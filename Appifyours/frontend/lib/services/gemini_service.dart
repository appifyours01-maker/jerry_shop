import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  String _apiKey = '';
  String _groqApiKey = '';
  bool _keysLoaded = false;
  
  // Fallback chain of models to try
  static const List<String> _modelFallbackChain = [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemma-3-27b-it',
    'groq-api', // Groq API as fallback when Gemini quota reached
  ];
  
  GenerativeModel? _model;
  ChatSession? _chatSession;
  int _currentModelIndex = 0;
  
  // Store context data
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic> _storeInfo = {};
  Map<String, dynamic> _businessDetails = {};

  GeminiService() {
    _loadApiKeys();
  }

  // Load API keys from backend
  Future<void> _loadApiKeys() async {
    try {
      // Use dotenv for base URL (same as ApiService)
      final baseUrl = dotenv.env['API_BASE']?.trim() ?? 'http://127.0.0.1:5000';
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token == null) {
        print('GeminiService: No auth token found, cannot load API keys');
        return;
      }

      // Try multiple endpoints for API keys
      // 1. Main app endpoint: /api/user/ai-api-keys
      // 2. Generated app endpoint: /ai-api-keys
      final endpoints = [
        '/api/user/ai-api-keys',
        '/ai-api-keys'
      ];

      for (final endpoint in endpoints) {
        try {
          final response = await http.get(
            Uri.parse('$baseUrl$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true && data['data'] != null) {
              _apiKey = data['data']['geminiApiKey'] ?? '';
              _groqApiKey = data['data']['groqApiKey'] ?? '';
              _keysLoaded = true;
              print('GeminiService: API keys loaded from backend via $endpoint');
              _initializeModel();
              return; // Success, exit the loop
            }
          }
        } catch (e) {
          print('GeminiService: Failed to load API keys from $endpoint: $e');
          // Continue to next endpoint
        }
      }

      print('GeminiService: Failed to load API keys from all endpoints');
    } catch (e) {
      print('GeminiService: Error loading API keys: $e');
    }
  }

  void _initializeModel() {
    if (!_keysLoaded || _apiKey.isEmpty) {
      print('GeminiService: API keys not loaded yet, skipping initialization');
      return;
    }
    
    final currentModel = _modelFallbackChain[_currentModelIndex];
    
    if (currentModel == 'groq-api') {
      // Groq API uses different API, not GenerativeModel
      print('GeminiService: Initialized with Groq API (as fallback)');
      return;
    }
    
    _model = GenerativeModel(
      model: currentModel,
      apiKey: _apiKey,
    );
    _chatSession = _model!.startChat();
    print('GeminiService: Initialized with model: $currentModel');
  }
  
  // Call Groq API as fallback
  Future<String> _callGroqAPI(String message) async {
    try {
      final systemContext = _buildSystemContext();
      
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {'role': 'system', 'content': systemContext},
            {'role': 'user', 'content': message},
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] ?? '';
        return content;
      } else {
        throw Exception('Groq API error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error calling Groq API: $e');
      rethrow;
    }
  }

  void _tryNextModel() {
    if (_currentModelIndex < _modelFallbackChain.length - 1) {
      _currentModelIndex++;
      print('GeminiService: Falling back to model: ${_modelFallbackChain[_currentModelIndex]}');
      _initializeModel();
    } else {
      print('GeminiService: All models exhausted, no more fallback options');
    }
  }

  // Update product data
  void updateProducts(List<Map<String, dynamic>> products) {
    _products = products;
    _updateSystemContext();
  }

  // Update store info
  void updateStoreInfo(Map<String, dynamic> storeInfo) {
    _storeInfo = storeInfo;
    _updateSystemContext();
  }

  // Update business details
  void updateBusinessDetails(Map<String, dynamic> businessDetails) {
    _businessDetails = businessDetails;
    _updateSystemContext();
  }

  // Build comprehensive system context with all shop data
  String _buildSystemContext() {
    final storeName = _storeInfo['storeName'] ?? _storeInfo['shopName'] ?? _storeInfo['appName'] ?? _businessDetails['storeName'] ?? _businessDetails['shopName'] ?? 'My Store';
    final storeAddress = _storeInfo['address'] ?? _businessDetails['address'] ?? 'Not available';
    final storeEmail = _storeInfo['email'] ?? _businessDetails['email'] ?? 'Not available';
    final storePhone = _storeInfo['phone'] ?? _businessDetails['phone'] ?? 'Not available';
    final gstNumber = _businessDetails['gstNumber'] ?? 'Not available';
    final businessCategory = _businessDetails['category'] ?? 'General';

    // Count products with discounts - check multiple possible discount field names
    int productsWithDiscount = 0;
    String productInfo = '';
    if (_products.isNotEmpty) {
      productInfo = '\n\nPRODUCT CATALOG (${_products.length} products):\n';
      for (int i = 0; i < _products.length; i++) {
        final product = _products[i];
        final name = product['productName'] ?? product['name'] ?? 'Unknown Product';
        final price = product['price'] ?? '0';
        // Check multiple possible discount field names
        final discountPrice = product['discountPrice'] ?? product['discount_price'] ?? product['offerPrice'] ?? product['offer_price'] ?? product['salePrice'] ?? product['sale_price'];
        final discount = product['discount'] ?? product['discountPercentage'] ?? product['discount_percentage'];
        final discountPercent = product['discountPercent'];
        final description = product['description'] ?? 'No description available';
        final category = product['category'] ?? 'General';
        final stock = product['stock'] ?? product['quantity'] ?? product['inventory'] ?? 'Not specified';
        final sku = product['sku'] ?? product['productId'] ?? product['product_id'] ?? 'Not specified';
        
        // Check if product has any discount/offer
        bool hasDiscount = false;
        // Check discountPrice field
        if (discountPrice != null && discountPrice.toString().isNotEmpty && discountPrice.toString() != '0' && discountPrice.toString() != 'null') {
          hasDiscount = true;
        }
        // Check discountPercent field
        if (discount != null && discount.toString().isNotEmpty && discount.toString() != '0' && discount.toString() != 'null') {
          hasDiscount = true;
        }
        // Also check for discountPercent directly from product
        if (discountPercent != null && discountPercent.toString().isNotEmpty && discountPercent.toString() != '0' && discountPercent.toString() != 'null') {
          hasDiscount = true;
        }
        
        if (hasDiscount) {
          productsWithDiscount++;
        }
        
        productInfo += '${i + 1}. $name\n';
        productInfo += '   - SKU/ID: $sku\n';
        productInfo += '   - Price: $price\n';
        if (hasDiscount) {
          if (discountPrice != null && discountPrice.toString().isNotEmpty && discountPrice.toString() != 'null') {
            productInfo += '   - Discount/Offer Price: $discountPrice (HAS OFFER)\n';
          }
          if (discountPercent != null && discountPercent.toString().isNotEmpty && discountPercent.toString() != 'null') {
            productInfo += '   - Discount Percentage: $discountPercent%\n';
          }
        }
        productInfo += '   - Stock/Inventory: $stock\n';
        productInfo += '   - Category: $category\n';
        productInfo += '   - Description: $description\n\n';
      }
    } else {
      productInfo = '\n\nPRODUCT CATALOG: No products currently available.';
    }

    return '''You are a helpful AI assistant for $storeName e-commerce store. You have complete knowledge about the store, products, ordering process, delivery, and all app features.

STORE INFORMATION:
- Store Name: $storeName
- Address: $storeAddress
- Email: $storeEmail
- Phone: $storePhone
- GST Number: $gstNumber
- Business Category: $businessCategory

$productInfo

PRODUCT STATISTICS:
- Total Products: ${_products.length}
- Products with Offers/Discounts: $productsWithDiscount
- Products without Offers: ${_products.length - productsWithDiscount}

COMPLETE APP INFORMATION:

ORDERING PROCESS (Step-by-Step):
1. Browse products on Home page with carousel slider
2. Click on any product to view details
3. Add product to cart with desired quantity
4. Review cart items and total price
5. Proceed to checkout
6. Enter delivery address (name, address, city, pincode, state, phone, email)
7. Select delivery time slot
8. Choose payment method (UPI, Card, or Cash on Delivery)
9. Confirm order and receive Order ID

DELIVERY INFORMATION (Shiprocket Integration):
- Delivery is handled through Shiprocket logistics service
- Multiple courier options: Delhivery (3-5 days), Ekart (4-6 days), XpressBees (2-4 days)
- Delivery time: 2-6 business days depending on courier selection
- Pincode serviceability check before order placement
- AWB (Air Waybill) code generated for tracking
- Real-time order tracking available in Orders section
- Tracking stages: Processing → Packed → Shipped → In Transit → Out for Delivery → Delivered
- Pickup location: Store warehouse (pincode 600124)
- Standard shipping fee applies (may be free above order threshold)
- Cash on Delivery (COD) available on most couriers

HOW TO RECEIVE DELIVERY:
- After order placement, you receive Order ID and AWB code
- Track order in Orders section using AWB code
- Courier will deliver to your provided address
- You may receive SMS/Email updates on delivery status
- Signature may be required upon delivery
- Contact courier directly if delivery issues arise

PAYMENT METHODS:
- UPI (Unified Payments Interface) - instant payment
- Credit/Debit Cards - Visa, Mastercard, RuPay
- Cash on Delivery (COD) - pay when you receive the order
- Prepaid payment options available

OFFERS & DISCOUNTS:
- $productsWithDiscount products currently have special offers/discounts
- Discounted products show both original price and discounted price
- Check individual product listings for current offers
- Cart-level discounts may apply during checkout
- Seasonal promotions on featured products

APP FEATURES:
- Home page with product carousel and featured items
- Product catalog with category filtering and search
- Cart management with quantity adjustments
- Wishlist to save favorite products
- Order history and tracking
- Real-time stock updates via WebSocket
- Multi-currency support
- GST calculation (typically 18%)
- Discount calculations on cart total
- Shipping fee calculation

STORE POLICIES:
- Return Policy: Items can be returned within specified period
- Refund Process: Initiated through Orders section
- Order Cancellation: Can be cancelled before shipping
- Stock Availability: Real-time updates shown in app

INSTRUCTIONS:
- Answer ALL questions about products, pricing, stock, store, ordering, delivery, tracking, offers, and app features using the comprehensive information above.
- If asked about product count: EXACTLY say "${_products.length} products"
- If asked about offers/discounts: EXACTLY say "$productsWithDiscount products have offers/discounts"
- Explain the complete ordering process when asked "how to order"
- Provide detailed delivery information including courier options and timeframes
- Explain order tracking with AWB codes and status updates
- Answer questions about payment methods, returns, refunds, and policies
- Guide users through app navigation and feature usage
- Be friendly, professional, and comprehensive in your answers
- Use the EXACT information provided in this system prompt
- If you don't have specific information, politely say so
- When mentioning prices, include currency symbols
- Always provide accurate stock information from product data
- If product is out of stock (stock = 0), inform user clearly''';
  }

  void _updateSystemContext() {
    // Send system context to the AI to train it with current data
    final systemContext = _buildSystemContext();
    try {
      if (_model == null) {
        print('Error updating system context: Model not initialized (backend may be down)');
        return;
      }
      // Create a new chat session with the system instruction
      _chatSession = _model!.startChat();
      // Send the system context as the first message to train the AI
      _chatSession!.sendMessage(Content.text(systemContext));
      print('System context updated and sent to AI');
    } catch (e) {
      print('Error updating system context: $e');
    }
  }

  // Send message and get response with fallback
  Future<String> sendMessage(String message) async {
    // Ensure API keys are loaded before sending message
    if (!_keysLoaded) {
      await _loadApiKeys();
      // Wait a bit for keys to load
      await Future.delayed(Duration(milliseconds: 500));
    }
    
    if (!_keysLoaded || _apiKey.isEmpty) {
      return 'Chatbot is currently unavailable. The backend server may be down. Please ensure the server is running and try again.';
    }
    
    // Check if model is initialized
    if (_model == null && _chatSession == null) {
      // Try to initialize the model
      _initializeModel();
      if (_model == null) {
        return 'Chatbot is initializing. Please try again in a moment.';
      }
    }
    
    int attempts = 0;
    final maxAttempts = _modelFallbackChain.length;
    
    while (attempts < maxAttempts) {
      try {
        final currentModel = _modelFallbackChain[_currentModelIndex];
        
        // Route to Groq API if it's the current model
        if (currentModel == 'groq-api') {
          return await _callGroqAPI(message);
        }
        
        // Use Gemini API for other models
        if (_chatSession == null) {
          return 'Chatbot session not initialized. Please try again.';
        }
        final response = await _chatSession!.sendMessage(Content.text(message));
        return response.text ?? 'I apologize, but I could not generate a response.';
      } catch (e) {
        print('Error in GeminiService with model ${_modelFallbackChain[_currentModelIndex]}: $e');
        
        // Check if error is quota/rate limit related or server error
        final errorString = e.toString().toLowerCase();
        final isQuotaError = errorString.contains('quota') || 
                             errorString.contains('rate limit') || 
                             errorString.contains('429') ||
                             errorString.contains('limit exceeded') ||
                             errorString.contains('503') ||
                             errorString.contains('high demand') ||
                             errorString.contains('unavailable') ||
                             errorString.contains('resource exhausted') ||
                             errorString.contains('billing') ||
                             errorString.contains('credit') ||
                             errorString.contains('usage') ||
                             errorString.contains('exceeded');
        
        // Always fallback to next model on any error for Gemini models
        // This ensures quota errors are caught even if the error message varies
        if (_currentModelIndex < _modelFallbackChain.length - 1) {
          print('GeminiService: Error detected, falling back to next model: ${_modelFallbackChain[_currentModelIndex + 1]}');
          _tryNextModel();
          // Resend the system context to the new model
          _updateSystemContext();
          attempts++;
          continue;
        }
        
        // If not a fallback error or no more models to try
        return 'I apologize, but I encountered an error processing your request. Please try again.';
      }
    }
    
    return 'I apologize, but all models are currently unavailable. Please try again later.';
  }

  // Get product count
  int get productCount => _products.length;

  // Get store name
  String get storeName => _storeInfo['storeName'] ?? _businessDetails['storeName'] ?? 'My Store';

  // Search products by name
  List<Map<String, dynamic>> searchProducts(String query) {
    if (query.isEmpty) return _products;
    
    final lowerQuery = query.toLowerCase();
    return _products.where((product) {
      final name = (product['productName'] ?? '').toString().toLowerCase();
      final description = (product['description'] ?? '').toString().toLowerCase();
      final category = (product['category'] ?? '').toString().toLowerCase();
      return name.contains(lowerQuery) || 
             description.contains(lowerQuery) || 
             category.contains(lowerQuery);
    }).toList();
  }

  // Get products by category
  List<Map<String, dynamic>> getProductsByCategory(String category) {
    if (category.isEmpty) return _products;
    
    final lowerCategory = category.toLowerCase();
    return _products.where((product) {
      final productCategory = (product['category'] ?? '').toString().toLowerCase();
      return productCategory.contains(lowerCategory);
    }).toList();
  }

  // Get product by name
  Map<String, dynamic>? getProductByName(String name) {
    final lowerName = name.toLowerCase();
    for (final product in _products) {
      final productName = (product['productName'] ?? '').toString().toLowerCase();
      if (productName == lowerName || productName.contains(lowerName)) {
        return product;
      }
    }
    return null;
  }

  // Get stock information for a product
  String? getProductStock(String productName) {
    final product = getProductByName(productName);
    if (product != null) {
      return (product['stock'] ?? product['quantity'] ?? product['inventory'] ?? 'Not specified').toString();
    }
    return null;
  }
}
