import 'package:flutter/material.dart';

/// App-level appearance preferences (stored in SharedPreferences).
///
/// The theme setting is separate from [ServerSettings]: it only changes
/// how this phone's UI looks, while the server settings change what the
/// local Web UI / API serve.
enum AppThemeMode {
  system,
  dark,
  light;

  /// Chinese label shown in the settings UI.
  String get label {
    switch (this) {
      case AppThemeMode.system:
        return '跟隨系統';
      case AppThemeMode.dark:
        return '深色';
      case AppThemeMode.light:
        return '淺色';
    }
  }

  ThemeMode get themeMode {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.light:
        return ThemeMode.light;
    }
  }

  /// Storage value written to SharedPreferences (`app_theme_mode`).
  String get storageValue => name;

  /// Parses a stored value; unknown or missing values fall back to dark,
  /// which is the look the app had before this setting existed.
  static AppThemeMode fromStorage(String? value) {
    switch (value) {
      case 'system':
        return AppThemeMode.system;
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.dark;
    }
  }
}
