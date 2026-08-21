import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// LOGIN ICON
// =============================================================================
// Gradient disc at the top of the login card. Solid on purpose: it is the one
// opaque element in an otherwise translucent card, so the eye lands there
// first.
// =============================================================================

class LoginIcon extends StatelessWidget {
  const LoginIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: GlassTokens.accentGradient,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: GlassTokens.primary.withValues(alpha: 0.35),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Icon(
        Icons.person,
        size: 54,
        color: Colors.white,
      ),
    );
  }
}
