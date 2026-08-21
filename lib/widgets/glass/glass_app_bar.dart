import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// GLASS APP BAR
// =============================================================================
// Translucent app bar: content scrolls *under* it and shows through, blurred.
//
// This only works when the Scaffold sets `extendBodyBehindAppBar: true` —
// GlassScaffold does that for you. Without it the Scaffold reserves opaque
// space above the body and there is nothing behind the bar to blur.
//
// The blur covers the status bar too: Scaffold sizes the app bar to
// preferredSize + the top inset, and the AppBar inside applies that inset
// itself, so the BackdropFilter wrapper spans the full height.
// =============================================================================

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  /// Tints the bar (and the title) — used to mark direct-to-device mode.
  final Color? tint;

  /// Small line under the title, for context that changes (a device name, a
  /// mode). Raises the bar's height when present.
  final String? subtitle;

  /// Mark shown immediately before the title — the brand dot on the main shell.
  final Widget? titleMark;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
    this.tint,
    this.subtitle,
    this.titleMark,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(subtitle == null ? kToolbarHeight : kToolbarHeight + 12);

  @override
  Widget build(BuildContext context) {
    final Color titleColor = tint == null
        ? GlassTokens.textPrimary
        : Color.lerp(tint, Colors.black, 0.35)!;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassTokens.blurStrong,
          sigmaY: GlassTokens.blurStrong,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: GlassTokens.paneGradient(
              tint: tint,
              tintStrength: 0.30,
              topAlpha: 0.55,
              bottomAlpha: 0.30,
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1,
              ),
            ),
          ),
          child: AppBar(
            // Set explicitly: AppBar otherwise infers icon brightness from its
            // own background, and ours is transparent, so it guesses wrong and
            // the clock/battery icons disappear into the light bar.
            systemOverlayStyle: GlassTokens.systemOverlay,
            toolbarHeight: preferredSize.height,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (titleMark != null) ...[
                  titleMark!,
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: centerTitle
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: titleColor.withValues(alpha: 0.62),
                            fontWeight: FontWeight.w500,
                            fontSize: 11.5,
                            letterSpacing: 0.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            centerTitle: centerTitle,
            leading: leading,
            actions: actions,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: titleColor,
            iconTheme: IconThemeData(color: titleColor),
          ),
        ),
      ),
    );
  }
}
