import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Mobile Session Manager for Generated Apps
/// Handles session persistence, auth token storage, and user authentication state.
///
/// This file is automatically pushed to GitHub as part of the app generation
/// pipeline. Any changes here will be reflected in every newly generated app.
class MobileSessionManager extends ChangeNotifier {
  // ─── Shared Preferences Keys ────────────────────────────────────────────────
  static const String _keyAuthToken        = 'auth_token';
  static const String _keyUserId           = 'user_id';
  static const String _keyUserRole         = 'user_role';
  static const String _keyUserName         = 'user_name';
  static const String _keyUserEmail        = 'user_email';
  static const String _keyPhoneNumber      = 'user_phone';
  static const String _keyAdminId          = 'admin_id';
  static const String _keyAppId            = 'app_id';
  static const String _keyAppName          = 'app_name';
  static const String _keyProfileImage     = 'profile_image';
  static const String _keySessionCreatedAt = 'session_created_at';
  static const String _keyLastActivityAt   = 'last_activity_at';

  /// Session expires after 24 hours of inactivity
  static const Duration _sessionTimeout = Duration(hours: 24);

  // ─── Singleton ───────────────────────────────────────────────────────────────
  static final MobileSessionManager _instance = MobileSessionManager._internal();
  factory MobileSessionManager() => _instance;
  MobileSessionManager._internal();

  // ─── In-Memory State ─────────────────────────────────────────────────────────
  String? _authToken;
  String? _userId;
  String? _userRole;
  String? _userName;
  String? _userEmail;
  String? _phoneNumber;
  String? _adminId;
  String? _appId;
  String? _appName;
  String? _profileImage;
  DateTime? _sessionCreatedAt;
  DateTime? _lastActivityAt;

  // ─── Getters ─────────────────────────────────────────────────────────────────
  String? get authToken        => _authToken;
  String? get userId           => _userId;
  String? get userRole         => _userRole;
  String? get userName         => _userName;
  String? get userEmail        => _userEmail;
  String? get phoneNumber      => _phoneNumber;
  String? get adminId          => _adminId;
  String? get appId            => _appId;
  String? get appName          => _appName;
  String? get profileImage     => _profileImage;
  DateTime? get sessionCreatedAt => _sessionCreatedAt;
  DateTime? get lastActivityAt   => _lastActivityAt;
  
