import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// GLASS THEME
// =============================================================================
// Design tokens + the global ThemeData behind the app's frosted-glass look.
//
// The visual language is: a soft indigo/violet/cyan gradient backdrop, and
// every surface on top of it is a translucent, blurred "pane" with a bright
// hairline edge and a low, wide shadow. Nothing is fully opaque, so the
// backdrop keeps showing through the whole UI.
//
// The widgets that actually draw the panes live in widgets/glass/. This file
// only holds the numbers and colors they share, so the whole look can be
// retuned from one place.
//
// NOTE ON ThemeData: only theme slots whose type has been stable across
// Flutter versions are set here (SnackBarThemeData, SwitchThemeData, ...).
// Surfaces that Flutter has been renaming (cards, dialogs, app bars, input
// decorations) are styled by the explicit glass widgets and by
// glassInputDecoration() below instead, so this file does not depend on which
// side of those migrations the local SDK sits on.
// =============================================================================

class GlassTokens {
  GlassTokens._();

  // ---------------------------------------------------------------------------
  // SECTION 1: BRAND + STATUS COLORS
  // ---------------------------------------------------------------------------
  // "Irrigation" palette: deep teal and aqua. The product moves water, so the
  // brand is water rather than the foliage green most agri apps reach for —
  // and that choice is functional, not just taste. Green means "online / valve
  // open" and red means "offline / closed" all through this app; a green brand
  // would put the brand and the status signal in the same hue and the status
  // would stop reading. Teal stays adjacent to green (still agricultural)
  // while leaving green and red to mean only one thing each.
  //
  // Every value below is checked for WCAG AA (4.5:1) against the pane it is
  // actually drawn on — see SECTION 3 for the text results. This app is used
  // outdoors, so contrast is a feature, not a formality.

  static const Color primary = Color(0xFF0F766E);        // 5.36:1 on pane
  static const Color primaryBright = Color(0xFF128B81);  // gradient start
  static const Color accent = Color(0xFF12808F);         // gradient end:
  //                          white label on it is 4.66:1, so buttons pass AA.

  /// Bright aqua for DECORATION ONLY — backdrop orbs, selection capsules.
  /// It is 2.83:1 on a pane, so never put text or a small icon in it.
  static const Color aqua = Color(0xFF1AA7B8);

  static const Color success = Color(0xFF2E7D32);        // 5.02:1
  static const Color warning = Color(0xFFB26A00);        // 4.15:1, headings
  static const Color danger = Color(0xFFC0303F);         // 5.50:1

  /// A fourth hue for categories that are neither brand nor a health state —
  /// currently sensor-driven mode, which sits alongside manual (brand teal)
  /// and schedule (warning amber) and needs to be told apart from both.
  /// Violet is the only family left that clashes with neither. 6.33:1.
  static const Color info = Color(0xFF5B4BC4);

  // ---------------------------------------------------------------------------
  // SECTION 2: BACKDROP
  // ---------------------------------------------------------------------------
  // The gradient the chrome blurs. Light enough that dark text stays readable
  // without restyling every Text widget.

  static const Color bgTop = Color(0xFFE6F4F3);
  static const Color bgMid = Color(0xFFEFF7F2);
  static const Color bgBottom = Color(0xFFDFF0F6);

  // ---------------------------------------------------------------------------
  // SECTION 3: TEXT
  // ---------------------------------------------------------------------------
  // Measured on the composited pane (#FBFDFC), not guessed. The old muted grey
  // came out at 2.94:1 — below AA and genuinely hard to read on a phone in
  // daylight — so all three steps were darkened until they passed.

  static const Color textPrimary = Color(0xFF0B2D2A);    // 14.45:1
  static const Color textSecondary = Color(0xFF34524E);  //  8.35:1
  static const Color textMuted = Color(0xFF4C6A66);      //  5.77:1

  // ---------------------------------------------------------------------------
  // SECTION 4: GEOMETRY + BLUR
  // ---------------------------------------------------------------------------

  static const double radiusLg = 24;
  static const double radiusMd = 18;
  static const double radiusSm = 12;

  /// Blur strength for panes sitting directly on the backdrop.
  static const double blur = 18;

  /// Lighter blur for small chips and pills, where a heavy blur reads as muddy.
  static const double blurSoft = 12;

  /// Heavier blur for chrome that must stay legible over scrolling content
  /// (app bars, bottom nav, dialogs).
  static const double blurStrong = 26;

  // ---------------------------------------------------------------------------
  // SECTION 5: SURFACE RECIPES
  // ---------------------------------------------------------------------------

