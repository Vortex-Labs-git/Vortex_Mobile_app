import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// Superseded by [GlassTokens] (theme/glass_theme.dart), which is the source
/// of truth for the frosted-glass look. These aliases stay so older code keeps
/// compiling and keeps matching the new palette — prefer GlassTokens in new
/// code, and note that surfaces are now translucent panes (see
/// widgets/glass/), not the flat [background] / [cardBackground] fills below.
class AppColors {
  static const Color primary = GlassTokens.primary;
  static const Color primaryDark = Color(0xFF0B5A54);
  static const Color primaryLight = Color(0xFFBFE0DC);
  static const Color accent = GlassTokens.primaryBright;
  static const Color success = GlassTokens.success;
  static const Color warning = GlassTokens.warning;
  static const Color error = GlassTokens.danger;
  static const Color offline = GlassTokens.textMuted;
  static const Color background = GlassTokens.bgMid;
  static const Color cardBackground = Colors.white;
}

class AppStrings {
  static const String appName = 'Vortex Labs';
  static const String version = '1.0.0';
  static const String home = 'Home';
  static const String user = 'User';
  static const String about = 'About';
  static const String statusOpen = 'Open';
  static const String statusClosed = 'Closed';
  static const String statusPartial = 'Partial';
  static const String statusOffline = 'Offline';
  static const String noDevices = 'No devices added yet';
  static const String tapToAdd = 'Tap + to add a motorized valve';
  static const String addDevice = 'Add New Device';
}

class AppDimensions {
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double iconSmall = 24.0;
  static const double iconMedium = 48.0;
  static const double iconLarge = 64.0;
  static const double borderRadius = 12.0;
}
