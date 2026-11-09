import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:media_control/main.dart';

void main() {
  group('AppThemeMode', () {
    test('labels are Traditional Chinese', () {
      expect(AppThemeMode.system.label, '跟隨系統');
      expect(AppThemeMode.dark.label, '深色');
      expect(AppThemeMode.light.label, '淺色');
    });

    test('maps to the matching Flutter ThemeMode', () {
      expect(AppThemeMode.system.themeMode, ThemeMode.system);
      expect(AppThemeMode.dark.themeMode, ThemeMode.dark);
      expect(AppThemeMode.light.themeMode, ThemeMode.light);
    });

    test('round-trips through storage values', () {
      for (final mode in AppThemeMode.values) {
        expect(AppThemeMode.fromStorage(mode.storageValue), mode);
      }
    });

    test('unknown or missing values fall back to dark', () {
      expect(AppThemeMode.fromStorage(null), AppThemeMode.dark);
      expect(AppThemeMode.fromStorage(''), AppThemeMode.dark);
      expect(AppThemeMode.fromStorage('neon'), AppThemeMode.dark);
    });
  });
}
