import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// LOGIN ERROR
// =============================================================================
// Red-tinted glass banner shown when login fails or input is invalid.
// Receives the error text from the parent screen.
// =============================================================================

class LoginError extends StatelessWidget {
  final String message;

  const LoginError({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
      tint: GlassTokens.danger,
      tintStrength: 0.20,
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: GlassTokens.danger,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Color.lerp(GlassTokens.danger, Colors.black, 0.30),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
