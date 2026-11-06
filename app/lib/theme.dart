import 'package:flutter/material.dart';

/// Same palette as the web app: warm off-white ink on near-black, with a gold accent.
class C {
  static const paper = Color(0xFF0B0B0D);
  static const surface = Color(0xFF141416);
  static const soft = Color(0xFF1C1C1F);
  static const line = Color(0xFF2A2A2E);
  static const ink = Color(0xFFF3EFE6);
  static const onInk = Color(0xFF0B0B0D);
  static const muted = Color(0xFF9B978E);
  static const go = Color(0xFFD8BC86);
  static const goSoft = Color(0xFF1F1B14);
  static const danger = Color(0xFFF0A5A0);
}

const display = 'InstrumentSerif';

TextStyle displayStyle(double size, {Color color = C.ink, FontStyle? style}) =>
    TextStyle(fontFamily: display, fontSize: size, height: 1.0, color: color, fontStyle: style, letterSpacing: -0.5);

const eyebrow = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: C.go);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: C.paper,
    onSurface: C.ink,
    primary: C.go,
    onPrimary: C.onInk,
    secondary: C.go,
    error: C.danger,
    outline: C.line,
    surfaceContainerHighest: C.soft,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Inter', brightness: Brightness.dark);
  final radius = BorderRadius.circular(16);
  return base.copyWith(
    scaffoldBackgroundColor: C.paper,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink).copyWith(
          bodyLarge: const TextStyle(fontSize: 17, height: 1.4, color: C.ink),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.4, color: C.ink),
          bodySmall: const TextStyle(fontSize: 13, height: 1.35, color: C.muted),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: C.ink,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600, color: C.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.ink,
        foregroundColor: C.onInk,
        disabledBackgroundColor: C.soft,
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink,
        side: const BorderSide(color: C.line),
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.go, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      hintStyle: const TextStyle(color: C.muted),
      labelStyle: const TextStyle(color: C.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: C.go)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: C.surface,
      selectedColor: C.goSoft,
      side: const BorderSide(color: C.line),
      labelStyle: const TextStyle(fontSize: 14, color: C.ink),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: C.goSoft,
      surfaceTintColor: Colors.transparent,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.go : C.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: s.contains(WidgetState.selected) ? C.ink : C.muted)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.soft,
      contentTextStyle: TextStyle(color: C.ink, fontSize: 15),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: C.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.surface, surfaceTintColor: Colors.transparent),
    dialogTheme: const DialogThemeData(backgroundColor: C.surface, surfaceTintColor: Colors.transparent),
  );
}
