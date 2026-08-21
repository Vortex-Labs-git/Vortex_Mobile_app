import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// DEVICE CARD
// =============================================================================
// One device row in the home device list. Shows avatar, name, ID,
// status dot + label, and a colored side bar. The whole card is tappable —
// the parent decides what to do based on device status.
//
// The pane is tinted by status, and so is the ring around the device image, so
// online / offline reads at a glance from the card itself rather than only
// from the label.
//
// Avatar logic (driven by the device ID prefix):
//   - VA*  → valve product image (assets/images/valve_v2.jpeg)
//   - SU*  → sensor icon
//   - else → neutral unknown-device icon
//
// All status logic (online / offline / esp_connected) lives in the parent;
// this widget just receives the resolved [statusText] / [statusColor] values
// and the direct-connection flag that distinguishes a local AP link.
// =============================================================================

class DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final String statusText; // "Online" | "Offline" | "Direct Connected"
  final Color statusColor; // Green or red
  final bool isEspConnected; // Direct AP link — rings the avatar in brand teal
  final VoidCallback onTap;

  const DeviceCard({
    super.key,
    required this.device,
    required this.statusText,
    required this.statusColor,
    required this.isEspConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String name =
        device['name'] ??
        device['vwv_name'] ??
        device['device_name'] ??
        'Unknown Device';
    final String id = device['id']?.toString() ?? '';
    final String idPrefix = id.toUpperCase();
    final bool isValve = idPrefix.startsWith('VA'); // valve image
    final bool isSensor = idPrefix.startsWith('SU'); // sensor icon

    // The ring around the device image tells the same story as the pill and the
    // status edge, so it must not stay a friendly teal on an offline device:
    //   offline          → red, matching the rest of the card
    //   direct connected → brand teal, because a local AP link is a different
    //                      kind of "connected" (no cloud, manual control only)
    //   online           → green
    final Color accent = isEspConnected ? GlassTokens.primary : statusColor;

    return GlassSurface(
      margin: const EdgeInsets.only(bottom: 14),
      borderRadius: BorderRadius.circular(GlassTokens.radiusLg),
      tint: statusColor,
      tintStrength: 0.14,
      onTap: onTap,
      // The status edge is a Stack layer rather than a stretched Row child so
      // the row needs no IntrinsicHeight — that measures every row twice, on
      // every list layout, for a 6px strip.
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                // ───────────────────────────────────────────────────────
                // Avatar: valve image for VA-*, sensor icon for SU-*,
                // neutral icon otherwise
                // ───────────────────────────────────────────────────────
                Container(
                  width: 68,
                  height: 68,
                  margin: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.55),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.20),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: isValve
                      ? ClipOval(
                          child: Image.asset(
                            'assets/images/valve_v2.jpeg',
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Center(
                          child: Icon(
                            isSensor ? Icons.sensors : Icons.device_unknown,
                            size: 34,
                            color: accent,
                          ),
                        ),
                ),

                // ───────────────────────────────────────────────────────
                // Name + ID + status row
                // ───────────────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Device name
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: GlassTokens.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 2),

                        // Device ID
                        Text(
                          "ID: $id",
                          style: const TextStyle(
                            color: GlassTokens.textMuted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 8),

                        // Status pill (dot + label) — tinted glass capsule
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GlassPill(
                            tint: statusColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: statusColor.withValues(
                                          alpha: 0.55,
                                        ),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color.lerp(
                                      statusColor,
                                      Colors.black,
                                      0.30,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ───────────────────────────────────────────────────────
                // Chevron
                // ───────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: GlassTokens.textMuted.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────────────────────────────
          // Right status edge — stretched to the row's height by the Stack
          // ─────────────────────────────────────────────────────────────
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    statusColor.withValues(alpha: 0.85),
                    statusColor.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
