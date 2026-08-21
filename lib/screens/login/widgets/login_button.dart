import 'package:flutter/material.dart';

import '../../../widgets/glass/glass.dart';

// =============================================================================
// LOGIN BUTTON
// =============================================================================
// Full-width primary "Sign In" button. Shows a spinner when [isLoading] is
// true and is disabled while loading. The actual login work is handled by
// the parent through [onPressed].
// =============================================================================

class LoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const LoginButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      label: 'Sign In',
      icon: Icons.login_rounded,
      isLoading: isLoading,
      onPressed: isLoading ? null : onPressed,
    );
  }
}
