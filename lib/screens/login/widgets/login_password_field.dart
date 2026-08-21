import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// LOGIN PASSWORD FIELD
// =============================================================================
// Obscured text field for entering the password. Includes a visibility-toggle
// suffix icon. The obscure state is owned by this widget itself, but the
// controller and submit callback come from the parent.
// =============================================================================

class LoginPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const LoginPasswordField({
    super.key,
    required this.controller,
    required this.onSubmitted,
  });

  @override
  State<LoginPasswordField> createState() => _LoginPasswordFieldState();
}

class _LoginPasswordFieldState extends State<LoginPasswordField> {
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscurePassword,
      decoration: glassInputDecoration(
        labelText: 'Password',
        hintText: 'Enter your password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
            color: GlassTokens.textMuted,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => widget.onSubmitted(),
    );
  }
}
