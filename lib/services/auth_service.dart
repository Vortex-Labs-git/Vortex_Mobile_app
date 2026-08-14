import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_service.dart';
import 'local_storage_service.dart';

class AuthService {
  static const String baseUrl = 'https://vortexlabsofficial.com/device_app';

  static Map<String, dynamic>? currentUser;
  static String? _token;

  static bool get isLoggedIn => currentUser != null;

  // ============================================================
  // JWT TOKEN EXPIRY CHECK
  // ============================================================
  /// Decode the JWT payload and check if it's expired or close to expiry.
  /// Returns true if the token is expired or will expire within 5 minutes.
  /// JWT format: header.payload.signature (base64url encoded)
  static bool isTokenExpired() {
    if (_token == null) return true;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return true;

      // Decode the payload (middle part)
      // base64Url.normalize adds padding if needed
      final payloadStr = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final payload = jsonDecode(payloadStr);

      // Check 'exp' claim (Unix timestamp in seconds)
      final exp = payload['exp'];
      if (exp == null) return false; // No expiry = never expires

      final expiryDate = DateTime.fromMillisecondsSinceEpoch(
        (exp is int ? exp : int.parse(exp.toString())) * 1000,
      );

      // Consider expired if less than 5 minutes remaining
      final now = DateTime.now();
      final isExpired = now.isAfter(
        expiryDate.subtract(const Duration(minutes: 5)),
      );

      if (isExpired) {
        print("🔑 Token expires at: $expiryDate (now: $now) → EXPIRED/EXPIRING");
      } else {
        print("🔑 Token expires at: $expiryDate (now: $now) → still valid");
      }

      return isExpired;
    } catch (e) {
      print("⚠️ Token decode error: $e — treating as expired");
      return true;
    }
  }

  // ============================================================
  // SILENT TOKEN REFRESH
  // ============================================================
  /// Try to get a fresh token using saved credentials.
  /// Returns true if refresh succeeded, false if user must re-login manually.
  static Future<bool> _silentRefresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUsername = prefs.getString('saved_username');
      final savedPassword = prefs.getString('saved_password');

      if (savedUsername == null || savedPassword == null) {
        print("🔑 No saved credentials — cannot silent refresh");
        return false;
      }

      print("🔑 Silent refresh: logging in as $savedUsername...");

      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': savedUsername,
          'password': savedPassword,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Silent refresh timed out');
        },
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        currentUser = data['user'];
        _token = data['access_token'];

        // Save the new token
        await prefs.setString('access_token', _token!);
        await prefs.setString('user_data', jsonEncode(currentUser));

        print("✅ Silent refresh succeeded — new token saved");
        return true;
      } else {
        print("❌ Silent refresh failed: ${data['message']}");
        // Credentials may have been changed by admin — force manual login
        return false;
      }
    } catch (e) {
      print("❌ Silent refresh error: $e");
      // Network error — might be in AP mode, don't force logout
      // Just continue with old token, WebSocket will fail gracefully
      return false;
    }
  }

  // ============================================================
  // 1. Check if user is already logged in (app start)
  // ============================================================
  /// IMPORTANT: This must NOT block app startup.
  /// When phone is connected to ESP32 hotspot (no internet),
  /// WebSocket.connect() would hang forever. So we fire-and-forget it.
  static Future<bool> checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final userDataString = prefs.getString('user_data');

      if (token != null && userDataString != null) {
        _token = token;
        currentUser = jsonDecode(userDataString);

        // ✅ CHECK TOKEN EXPIRY
        if (isTokenExpired()) {
          print("🔑 Token expired — attempting silent refresh...");

          final refreshed = await _silentRefresh();
          if (!refreshed) {
            // Could not refresh (no saved creds, or server rejected, or no internet)
            // If no internet (AP mode), continue with expired token — WebSocket will fail
            // but the app can still work in direct ESP32 mode.
            // Check if we have saved credentials at all:
            final hasCreds = prefs.getString('saved_username') != null;
            if (!hasCreds) {
              // No saved credentials → must force manual login
              print("🔑 No saved credentials — forcing manual login");
              await _clearSession();
              return false;
            }
            // Has credentials but refresh failed (likely no internet / AP mode)
            // Continue — app will work in offline/direct mode
            print("🔑 Refresh failed but has creds — continuing in offline mode");
          } else {
            print("✅ login successful for: ${currentUser!['name']}");
          }
        } else {
          print("✅ Auto-login successful for: ${currentUser!['name']}");
        }

        // Fire-and-forget: try server WebSocket in background
        // Do NOT await — this lets the app start instantly
        // even when connected to ESP32 hotspot (no internet)
        WebSocketService.connect().then((connected) {
          if (connected) {
            print("🔌 WS: Background connect succeeded");
          } else {
            print("🔌 WS: Background connect failed (offline mode)");
          }
        }).catchError((e) {
          print("🔌 WS: Background connect error: $e");
        });

        return true;
      }
    } catch (e) {
      print("❌ Error restoring session: $e");
    }
    return false;
  }

  // ============================================================
  // 2. Login and Save Token
  // ============================================================
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        currentUser = data['user'];
        _token = data['access_token'];

        print("🔑 LOGIN TOKEN: $_token");

        // Save to phone storage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _token!);
        await prefs.setString('user_data', jsonEncode(currentUser));

        // ✅ SAVE CREDENTIALS for silent refresh
        await prefs.setString('saved_username', username);
        await prefs.setString('saved_password', password);

        // Connect WebSocket after login (this is fine to await here
        // because login requires internet anyway)
        await WebSocketService.connect();
      }

      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================================
  // 2b. Change Password (REST API)
  // ============================================================
  /// Changes the account password via change_password.php.
  /// On success, updates saved_password in SharedPreferences so silent
  /// token refresh keeps working — otherwise the next token expiry would
  /// fail to refresh and force a manual re-login.
  static Future<Map<String, dynamic>> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      final response = await http.post(
        Uri.parse('$baseUrl/change_password.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );

      print("🔑 Change Password Response: ${response.body}");

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        // CRITICAL: keep saved_password in sync for silent refresh
        await prefs.setString('saved_password', newPassword);
        print("✅ Password changed — saved_password updated");
      }

      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================================
  // 3. Logout and Clear Data
  // ============================================================
  static Future<void> logout() async {
    // Disconnect WebSocket first
    WebSocketService.disconnect();

    // Clear cached device list
    await LocalStorageService.clearCache();

    currentUser = null;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // This clears saved_username/password too
    print("✅ Logged out, WebSocket disconnected & cache cleared");
  }

  // ============================================================
  // INTERNAL: Clear session without clearing saved credentials
  // ============================================================
  /// Used when token expired and refresh failed.
  /// Clears token and user data but keeps credentials for next attempt.
  static Future<void> _clearSession() async {
    WebSocketService.disconnect();
    currentUser = null;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('user_data');
    // NOTE: We do NOT remove saved_username/saved_password here
    // so that login screen could potentially pre-fill them
    print("🔑 Session cleared (credentials kept for next login)");
  }

  // ============================================================
  // PUBLIC: Force refresh token (call from anywhere)
  // ============================================================
  /// Call this when WebSocket gets rejected or any API returns 401.
  /// Returns true if refresh succeeded and WebSocket reconnected.
  static Future<bool> refreshTokenAndReconnect() async {
    print("🔑 refreshTokenAndReconnect called...");
    final refreshed = await _silentRefresh();
    if (refreshed) {
      // Reconnect WebSocket with new token
      // Use skipExpiryCheck: true to avoid loop
      // (connect would see token is fresh and not call refresh again anyway,
      //  but this is a safety guard)
      WebSocketService.disconnect();
      final connected = await WebSocketService.connect(skipExpiryCheck: true);
      print("🔌 WS reconnect after refresh: $connected");
      return connected;
    }
    return false;
  }
}