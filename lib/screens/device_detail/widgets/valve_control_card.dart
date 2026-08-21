import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

import '../../../widgets/glass/glass.dart';
import 'dart:math' as math;

// =============================================================================
// VALVE CONTROL CARD
// =============================================================================
// Manual-mode valve control. Has two sub-modes selected by [valveControlEnabled]:
//   ON  → State mode: Open / Close switch with confirmation tracking
//   OFF → Angle mode: 0–90° slider + dial visualization + Set Angle button
//
// All state lives in the parent screen. This widget just renders + raises
// callbacks for every user action.
// =============================================================================

class ValveControlCard extends StatelessWidget {
  // ── Mode toggle ──
  final bool valveControlEnabled; // true = state mode, false = angle mode
  final ValueChanged<bool> onValveControlEnabledChanged;

  // ── State mode ──
  final bool isOpen;
  final int actualPosition;
  final bool isUpdating;
  final ValueChanged<bool> onOpenCloseToggled; // true=open, false=close

  // ── Angle mode ──
  final double sliderAngle;
  final bool isAngleUpdating;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onSliderEditStart;
  final VoidCallback onSliderEditEnd;
  final ValueChanged<int> onSetAnglePressed;

  // ── Confirmation tracking (shared across both sub-modes) ──
  final bool waitingForConfirmation;
  final int? pendingTargetAngle;
  final int confirmationCountdown;

