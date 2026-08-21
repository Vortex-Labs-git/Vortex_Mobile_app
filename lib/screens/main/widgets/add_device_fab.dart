import 'package:flutter/material.dart';

import '../../../utils/constants.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// ADD DEVICE FAB
// =============================================================================
// Floating action button shown only on the Home tab. The actual dialog logic
// (TextField for name, snackbar confirmation) lives in the parent screen and
// is invoked through [onPressed].
//
// Uses GlassFab — a gradient disc rather than a Material FAB, so it reads as
// the one solid element floating above the glass.
// =============================================================================

class AddDeviceFab extends StatelessWidget {
  final VoidCallback onPressed;

  const AddDeviceFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GlassFab(
      icon: Icons.add_rounded,
      onPressed: onPressed,
      tooltip: AppStrings.addDevice,
    );
  }
}
