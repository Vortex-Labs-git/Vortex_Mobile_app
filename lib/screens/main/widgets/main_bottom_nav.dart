import 'package:flutter/material.dart';

import '../../../utils/constants.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// MAIN BOTTOM NAV
// =============================================================================
// Bottom navigation bar with 4 fixed tabs: Home / User / Manual / About.
// Receives the currently selected index and an onTap callback that the
// parent uses to update its own _currentIndex state.
//
// Translucent (GlassBottomNav): list content slides under it. The selected
// tab gets a tinted capsule behind its icon, which stays readable when the
// thing scrolling underneath is busy.
// =============================================================================

class MainBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassBottomNav(
      currentIndex: currentIndex,
      onTap: onTap,
      items: const [
        GlassNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: AppStrings.home,
        ),
        GlassNavItem(
          icon: Icons.person_outline,
          activeIcon: Icons.person_rounded,
          label: AppStrings.user,
        ),
        GlassNavItem(
          icon: Icons.menu_book_outlined,
          activeIcon: Icons.menu_book_rounded,
          label: 'Manual',
        ),
        GlassNavItem(
          icon: Icons.info_outline,
          activeIcon: Icons.info_rounded,
          label: AppStrings.about,
        ),
      ],
    );
  }
}
