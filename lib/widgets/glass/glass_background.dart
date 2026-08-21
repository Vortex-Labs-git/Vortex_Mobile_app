import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// GLASS BACKGROUND
// =============================================================================
// The backdrop the glass panes sit on. Without it they have nothing to show
// through and the whole look collapses into flat grey boxes — so any screen
// using glass widgets should sit inside one of these.
//
// It paints:
//   1. a diagonal teal → mint → aqua gradient
//   2. three large, soft "orbs" (radial gradients fading to transparent),
//      which keep the backdrop from reading as a flat wash
//
// The orbs are radial gradients rather than blurred shapes on purpose: one
// gradient fill each, no image filter. The whole backdrop is a single cached
// layer, so scrolling content on top of it never forces it to repaint.
//
// [animated] drifts the orbs on a slow 24s loop. It is off everywhere by
// default, and turning it on is more expensive than it looks: any animation
// that never ends keeps the app producing frames forever, and BackdropFilter
// cannot be cached, so the app bar and nav blurs get recomputed on every one
// of those frames. Measured on this app, an endless animation cost a full CPU
// core while the screen sat idle. Only enable this on a screen that is briefly
// on display, and never on one the user leaves open.
// =============================================================================

class GlassBackground extends StatefulWidget {
  final Widget child;

  /// Draw the soft color orbs. Off gives a plain gradient.
  final bool showOrbs;

  /// Slowly drift the orbs. See the note above before turning this on.
  final bool animated;

  const GlassBackground({
    super.key,
    required this.child,
    this.showOrbs = true,
    this.animated = false,
  });

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animated) _startAnimation();
  }

  @override
  void didUpdateWidget(GlassBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && _controller == null) {
      _startAnimation();
    } else if (!widget.animated && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void _startAnimation() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The gradient and orbs never change while a screen is idle or scrolling,
    // so keep them in their own layer instead of repainting them under every
    // frame of scrolling content.
    final Widget backdrop = RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              GlassTokens.bgTop,
              GlassTokens.bgMid,
              GlassTokens.bgBottom,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: widget.showOrbs ? _buildOrbs() : const SizedBox.expand(),
      ),
    );

    return Stack(fit: StackFit.expand, children: [backdrop, widget.child]);
  }

  // ---------------------------------------------------------------------------
  // ORBS
  // ---------------------------------------------------------------------------

  Widget _buildOrbs() {
    // Each orb animates itself (see _orb), so nothing needs to rebuild here.
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -90,
            left: -70,
            child: _orb(
              size: 300,
              color: GlassTokens.primaryBright,
              alpha: 0.38,
              phase: 0,
            ),
          ),
          Positioned(
            top: 140,
            right: -110,
            child: _orb(
              size: 320,
              color: GlassTokens.aqua,
              alpha: 0.30,
              phase: 2.1,
            ),
          ),
          Positioned(
            bottom: -100,
            left: -50,
            child: _orb(
              size: 300,
              color: GlassTokens.success,
              alpha: 0.30,
              phase: 4.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orb({
    required double size,
    required Color color,
    required double alpha,
    required double phase,
  }) {
    final Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.45),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );

    final AnimationController? controller = _controller;
    if (controller == null) return circle;

    // Each orb traces a small ellipse, offset in phase from its siblings, so
    // the backdrop never repeats an exact frame.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final double t = controller.value * 2 * math.pi + phase;
        return Transform.translate(
          offset: Offset(math.cos(t) * 22, math.sin(t) * 30),
          child: child,
        );
      },
      child: circle,
    );
  }
}
