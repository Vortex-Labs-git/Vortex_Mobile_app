import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// GLASS BOTTOM NAV
// =============================================================================
// A floating navigation island: a rounded, translucent bar inset from the
// screen edges with content sliding underneath it. Pair it with
// `extendBody: true` on the Scaffold (GlassScaffold does this) — otherwise the
// Scaffold reserves opaque space below the body and the bar has nothing to
// float over.
//
// The selected tab is marked by a capsule that SLIDES between tabs rather than
// appearing in place, so a tab change reads as one continuous movement.
//
// This is one of the few places blur is kept (see the note in glass_surface):
// real content passes under it, so the frosting is visible and worth its cost.
//
// Screens whose content scrolls should add MediaQuery.paddingOf(context).bottom
// to their bottom padding — with extendBody that value already accounts for the
// island's full height plus its margins, so the last row clears the bar while
// the list still scrolls behind it.
// =============================================================================

class GlassNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  const GlassNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}

class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  /// Height of the island itself, excluding the margins around it.
  static const double barHeight = 64;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(barHeight / 2);
    // Clear the system navigation area completely. The app runs edge-to-edge,
    // so that area is ours to draw into — which means nothing stops this island
    // from landing on top of Android's 3-button bar unless the FULL inset is
    // reserved. A slightly airy gap under gesture navigation is the acceptable
    // side of that trade; overlapping the Back button is not.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottomInset),
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: GlassTokens.textPrimary.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: GlassTokens.blurStrong,
              sigmaY: GlassTokens.blurStrong,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.72),
                    Colors.white.withValues(alpha: 0.46),
                  ],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.75),
                  width: 1,
                ),
              ),
              child: Material(
                // Not inside the Scaffold body's Material, so the tab ripples
                // need one of their own.
                type: MaterialType.transparency,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double tabWidth =
                        constraints.maxWidth / items.length;
                    return Stack(
                      children: [
                        // Sliding selection capsule, behind the tabs.
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          left: tabWidth * currentIndex,
                          width: tabWidth,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              height: 46,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(23),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    GlassTokens.primaryBright
                                        .withValues(alpha: 0.20),
                                    GlassTokens.aqua.withValues(alpha: 0.16),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.70),
                                ),
                              ),
                            ),
                          ),
                        ),

                        Row(
                          children: [
                            for (int i = 0; i < items.length; i++)
                              Expanded(
                                child: _NavButton(
                                  item: items[i],
                                  selected: i == currentIndex,
                                  onTap: () => onTap(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// One tab. The capsule behind it is drawn by the parent (it slides), so this
// only animates the icon and label.
// -----------------------------------------------------------------------------

class _NavButton extends StatelessWidget {
  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      splashColor: GlassTokens.primary.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Selected icon lifts slightly and takes the brand color.
          AnimatedScale(
            scale: selected ? 1.12 : 1.0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 260),
              tween: ColorTween(
                end: selected ? GlassTokens.primary : GlassTokens.textMuted,
              ),
              builder: (context, color, _) => Icon(
                selected ? (item.activeIcon ?? item.icon) : item.icon,
                size: 22,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 260),
            style: TextStyle(
              fontSize: 11,
              color: selected ? GlassTokens.primary : GlassTokens.textMuted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}
