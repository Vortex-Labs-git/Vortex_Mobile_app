import 'package:flutter/material.dart';

import '../../../utils/constants.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// MAIN APP BAR
// =============================================================================
// Top app bar shown across all 4 tabs: the app name, and a profile button that
// jumps to the User tab.
//
// The profile control is a GlassIconButton rather than a bare IconButton —
// on a translucent bar a plain icon reads as decoration, so it gets its own
// pane and a press-down scale to make it obviously tappable.
//
// Translucent: tab content scrolls underneath and blurs through it. That only
// works because MainScreen uses GlassScaffold (extendBodyBehindAppBar).
//
// Implements PreferredSizeWidget so it can be used in Scaffold.appBar.
// =============================================================================

class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onPersonPressed;

  const MainAppBar({super.key, required this.onPersonPressed});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return GlassAppBar(
      title: AppStrings.appName,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GlassIconButton(
            icon: Icons.person_outline,
            onPressed: onPersonPressed,
            tooltip: AppStrings.user,
          ),
        ),
      ],
    );
  }
}
