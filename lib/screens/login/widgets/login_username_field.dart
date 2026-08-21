import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// LOGIN USERNAME FIELD
// =============================================================================
// Text field for entering the username. Uses an external controller passed
// in from the parent screen so the parent can read the value on submit.
// =============================================================================

class LoginUsernameField extends StatelessWidget {
  final TextEditingController controller;

  const LoginUsernameField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: glassInputDecoration(
        labelText: 'Username',
        hintText: 'Enter your username',
        prefixIcon: const Icon(Icons.person_outline),
      ),
      textInputAction: TextInputAction.next,
    );
  }
}
