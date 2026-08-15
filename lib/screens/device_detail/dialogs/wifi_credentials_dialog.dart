import 'package:flutter/material.dart';

import '../../../services/esp_direct_service.dart';

// =============================================================================
// WIFI CREDENTIALS DIALOG (Direct mode)
// =============================================================================
// Collects home WiFi SSID + password and sends set_valve_wifi to the connected
// ESP32. Architecture Doc Page 13. The ESP32 restarts afterwards, so the direct
// connection is expected to drop right after sending.
// =============================================================================

/// Delay before closing the dialog — gives the ESP32 time to store the
/// credentials before it restarts.
const Duration _restartGrace = Duration(seconds: 3);

Future<void> showWifiCredentialsDialog(BuildContext context) {
  final ssidController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  bool isSending = false;

  // Captured up front so the success message still works after the dialog
  // (and its context) is gone.
  final messenger = ScaffoldMessenger.of(context);

  void showMessage(String message, {Color? color, Duration? duration}) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void send() {
          final ssid = ssidController.text.trim();
          final password = passwordController.text;

          if (ssid.isEmpty) {
            showMessage('Please enter WiFi name');
            return;
          }

          if (!EspDirectService.instance.isAuthenticated) {
            showMessage(
              'Not connected to valve. Go back and reconnect.',
              color: Colors.red,
            );
            return;
          }

          setDialogState(() => isSending = true);

          EspDirectService.instance.setWifiCredentials(
            ssid: ssid,
            password: password,
          );

          print("📤 ESP32: set_valve_wifi ssid=$ssid");

          // ESP32 will restart — the connection will be lost.
          Future.delayed(_restartGrace, () {
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            showMessage(
              'WiFi credentials sent! Valve will restart and connect to your home WiFi.',
              color: Colors.green,
              duration: const Duration(seconds: 5),
            );
          });
        }

        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi, color: Color(0xFF3F51B5)),
              SizedBox(width: 10),
              Text('Set Home WiFi'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your home WiFi credentials. The valve will restart and connect to this network.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ssidController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'WiFi Name (SSID)',
                  hintText: 'Enter your home WiFi name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'WiFi Password',
                  hintText: 'Enter WiFi password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () {
                      setDialogState(() => obscurePassword = !obscurePassword);
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isSending ? null : send,
              icon: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(isSending ? 'Sending...' : 'Save & Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    ),
  ).whenComplete(() {
    ssidController.dispose();
    passwordController.dispose();
  });
}
