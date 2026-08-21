import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// ERROR VIEW
// =============================================================================
// Shown when there's an error message AND no cached devices to display.
// Shows the error icon, message, and a Retry button that re-runs initialization.
//
// The pane is tinted red so the failure reads before the text does.
// =============================================================================

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          tint: GlassTokens.danger,
          tintStrength: 0.16,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error icon
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlassTokens.danger.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.wifi_off,
                  size: 38,
                  color: GlassTokens.danger,
                ),
              ),

              const SizedBox(height: 18),

              // Error message text
              Text(
                message,
                style: TextStyle(
                  color: Color.lerp(GlassTokens.danger, Colors.black, 0.30),
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 22),

              // Retry button
              GlassButton(
                label: 'Retry',
                icon: Icons.refresh,
                fullWidth: false,
                height: 46,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
