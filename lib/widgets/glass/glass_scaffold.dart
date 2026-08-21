import 'package:flutter/material.dart';

import 'glass_background.dart';

// =============================================================================
// GLASS SCAFFOLD
// =============================================================================
// Scaffold + gradient backdrop, wired so the glass chrome actually works:
//
//   - the backdrop sits OUTSIDE the Scaffold, and the Scaffold is transparent,
//     so app bar and bottom nav blur the gradient rather than a grey void
//   - extendBodyBehindAppBar / extendBody let content scroll under both
//   - the body is wrapped in SafeArea(top) so it starts below the app bar
//     (with extendBodyBehindAppBar the Scaffold folds the bar's height into
//     the body's MediaQuery padding, so SafeArea handles it)
//
// Bottom inset is deliberately NOT consumed: scrolling screens should add
// MediaQuery.paddingOf(context).bottom to their own bottom padding so content
// passes under the translucent nav bar instead of stopping short of it.
// =============================================================================

class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  /// Drift the backdrop orbs. Off by default — see GlassBackground.
  final bool animatedBackground;

  final bool showOrbs;

  /// Set false if the body handles its own top inset.
  final bool useSafeArea;

  final bool resizeToAvoidBottomInset;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.floatingActionButtonLocation,
    this.animatedBackground = false,
    this.showOrbs = true,
    this.useSafeArea = true,
    this.resizeToAvoidBottomInset = true,
  });

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      animated: animatedBackground,
      showOrbs: showOrbs,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: appBar,
        body: useSafeArea
            ? SafeArea(top: true, bottom: false, child: body)
            : body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}
