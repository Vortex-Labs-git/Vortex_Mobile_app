import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';

class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Transparent: this tab sits on MainScreen's gradient backdrop.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // ── Header ──
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.45),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                    boxShadow: GlassTokens.paneShadow(y: 8, blurRadius: 22),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 40,
                    color: GlassTokens.primary,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'User Manual',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: GlassTokens.primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Vortex Smart Valve — Complete Guide',
                  style: TextStyle(
                    fontSize: 14,
                    color: GlassTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),

            const SizedBox(height: 28),

            // ── 1. Getting Started ──
            _buildSectionCard(
              icon: Icons.play_circle_outline,
              title: '1. Getting Started',
              children: [
                _buildStep('1', 'Open the Vortex Labs app and log in with your username and password.'),
                _buildStep('2', 'Once logged in, the Home screen shows all valves assigned to your account.'),
                _buildStep('3', 'Each valve card shows the device name, ID, and connection status (Online, Offline, or Direct Connected).'),
                _buildNote('If you see no devices, contact Vortex Labs to get valves assigned to your account.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 2. Connection Methods ──
            _buildSectionCard(
              icon: Icons.wifi,
              title: '2. Connection Methods',
              children: [
                _buildSubTitle('Cloud Connection (Normal Mode)'),
                _buildBullet('Your valve connects to your home/office WiFi and communicates through the Vortex cloud server.'),
                _buildBullet('The app shows a green "Live updates active" bar at the top when connected.'),
                _buildBullet('You can control the valve from anywhere in the world.'),
                const SizedBox(height: 12),
                _buildSubTitle('Direct Connection (ESP32 Direct Mode)'),
                _buildBullet('Use this when the valve has no internet connection or for initial WiFi setup.'),
                _buildBullet('The valve creates its own WiFi hotspot named "Vortex_VAXXXXXXXXX".'),
                const SizedBox(height: 8),
                _buildNote('Direct mode only supports manual valve control. Schedule and sensor features require a cloud connection.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 3. How to Connect Directly to a Valve ──
            _buildSectionCard(
              icon: Icons.settings_remote,
              title: '3. Direct Connection Setup',
              children: [
                _buildStep('1', 'Make sure the valve is powered on. If it has no WiFi configured, it will automatically create a hotspot named "Vortex_VAXXXXXXXXX".'),
                _buildStep('2', 'On your phone, go to WiFi Settings and connect to the valve\'s hotspot (e.g., "Vortex_VA202601001").'),
                _buildStep('3', 'Open the Vortex Labs app. The app will automatically detect the valve\'s hotspot and attempt to connect directly.'),
                _buildStep('4', 'Once connected, the valve card will show "Direct Connected" in green.'),
                _buildStep('5', 'Tap the valve card to open the control screen. You can now control the valve directly.'),
                const SizedBox(height: 8),
                _buildNote('The app will automatically switch to direct mode when you connect to a valve hotspot, and back to cloud mode when you reconnect to your normal WiFi.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 4. Controlling the Valve ──
            _buildSectionCard(
              icon: Icons.tune,
              title: '4. Controlling the Valve',
              children: [
                _buildSubTitle('Open / Close Mode (State Control)'),
                _buildBullet('When the toggle switch on the Valve Control card is ON, you are in Open/Close mode.'),
                _buildBullet('Tap "Open" to fully open the valve (90°) or "Close" to fully close it (0°).'),
                _buildBullet('The "Actual position" row shows the real-time position of the valve in degrees.'),
                const SizedBox(height: 12),
                _buildSubTitle('Angle Mode (Precise Control)'),
                _buildBullet('Toggle the switch OFF to enter Angle Control mode.'),
                _buildBullet('Use the slider to set a specific angle between 0° and 90°.'),
                _buildBullet('The rotating needle dial shows the current position visually.'),
                _buildBullet('Tap the "Set Angle to X°" button to send the command.'),
                _buildBullet('The "Actual position" row confirms the valve has moved to the requested angle.'),
                const SizedBox(height: 8),
                _buildNote('There may be a small delay (a few seconds) between sending a command and the valve reaching its target position.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 5. Control Methods ──
            _buildSectionCard(
              icon: Icons.dashboard_outlined,
              title: '5. Control Methods',
              children: [
                _buildSubTitle('Manual'),
                _buildBullet('You directly control the valve position using the Open/Close buttons or the angle slider.'),
                const SizedBox(height: 12),
                _buildSubTitle('Schedule'),
                _buildBullet('Set automatic open and close times for each day of the week.'),
                _buildBullet('Use the Manual/Schedule toggle at the top to switch between manual and scheduled operation.'),
                _buildBullet('When Schedule mode is active, the valve follows the set timetable automatically.'),
                _buildBullet('Tap on a day\'s time to change the open (green) or close (red) time.'),
                _buildBullet('Press "Save Schedule" to apply changes.'),
                const SizedBox(height: 12),
                _buildSubTitle('Sensor (Coming Soon)'),
                _buildBullet('Sensor-based control will allow the valve to respond automatically to environmental conditions.'),
                const SizedBox(height: 8),
                _buildNote('Schedule and Sensor modes require a cloud connection and are not available in Direct mode.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 6. Device Info ──
            _buildSectionCard(
              icon: Icons.info_outline,
              title: '6. Device Information',
              children: [
                _buildBullet('Product Type — The hardware model of your valve (e.g., WiFi Valve v1).'),
                _buildBullet('Name — A custom name for your valve. Tap "Edit" to rename it.'),
                _buildBullet('Connection Status — Shows whether the valve is Online, Offline, or Direct Connected.'),
                _buildBullet('If the valve shows "Offline", check that it is powered on and connected to WiFi.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 7. WiFi Setup for the Valve ──
            _buildSectionCard(
              icon: Icons.wifi_lock,
              title: '7. WiFi Setup for the Valve',
              children: [
                _buildStep('1', 'Connect your phone to the valve\'s hotspot (Vortex_VAXXXXXXXXX).'),
                _buildStep('2', 'Open the app and tap on the valve card (it will show "Direct Connected").'),
                _buildStep('3', 'In the control screen, you can configure the valve\'s WiFi settings to connect it to your home/office network.'),
                _buildStep('4', 'Enter your WiFi network name (SSID) and password.'),
                _buildStep('5', 'The valve will restart and connect to your WiFi. It will then appear as "Online" in the app.'),
                const SizedBox(height: 8),
                _buildNote('After WiFi setup, reconnect your phone to your normal WiFi network. The valve will be accessible through the cloud.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 8. Troubleshooting ──
            _buildSectionCard(
              icon: Icons.build_outlined,
              title: '8. Troubleshooting',
              children: [
                _buildSubTitle('Valve shows "Offline"'),
                _buildBullet('Check that the valve is powered on.'),
                _buildBullet('Verify the valve is connected to your WiFi network.'),
                _buildBullet('Try pulling down on the Home screen to refresh the device list.'),
                const SizedBox(height: 12),
                _buildSubTitle('Cannot connect directly'),
                _buildBullet('Make sure your phone is connected to the valve\'s hotspot (Vortex_VAXXXXXXXXX).'),
                _buildBullet('The valve creates a hotspot only when it has no WiFi configured or cannot reach its saved network.'),
                _buildBullet('Ensure you are within range of the valve (typically 10–20 meters).'),
                const SizedBox(height: 12),
                _buildSubTitle('Valve not responding to commands'),
                _buildBullet('Wait a few seconds — the valve may take time to reach the target position.'),
                _buildBullet('Check the "Actual position" to verify the valve has moved.'),
                _buildBullet('If the valve still does not respond, try power cycling it.'),
                const SizedBox(height: 12),
                _buildSubTitle('App shows "Offline — showing cached devices"'),
                _buildBullet('Your phone may not have an internet connection.'),
                _buildBullet('The Vortex cloud server may be temporarily unreachable.'),
                _buildBullet('Cached data is shown so you can still see your device list. Control requires a live connection.'),
              ],
            ),

            const SizedBox(height: 20),

            // ── 9. Contact & Support ──
            _buildSectionCard(
              icon: Icons.support_agent,
              title: '9. Contact & Support',
              children: [
                _buildContactRow(Icons.email, 'info@vortexlabsofficial.com'),
                const SizedBox(height: 8),
                _buildContactRow(Icons.phone, '+94 70 554 9401'),
                const SizedBox(height: 8),
                _buildContactRow(Icons.language, 'www.vortexlabsofficial.com'),
              ],
            ),

            const SizedBox(height: 30),

            // ── Footer ──
            const Center(
              child: Text(
                '© 2025 Vortex Labs Official',
                style: TextStyle(color: GlassTokens.textMuted, fontSize: 13),
              ),
            ),

            const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Card wrapper ──
  static Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: GlassTokens.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                child: Icon(icon, color: GlassTokens.primary, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: GlassTokens.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  // ── Step with number ──
  static Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: GlassTokens.accentGradient,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: GlassTokens.primary.withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14, color: GlassTokens.textSecondary, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bullet point ──
  static Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 6, color: GlassTokens.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 14, color: GlassTokens.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-title ──
  static Widget _buildSubTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: GlassTokens.textPrimary,
        ),
      ),
    );
  }

  // ── Note/tip box ──
  // Amber-tinted glass so tips read as a distinct layer inside the card
  // without going back to a flat opaque box.
  static Widget _buildNote(String text) {
    return GlassCard(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      tint: GlassTokens.warning,
      tintStrength: 0.22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline,
            color: Color(0xFFB45309),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6D4C00),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Contact row ──
  static Widget _buildContactRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: GlassTokens.primary, size: 20),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: GlassTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