  const ValveControlCard({
    super.key,
    required this.valveControlEnabled,
    required this.onValveControlEnabledChanged,
    required this.isOpen,
    required this.actualPosition,
    required this.isUpdating,
    required this.onOpenCloseToggled,
    required this.sliderAngle,
    required this.isAngleUpdating,
    required this.onSliderChanged,
    required this.onSliderEditStart,
    required this.onSliderEditEnd,
    required this.onSetAnglePressed,
    required this.waitingForConfirmation,
    required this.pendingTargetAngle,
    required this.confirmationCountdown,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =========================================================
            // SECTION 1: HEADER + MODE TOGGLE
            // =========================================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Valve control',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Transform.scale(
                  scale: 1.2,
                  child: Switch(
                    value: valveControlEnabled,
                    // Disable mode switch while waiting for confirmation
                    onChanged: waitingForConfirmation
                        ? null
                        : onValveControlEnabledChanged,
                  ),
                ),
              ],
            ),

            // =========================================================
            // SECTION 2: MODE INDICATOR LABEL
            // =========================================================
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                valveControlEnabled
                    ? 'Mode: Open / Close'
                    : 'Mode: Angle control',
                style: TextStyle(
                  color: GlassTokens.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // =========================================================
            // SECTION 3: STATE MODE (toggle ON)
            // =========================================================
            if (valveControlEnabled) ...[
              // 3.1  Current state readout (what the device/DB reports)
              _buildCurrentStateRow(),

              const SizedBox(height: 12),

              // 3.2  Full-width action button — shows the OPPOSITE of
              //      the current state (open now → offers "Close Valve")
              _buildOpenCloseButton(),

              // const SizedBox(height: 12),

              // // 3.3  Actual position display
              // _buildActualPositionRow(),
            ],

            // =========================================================
            // SECTION 4: ANGLE MODE (toggle OFF)
            // =========================================================
            if (!valveControlEnabled) ...[
              const Text('By angle', style: TextStyle(color: GlassTokens.textMuted)),
              const SizedBox(height: 12),

              // 4.1  (waiting banner removed — the Set Angle button below
              //       already shows the countdown)

              // 4.2  Angle dial (ring + needle + center dot)
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: GlassTokens.primary.withValues(alpha: 0.16),
                            width: 8,
                          ),
                        ),
                      ),
                      // Needle (rotated by current slider angle)
                      Transform.rotate(
                        angle: (sliderAngle / 90) * (math.pi / 2),
                        child: Container(
                          width: 4,
                          height: 50,
                          decoration: BoxDecoration(
                            color: waitingForConfirmation
                                ? GlassTokens.primary
                                : GlassTokens.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Center dot
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: waitingForConfirmation
                              ? GlassTokens.primary
                              : GlassTokens.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 4.3  Big angle value text
              Center(
                child: Text(
                  '${sliderAngle.round()}°',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: waitingForConfirmation
                        ? GlassTokens.primary
                        : GlassTokens.primary,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 4.4  Slider 0° ─────●───── 90°
              Row(
                children: [
                  const Text(
                    '0°',
                    style: TextStyle(color: GlassTokens.textMuted, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: sliderAngle,
                      min: 0,
                      max: 90,
                      divisions: 90,
                      activeColor: waitingForConfirmation
                          ? GlassTokens.textMuted
                          : GlassTokens.primary,
                      inactiveColor: GlassTokens.primary.withValues(alpha: 0.18),
                      label: '${sliderAngle.round()}°',
                      onChanged: waitingForConfirmation ? null : onSliderChanged,
                      onChangeStart: waitingForConfirmation
                          ? null
                          : (_) => onSliderEditStart(),
                      onChangeEnd: waitingForConfirmation
                          ? null
                          : (_) => onSliderEditEnd(),
                    ),
                  ),
                  const Text(
                    '90°',
                    style: TextStyle(color: GlassTokens.textMuted, fontSize: 12),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // 4.5  "Set Angle" button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (isAngleUpdating || waitingForConfirmation)
                      ? null
                      : () => onSetAnglePressed(sliderAngle.round()),
                  icon: (isAngleUpdating || waitingForConfirmation)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    waitingForConfirmation
                        ? 'Waiting... ${confirmationCountdown}s'
                        : isAngleUpdating
                            ? 'Sending...'
                            : 'Set Angle to ${sliderAngle.round()}°',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTokens.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        GlassTokens.primary.withValues(alpha: 0.6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // // 4.6  Actual position display
              // _buildActualPositionRow(),
            ],
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: actual-position info row (used by both state and angle modes)
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildActualPositionRow() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Actual position',
            style: TextStyle(color: GlassTokens.textMuted, fontSize: 12),
          ),
          Text(
            '$actualPosition°',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: actualPosition >= 45 ? GlassTokens.success : GlassTokens.danger,
            ),
          ),
        ],
      ),
    );
  }


  // ───────────────────────────────────────────────────────────────────────
  // Helper: current-state readout ("By state" + Open/Closed pill)
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildCurrentStateRow() {
    final Color stateColor =
        isOpen ? GlassTokens.success : GlassTokens.danger;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('By state', style: TextStyle(color: GlassTokens.textMuted)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: stateColor.withValues(alpha: 0.40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stateColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isOpen ? 'Open' : 'Closed',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: stateColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: full-width open/close action button.
  // The label is always the ACTION, not the state:
  //   valve open   → "Close Valve" (red)
  //   valve closed → "Open Valve"  (green)
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildOpenCloseButton() {
    final bool busy = isUpdating || waitingForConfirmation;

    // Which action a press performs. While a command is in flight, `isOpen`
    // already reports the pending target, so we read the in-flight command
    // off pendingTargetAngle instead — that keeps the label/colour from
    // flipping mid-wait.
    final bool actionIsOpen =
        (waitingForConfirmation && pendingTargetAngle != null)
            ? pendingTargetAngle! >= 45
            : !isOpen;

    final Color actionColor = actionIsOpen
        ? const Color(0xFF2E7D32) // green – will open
        : const Color(0xFFC62828); // red   – will close

    final String label = waitingForConfirmation
        ? '${actionIsOpen ? "Opening" : "Closing"}... ${confirmationCountdown}s'
        : isUpdating
            ? 'Sending...'
            : actionIsOpen
                ? 'Open Valve'
                : 'Close Valve';

    return SizedBox(
      width: double.infinity, // edge to edge inside the card padding
      child: ElevatedButton.icon(
        onPressed: busy ? null : () => onOpenCloseToggled(!isOpen),
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                actionIsOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 20,
              ),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: actionColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: actionColor.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 1,
        ),
      ),
    );
  }
}