  /// The two-stop sheen every pane is filled with. [tint] pulls the glass
  /// towards a status color (green for online, red for errors, ...).
  ///
  /// The default alphas are tuned for outdoor use: denser than a typical glass
  /// UI, because a pane that reads as elegant indoors turns into unreadable
  /// haze on a phone held in a field at midday. Contrast against the composited
  /// result is what the text colors in SECTION 3 were measured on.
  static LinearGradient paneGradient({
    Color? tint,
    double tintStrength = 0.35,
    double topAlpha = 0.74,
    double bottomAlpha = 0.54,
  }) {
    final Color base = tint == null
        ? Colors.white
        : Color.lerp(Colors.white, tint, tintStrength)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        base.withValues(alpha: topAlpha),
        base.withValues(alpha: bottomAlpha),
      ],
    );
  }

  /// The bright hairline that sells the "edge of a pane of glass" illusion.
  static Color paneBorder({Color? tint, double alpha = 0.70}) {
    if (tint == null) return Colors.white.withValues(alpha: alpha);
    return Color.lerp(tint, Colors.white, 0.45)!
        .withValues(alpha: (alpha + 0.05).clamp(0.0, 1.0));
  }

  /// Low, wide, slightly blue shadow — glass floats, it doesn't sit.
  static List<BoxShadow> paneShadow({
    double y = 10,
    double blurRadius = 24,
    double alpha = 0.10,
  }) {
    return [
      BoxShadow(
        color: textPrimary.withValues(alpha: alpha),
        blurRadius: blurRadius,
        offset: Offset(0, y),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // SYSTEM BARS
  // ---------------------------------------------------------------------------
  // The clock, battery and signal icons are drawn by the OS, not by us, and by
  // default their color follows the PHONE's theme — so on a light-themed phone
  // they come out white and vanish against this app's light glass bar.
  //
  // This app's chrome is light in every state, so the fix is to stop leaving it
  // to the OS and always ask for dark icons. Both platforms are covered:
  // statusBarIconBrightness is the Android knob, statusBarBrightness is the iOS
  // one (and iOS reads it as the brightness of the BACKGROUND, hence .light).
  //
  // The bars themselves are transparent so the gradient runs behind them.
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );

  /// Gradient used for solid accents (primary buttons, the FAB, avatars).
  /// Fill for solid accents (primary buttons, the FAB, avatars). Both stops are
  /// dark enough that white 16px labels clear AA — the brighter [aqua] is
  /// deliberately not used here for that reason.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBright, accent],
  );

  /// Same idea, tinted to an arbitrary color (status buttons, destructive
  /// actions). Produces a slightly lighter → slightly darker sweep.
  static LinearGradient tintedGradient(Color color) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(color, Colors.white, 0.22)!,
        Color.lerp(color, Colors.black, 0.10)!,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 6: GLOBAL THEME
  // ---------------------------------------------------------------------------

  static ThemeData themeData() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // GlassBackground paints the real gradient. This flat color is the
      // stand-in for screens not yet wrapped in one — transparent would render
      // as black.
      scaffoldBackgroundColor: bgMid,
    );

    return base.copyWith(
      dividerColor: primary.withValues(alpha: 0.14),

      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary.withValues(alpha: 0.92),
        contentTextStyle: const TextStyle(color: Colors.white),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return textMuted.withValues(alpha: 0.55);
          }
          return states.contains(WidgetState.selected) ? Colors.white : primary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.white.withValues(alpha: 0.35);
          }
          return states.contains(WidgetState.selected)
              ? primary
              : Colors.white.withValues(alpha: 0.55);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : primary.withValues(alpha: 0.45),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}

// =============================================================================
// GLASS INPUT DECORATION
// =============================================================================
// Shared InputDecoration for text fields sitting on glass. Applied per-field
// rather than through ThemeData.inputDecorationTheme — see the note at the top
// of this file.
// =============================================================================

InputDecoration glassInputDecoration({
  String? labelText,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.55),
    hintStyle: const TextStyle(color: GlassTokens.textMuted),
    labelStyle: const TextStyle(color: GlassTokens.textSecondary),
    prefixIconColor: GlassTokens.primary,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(Colors.white.withValues(alpha: 0.75)),
    enabledBorder: border(Colors.white.withValues(alpha: 0.75)),
    focusedBorder: border(GlassTokens.primary.withValues(alpha: 0.55), 1.6),
    errorBorder: border(GlassTokens.danger.withValues(alpha: 0.60)),
    focusedErrorBorder: border(GlassTokens.danger.withValues(alpha: 0.80), 1.6),
  );
}
