import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';
import 'glass_surface.dart';

// =============================================================================
// GLASS DIALOG
// =============================================================================
// A dialog made of the same glass as the rest of the app, opened with a
// blurred barrier so the screen behind it visibly recedes.
//
// showGlassDialog() is used instead of showDialog() because the barrier blur
// has to animate with the dialog — showDialog only gives a flat scrim.
// The returned Future behaves like showDialog's: it completes with whatever
// value Navigator.pop() is given.
// =============================================================================

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: GlassTokens.textPrimary.withValues(alpha: 0.26),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      // Sigma must stay above zero, hence the small floor.
      final double sigma = 0.001 + 7 * curved.value;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

// -----------------------------------------------------------------------------
// THE PANEL
// -----------------------------------------------------------------------------

class GlassDialog extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget content;

  /// Buttons, laid out in a right-aligned row.
  final List<Widget> actions;

  /// Tints the header icon and title — red for destructive confirmations.
  final Color? tint;

  const GlassDialog({
    super.key,
    required this.title,
    this.icon,
    required this.content,
    this.actions = const [],
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = tint ?? GlassTokens.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassSurface(
            // Worth a blur: one at a time, and it sits over real screen
            // content rather than the plain gradient.
            enableBlur: true,
            blur: GlassTokens.blurStrong,
            // Denser than a card: dialog text must stay readable over whatever
            // happens to be behind it.
            opacity: 1.35,
            padding: const EdgeInsets.all(22),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──
                  Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(GlassTokens.radiusSm),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Icon(icon, color: accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: tint == null
                                ? GlassTokens.textPrimary
                                : Color.lerp(accent, Colors.black, 0.30),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ── Body ──
                  Flexible(child: SingleChildScrollView(child: content)),

                  // ── Actions ──
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (int i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          actions[i],
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
