import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// CONNECTION STATUS BAR
// =============================================================================
// Tappable status capsule above the device list. Three possible states:
//   - GREEN  "Live updates active"            (server WS connected)
//   - INDIGO "Direct mode — <ssid>"           (phone is on a Vortex_VA AP)
//   - ORANGE "Offline — showing cached..."    (no server, no AP)
//
// The one-line summary rarely tells the user what a state actually means for
// them, so tapping expands an explanation of what works in that mode.
//
// The dot pulses for a few seconds when the connection comes up, then settles.
// It deliberately does NOT pulse forever: an animation that never ends keeps
// the whole app producing frames, and because BackdropFilter cannot be cached,
// the app bar and nav blurs are then recomputed on every one of those frames.
// Measured, that cost a full CPU core continuously while the screen just sat
// there. A pulse on the transition says "this just went live" — which is the
// moment the information is worth anything — and then the screen goes quiet.
//
// This widget is display-only: it takes the same three values from the parent
// as before and never talks to the services itself. Expansion is local state.
// =============================================================================

class ConnectionStatusBar extends StatefulWidget {
  final bool wsConnected;
  final bool isEspApMode;
  final String? connectedSsid;

  const ConnectionStatusBar({
    super.key,
    required this.wsConnected,
    required this.isEspApMode,
    required this.connectedSsid,
  });

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _pulse;
  Timer? _pulseStop;

  /// How long the "just went live" pulse runs before the screen goes idle.
  static const Duration _pulseWindow = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(ConnectionStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wsConnected != oldWidget.wsConnected) _syncPulse();
  }

  /// The halo runs only while updates are actually live — a pulsing dot on a
  /// stale or offline state would be a lie — and only for [_pulseWindow], so
  /// the app can go idle afterwards. See the note at the top of this file for
  /// why a permanent animation is expensive here specifically.
  void _syncPulse() {
    _pulseStop?.cancel();

    if (!widget.wsConnected) {
      _pulse.stop();
      _pulse.value = 0;
      return;
    }

    _pulse.repeat();
    _pulseStop = Timer(_pulseWindow, () {
      if (!mounted) return;
      _pulse.stop();
      // Rewinding notifies the listeners, so the halo clears without a
      // setState of its own.
      _pulse.value = 0;
    });
  }

  @override
  void dispose() {
    _pulseStop?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ─────────────────────────────────────────────────────────────
    // Resolve tint, label, icon and the expanded explanation
    // ─────────────────────────────────────────────────────────────
    final Color tint;
    final String label;
    final IconData icon;
    final String detail;

    if (widget.wsConnected) {
      tint = GlassTokens.success;
      label = 'Live updates active';
      icon = Icons.wifi;
      detail = 'Connected to the Vortex cloud.';
    } else if (widget.isEspApMode) {
      tint = GlassTokens.primary;
      label = 'Direct mode — ${widget.connectedSsid ?? 'Valve WiFi'}';
      icon = Icons.settings_remote;
      detail = 'Talking straight to the valve over its own WiFi. Manual '
          'control works; schedule and sensor features need a cloud '
          'connection.';
    } else {
      tint = GlassTokens.warning;
      label = 'Offline — showing cached devices';
      icon = Icons.wifi_off;
      detail = 'No connection to the Vortex cloud. This is the device list '
          'saved on your phone — pull down to retry.';
    }

    final Color foreground = Color.lerp(tint, Colors.black, 0.35)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GlassSurface(
        tint: tint,
        tintStrength: 0.42,
        // 20 is exactly half the collapsed height, so this reads as a capsule
        // when closed and a rounded card when open — no radius animation, and
        // nothing snaps mid-expand.
        borderRadius: BorderRadius.circular(20),
        showShadow: false,
        onTap: () => setState(() => _expanded = !_expanded),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Summary row ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatusDot(tint: tint, icon: icon, pulse: _pulse),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: foreground.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),

              // ── Explanation, revealed on tap ──
              if (_expanded) ...[
                const SizedBox(height: 8),
                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.92),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// STATUS DOT
// -----------------------------------------------------------------------------
// The state icon, with a halo that expands and fades while [pulse] runs.
// Isolated behind a RepaintBoundary so the animation repaints ~20px, not the
// whole capsule and the list behind it.
// -----------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  final Color tint;
  final IconData icon;
  final Animation<double> pulse;

  const _StatusDot({
    required this.tint,
    required this.icon,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    final Color foreground = Color.lerp(tint, Colors.black, 0.35)!;

    return RepaintBoundary(
      child: SizedBox(
        width: 22,
        height: 22,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final double t = pulse.value;
                if (t == 0) return const SizedBox.shrink();
                return Container(
                  width: 14 + 8 * t,
                  height: 14 + 8 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint.withValues(alpha: 0.35 * (1 - t)),
                  ),
                );
              },
            ),
            Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.20),
              ),
              child: Icon(icon, color: foreground, size: 12),
            ),
          ],
        ),
      ),
    );
  }
}
