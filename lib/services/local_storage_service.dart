import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// Local Storage Service - Device Cache
/// ============================================================
/// Saves the device list locally so HomeScreen can display devices
/// even when the server is unreachable (offline/AP mode).
///
/// Architecture Doc (Page 4):
/// "When a Mobile app receives the initial device data, the App
///  needs to save them on local space to show the user devices
///  even in an offline state. Future help for operate on ESP32 AP mode"
///
/// Usage:
///   // Save when received from WebSocket:
///   await LocalStorageService.saveDeviceList(devices);
///
///   // Load on app start or when offline:
///   final cached = await LocalStorageService.getDeviceList();
///
///   // Check if a device ID belongs to this user:
///   bool isMine = await LocalStorageService.isUserDevice('VA202601001');
/// ============================================================

class LocalStorageService {
  static const String _deviceListKey = 'cached_device_list';
  static const String _lastSyncKey = 'device_list_last_sync';

  // ============================================================
  // SAVE: Cache the device list from server WebSocket
  // ============================================================
  /// Save device list received from WebSocket to local storage.
  /// Call this every time `devices_data` event is received.
  static Future<void> saveDeviceList(List<dynamic> devices) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(devices);
      await prefs.setString(_deviceListKey, jsonString);
      await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
      print("💾 LocalStorage: Saved ${devices.length} devices to cache");
    } catch (e) {
      print("❌ LocalStorage: Failed to save device list: $e");
    }
  }

  // ============================================================
  // LOAD: Get cached device list
  // ============================================================
  /// Load the cached device list from local storage.
  /// Returns empty list if no cache exists.
  static Future<List<dynamic>> getDeviceList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_deviceListKey);

      if (jsonString == null || jsonString.isEmpty) {
        print("💾 LocalStorage: No cached device list found");
        return [];
      }

      final List<dynamic> devices = jsonDecode(jsonString);
      print("💾 LocalStorage: Loaded ${devices.length} devices from cache");
      return devices;
    } catch (e) {
      print("❌ LocalStorage: Failed to load device list: $e");
      return [];
    }
  }

  // ============================================================
  // CHECK: Is a device ID in the user's cached list?
  // ============================================================
  /// Check if a given device_id belongs to the current user.
  /// Used during ESP32 AP mode to verify the connected valve
  /// is assigned to this user account.
  ///
  /// Architecture Doc (Page 10):
  /// "On the mobile app side, the app already knows which device IDs
  ///  belong to the user, as this data is stored locally."
  static Future<bool> isUserDevice(String deviceId) async {
    try {
      final devices = await getDeviceList();
      return devices.any((device) =>
          device['id']?.toString() == deviceId);
    } catch (e) {
      print("❌ LocalStorage: Error checking device ownership: $e");
      return false;
    }
  }

  // ============================================================
  // GET: Device data by ID from cache
  // ============================================================
  /// Get a specific device's cached data by its ID.
  /// Useful when navigating to DeviceDetailScreen in offline mode.
  static Future<Map<String, dynamic>?> getDeviceById(String deviceId) async {
    try {
      final devices = await getDeviceList();
      final match = devices.firstWhere(
        (device) => device['id']?.toString() == deviceId,
        orElse: () => null,
      );
      return match != null ? Map<String, dynamic>.from(match) : null;
    } catch (e) {
      print("❌ LocalStorage: Error getting device by ID: $e");
      return null;
    }
  }

  // ============================================================
  // META: Last sync time
  // ============================================================
  /// Get the timestamp of the last successful device list sync.
  static Future<String?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncKey);
  }

  // ============================================================
  // CLEAR: Remove cached data (on logout)
  // ============================================================
  /// Clear all cached device data. Call this on logout.
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_deviceListKey);
      await prefs.remove(_lastSyncKey);
      print("💾 LocalStorage: Cache cleared");
    } catch (e) {
      print("❌ LocalStorage: Failed to clear cache: $e");
    }
  }
}
