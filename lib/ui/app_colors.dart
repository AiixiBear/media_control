import 'package:flutter/material.dart';

/// Resolves the app's dark-first palette for the current brightness.
///
/// The UI was designed dark, so every card uses these helpers instead of
/// hard-coded white text: in light mode the same cards render with dark
/// text on light panels and stay readable.
class AppColors {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Primary text.
  static Color text(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF0F172A);

  /// Secondary / muted text.
  static Color muted(BuildContext context) =>
      isDark(context) ? Colors.white70 : const Color(0xFF475569);

  /// Faint text (package names, hints).
  static Color faint(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.56)
      : const Color(0xFF64748B);

  /// Card / panel background.
  static Color panel(BuildContext context) =>
      isDark(context) ? Colors.white.withValues(alpha: 0.05) : Colors.white;

  /// Card / panel border.
  static Color panelBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFE2E8F0);

  /// Inner session-row background.
  static Color rowBackground(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.04)
      : const Color(0xFFF1F5F9);

  /// Inner session-row border.
  static Color rowBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.06)
      : const Color(0xFFE2E8F0);

  /// Hero gradient (top-left to bottom-right).
  static List<Color> heroGradient(BuildContext context) => isDark(context)
      ? const <Color>[Color(0xFF143149), Color(0xFF10253B), Color(0xFF0A1424)]
      : const <Color>[Color(0xFFD6F3F5), Color(0xFFC2E8F5), Color(0xFFE0F2FE)];

  /// Page background gradient.
  static List<Color> pageGradient(BuildContext context) => isDark(context)
      ? const <Color>[Color(0xFF08111F), Color(0xFF0B1729), Color(0xFF050B14)]
      : const <Color>[Color(0xFFF4F7FA), Color(0xFFE8F1F8), Color(0xFFDCE8F2)];

  /// App bar background.
  static Color appBar(BuildContext context) =>
      isDark(context) ? const Color(0xFF07111D) : const Color(0xFFE8F1F8);
}
