import 'package:flutter/material.dart';

import 'models.dart';

/// The colours of one look. Dark is white on pure black, light is black on white. Both share one
/// accent (Signal), kept for the moments that matter: Connect, the sidekick's pick, live events and
/// matches. Images are halftone dots (widgets/dots.dart), so they follow the ink colour.
class Palette {
  const Palette({
    required this.brightness,
    required this.paper,
    required this.surface,
    required this.soft,
    required this.line,
    required this.ink,
    required this.onInk,
    required this.muted,
    required this.go,
    required this.goSoft,
    required this.danger,
  });

  final Brightness brightness;
  final Color paper;
  final Color surface;
  final Color soft;
  final Color line;
  final Color ink;
  final Color onInk;
  final Color muted;
  final Color go;
  final Color goSoft;
  final Color danger;

  static const dark = Palette(
    brightness: Brightness.dark,
    paper: Color(0xFF000000),
    surface: Color(0xFF111111),
    soft: Color(0xFF1C1C1C),
    line: Color(0xFF2A2A2A),
    ink: Color(0xFFFFFFFF),
    onInk: Color(0xFF000000),
    muted: Color(0xFF8E8E8E),
    go: Color(0xFFFF5A36),
    goSoft: Color(0xFF2A100A),
    danger: Color(0xFFFF8A80),
  );

  static const light = Palette(
    brightness: Brightness.light,
    paper: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F4F4),
    soft: Color(0xFFEBEBEB),
    line: Color(0xFFDCDCDC),
    ink: Color(0xFF0B0B0B),
    onInk: Color(0xFFFFFFFF),
    muted: Color(0xFF6B6B6B),
    // Signal, a touch deeper than on black so the orange text still reads on white.
    go: Color(0xFFE2472A),
    goSoft: Color(0xFFFDE9E3),
    danger: Color(0xFFC62828),
  );
}

/// The colours in use right now. Screens read them as they build. [C.use] switches the whole app;
/// main.dart rebuilds the app when that happens.
class C {
  static Palette _p = Palette.dark;

  static void use(Brightness b) => _p = b == Brightness.light ? Palette.light : Palette.dark;

  static Brightness get brightness => _p.brightness;
  static Color get paper => _p.paper;
  static Color get surface => _p.surface;
  static Color get soft => _p.soft;
  static Color get line => _p.line;
  static Color get ink => _p.ink;
  static Color get onInk => _p.onInk;
  static Color get muted => _p.muted;
  static Color get go => _p.go;
  static Color get goSoft => _p.goSoft;
  static Color get danger => _p.danger;
}

/// Light or dark for a choice, once "system" is resolved against the phone or browser.
Brightness brightnessOf(ThemeChoice c, Brightness platform) => switch (c) {
      ThemeChoice.system => platform,
      ThemeChoice.light => Brightness.light,
      ThemeChoice.dark => Brightness.dark,
    };

ThemeMode themeModeOf(ThemeChoice c) => switch (c) {
      ThemeChoice.system => ThemeMode.system,
      ThemeChoice.light => ThemeMode.light,
      ThemeChoice.dark => ThemeMode.dark,
    };

const display = 'InstrumentSerif';

TextStyle displayStyle(double size, {Color? color, FontStyle? style}) => TextStyle(
      fontFamily: display,
      fontSize: size,
      height: 1.0,
      color: color ?? C.ink,
      fontStyle: style,
      letterSpacing: -0.5,
    );

TextStyle get eyebrow => TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: C.go);

ThemeData buildTheme(Palette p) {
  final light = p.brightness == Brightness.light;
  final scheme = light
      ? ColorScheme.light(
          surface: p.paper,
          onSurface: p.ink,
          primary: p.go,
          onPrimary: p.onInk,
          secondary: p.go,
          error: p.danger,
          outline: p.line,
          surfaceContainerHighest: p.soft,
        )
      : ColorScheme.dark(
          surface: p.paper,
          onSurface: p.ink,
          primary: p.go,
          onPrimary: p.onInk,
          secondary: p.go,
          error: p.danger,
          outline: p.line,
          surfaceContainerHighest: p.soft,
        );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Inter', brightness: p.brightness);
  final radius = BorderRadius.circular(16);
  return base.copyWith(
    scaffoldBackgroundColor: p.paper,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme
        .apply(bodyColor: p.ink, displayColor: p.ink)
        .copyWith(
          bodyLarge: TextStyle(fontSize: 17, height: 1.4, color: p.ink),
          bodyMedium: TextStyle(fontSize: 15, height: 1.4, color: p.ink),
          bodySmall: TextStyle(fontSize: 13, height: 1.35, color: p.muted),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: p.ink,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600, color: p.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.onInk,
        disabledBackgroundColor: p.soft,
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : p.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onInk : p.ink),
        side: WidgetStateProperty.all(BorderSide(color: p.line)),
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: TextStyle(color: p.muted),
      labelStyle: TextStyle(color: p.muted),
      helperStyle: TextStyle(color: p.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.go)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      selectedColor: p.goSoft,
      side: BorderSide(color: p.line),
      labelStyle: TextStyle(fontSize: 14, color: p.ink),
      shape: const StadiumBorder(),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.paper,
      indicatorColor: p.go,
      surfaceTintColor: Colors.transparent,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.onInk : p.muted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: s.contains(WidgetState.selected) ? p.ink : p.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.soft,
      contentTextStyle: TextStyle(color: p.ink, fontSize: 15),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
  );
}