  set profileImage(String? url) {
    _profileImage = url;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      if (url != null) {
        prefs.setString(_keyProfileImage, url);
      } else {
        prefs.remove(_keyProfileImage);
      }
    });
  }

  /// Whether the user has a valid, non-expired session
  bool get isLoggedIn {
    if (_authToken == null || _userId == null) return false;
    if (isSessionExpired) return false;
    return true;
  }

  /// True if the last activity was more than [_sessionTimeout] ago
  bool get isSessionExpired {
    if (_lastActivityAt == null) return false;
    return DateTime.now().difference(_lastActivityAt!) > _sessionTimeout;
  }

  // ─── Role Helpers ─────────────────────────────────────────────────────────────
  bool hasRole(String requiredRole) =>
      _userRole?.toLowerCase() == requiredRole.toLowerCase();

  bool get isAdmin  => hasRole('admin') || hasRole('super_admin');
  bool get isVendor => hasRole('vendor');
  bool get isUser   => hasRole('user') || _userRole == null;

  // ─── Lifecycle ────────────────────────────────────────────────────────────────

  /// Initialize session manager: loads .env and restores saved session.
  /// Call this in `main()` before `runApp()`.
  Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
    } catch (_) {
      // .env may already be loaded — safe to ignore
    }
    await loadSession();
  }

  // ─── Persistence ─────────────────────────────────────────────────────────────

  /// Load session from SharedPreferences into memory.
  Future<void> loadSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _authToken        = prefs.getString(_keyAuthToken);
      _userId           = prefs.getString(_keyUserId);
      _userRole         = prefs.getString(_keyUserRole);
      _userName         = prefs.getString(_keyUserName);
      _userEmail        = prefs.getString(_keyUserEmail);
      _phoneNumber      = prefs.getString(_keyPhoneNumber);
      _adminId          = prefs.getString(_keyAdminId);
      _appId            = prefs.getString(_keyAppId);
      _appName          = prefs.getString(_keyAppName);
      _profileImage     = prefs.getString(_keyProfileImage);

      final createdStr  = prefs.getString(_keySessionCreatedAt);
      final activityStr = prefs.getString(_keyLastActivityAt);
      _sessionCreatedAt = createdStr  != null ? DateTime.tryParse(createdStr)  : null;
      _lastActivityAt   = activityStr != null ? DateTime.tryParse(activityStr) : null;

      debugPrint('📱 [MobileSession] Session loaded:');
      debugPrint('  userId      : $_userId');
      debugPrint('  role        : $_userRole');
      debugPrint('  token       : ${_authToken != null ? "✅ present" : "❌ missing"}');
      debugPrint('  loggedIn    : $isLoggedIn');
      debugPrint('  expired     : $isSessionExpired');

      notifyListeners();
    } catch (e) {
      debugPrint('❌ [MobileSession] Error loading session: $e');
    }
  }

  /// Bind authentication data after a successful login or signup response.
  ///
  /// Call this right after your login API call returns a token.
  Future<void> bindAuth({
    required String userId,
    required String token,
    String? role,
    String? name,
    String? email,
    String? phoneNumber,
    String? adminId,
    String? appId,
    String? appName,
    String? profileImage,
  }) async {
    try {
      final now = DateTime.now();

      _userId           = userId;
      _authToken        = token;
      _userRole         = role;
      _userName         = name;
      _userEmail        = email;
      _phoneNumber      = phoneNumber;
      _adminId          = adminId;
      _appId            = appId;
      _appName          = appName;
      _profileImage     = profileImage;
      _sessionCreatedAt = now;
      _lastActivityAt   = now;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAuthToken, token);
      await prefs.setString(_keyUserId,    userId);
      await prefs.setString(_keySessionCreatedAt, now.toIso8601String());
      await prefs.setString(_keyLastActivityAt,   now.toIso8601String());

      if (role        != null) await prefs.setString(_keyUserRole,    role);
      if (name        != null) await prefs.setString(_keyUserName,    name);
      if (email       != null) await prefs.setString(_keyUserEmail,   email);
      if (phoneNumber != null) await prefs.setString(_keyPhoneNumber, phoneNumber);
      if (adminId     != null) await prefs.setString(_keyAdminId,     adminId);
      if (appId       != null) await prefs.setString(_keyAppId,       appId);
      if (appName     != null) await prefs.setString(_keyAppName,     appName);
      if (profileImage!= null) await prefs.setString(_keyProfileImage,profileImage);

      debugPrint('✅ [MobileSession] Session bound:');
      debugPrint('  userId : $userId | role : $role | name : $name');

      notifyListeners();
    } catch (e) {
      debugPrint('❌ [MobileSession] Error binding auth: $e');
    }
  }

  /// Update the last-activity timestamp to keep the session alive.
  /// Call this on any meaningful user interaction.
  Future<void> touchActivity() async {
    try {
      _lastActivityAt = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastActivityAt, _lastActivityAt!.toIso8601String());
    } catch (e) {
      debugPrint('❌ [MobileSession] Error touching activity: $e');
    }
  }

  /// Update specific session fields (e.g., after a profile update).
  Future<void> updateSession({
    String? role,
    String? name,
    String? email,
    String? phoneNumber,
    String? appName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (role != null) {
        _userRole = role;
        await prefs.setString(_keyUserRole, role);
      }
      if (name != null) {
        _userName = name;
        await prefs.setString(_keyUserName, name);
      }
      if (email != null) {
        _userEmail = email;
        await prefs.setString(_keyUserEmail, email);
      }
      if (phoneNumber != null) {
        _phoneNumber = phoneNumber;
        await prefs.setString(_keyPhoneNumber, phoneNumber);
      }
      if (appName != null) {
        _appName = appName;
        await prefs.setString(_keyAppName, appName);
      }

      debugPrint('✅ [MobileSession] Session updated');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [MobileSession] Error updating session: $e');
    }
  }

  /// Clear all session data on logout.
  Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAuthToken);
      await prefs.remove(_keyUserId);
      await prefs.remove(_keyUserRole);
      await prefs.remove(_keyUserName);
      await prefs.remove(_keyUserEmail);
      await prefs.remove(_keyPhoneNumber);
      await prefs.remove(_keyAdminId);
      await prefs.remove(_keyAppId);
      await prefs.remove(_keyAppName);
      await prefs.remove(_keyProfileImage);
      await prefs.remove(_keySessionCreatedAt);
      await prefs.remove(_keyLastActivityAt);

      _authToken        = null;
      _userId           = null;
      _userRole         = null;
      _userName         = null;
      _userEmail        = null;
      _phoneNumber      = null;
      _adminId          = null;
      _appId            = null;
      _appName          = null;
      _profileImage     = null;
      _sessionCreatedAt = null;
      _lastActivityAt   = null;

      debugPrint('✅ [MobileSession] Session cleared');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [MobileSession] Error clearing session: $e');
    }
  }

  // ─── HTTP Helpers ─────────────────────────────────────────────────────────────

  /// Get the API base URL from .env
  String get apiBaseUrl =>
      dotenv.env['API_BASE'] ?? 'http://localhost:5000';

  /// Authorization headers ready for API requests
  Map<String, String> get authHeaders {
    if (_authToken == null) {
      return {'Content-Type': 'application/json'};
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_authToken',
    };
  }

  /// Convenience getter — same as [authHeaders]
  Map<String, String> get headers => authHeaders;
}
