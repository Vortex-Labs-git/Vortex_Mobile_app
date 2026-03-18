import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_service.dart';

class AuthService {
  static const String baseUrl = 'https://vortexlabsofficial.com/vortex_app';

  static Map<String, dynamic>? currentUser;
  static String? _token;

  static bool get isLoggedIn => currentUser != null;

  // ============================================================
  // 1. Check if user is already logged in (app start)
  // ============================================================
  static Future<bool> checkLoginStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      final userDataString = prefs.getString('user_data');

      if (token != null && userDataString != null) {
        _token = token;
        currentUser = jsonDecode(userDataString);
        print("✅ Auto-login successful for: ${currentUser!['name']}");
        print("🔑 SAVED TOKEN: ${token.substring(0, 30)}...");

        // Connect WebSocket immediately after auto-login
        await WebSocketService.connect();

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

        // Connect WebSocket immediately after login
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
  // 3. Logout and Clear Data
  // ============================================================
  static Future<void> logout() async {
    // Disconnect WebSocket first
    WebSocketService.disconnect();

    currentUser = null;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    print("✅ Logged out & WebSocket disconnected");
  }
}
