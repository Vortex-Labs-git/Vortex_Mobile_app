import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// EMPTY VIEW
// =============================================================================
// Shown when device loading is complete but the user has no devices assigned.
// Static, no callbacks needed — just a hint to contact Vortex Labs.
// =============================================================================

class EmptyView extends StatelessWidget {
  const EmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Devices icon in a soft glass disc
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlassTokens.primary.withValues(alpha: 0.10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.devices_other,
                  size: 42,
                  color: GlassTokens.primary,
                ),
              ),

              const SizedBox(height: 20),

              // Title
              const Text(
                "No devices found",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textPrimary,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              const Text(
                "Please contact Vortex Labs to get devices assigned to your account.",
                style: TextStyle(color: GlassTokens.textSecondary, height: 1.45),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
