// =============================================================================
// ENV — every network endpoint in the app, in one place
// =============================================================================
// If the backend moves (new host, new port, http → https, ws → wss), this is
// the ONLY file that changes. Nothing else in the app should contain a URL,
// a host, or a port literal.
// =============================================================================

class Env {
  // ---- Cloud REST API ----
  static const String apiBase = 'https://vortexlabsofficial.com/vortex_app';

  static String get loginUrl => '$apiBase/login.php';
  static String get changePasswordUrl => '$apiBase/change_password.php';
  static String get controlDeviceUrl => '$apiBase/control_device.php';

  // ---- Cloud WebSocket (PHP Ratchet server) ----
  // Switch wsScheme to 'wss' once the server has TLS; nothing else changes.
  static const String wsScheme = 'ws';
  static const String wsHost = '82.29.161.52';
  static const int wsPort = 8085;

  static String get wsUrl => '$wsScheme://$wsHost:$wsPort';

  // ---- ESP32 direct (AP mode) ----
  // Owned by the ESP32 firmware — the valve's own hotspot, no internet.
  // The httpd server runs on port 80 and registers the WebSocket at /ws.
  static const String espIp = '192.168.4.1';
  static const int espPort = 80;
  static const String espPath = '/ws';
}
