import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
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
    required this.shadow,
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

  /// The soft shadow under raised things (the tab bar, the deck). Barely there on black.
  final Color shadow;

  static const dark = Palette(
    brightness: Brightness.dark,
    paper: Color(0xFF000000),
    surface: Color(0xFF101010),
    soft: Color(0xFF1B1B1B),
    line: Color(0xFF262626),
    ink: Color(0xFFFFFFFF),
    onInk: Color(0xFF000000),
    muted: Color(0xFF9A9A9A),
    go: Color(0xFFFF5A36),
    goSoft: Color(0xFF26110B),
    danger: Color(0xFFFF8A80),
    shadow: Color(0x00000000),
  );

  static const light = Palette(
    brightness: Brightness.light,
    paper: Color(0xFFFFFFFF),
    surface: Color(0xFFF6F5F2),
    soft: Color(0xFFECEAE6),
    line: Color(0xFFE4E2DD),
    ink: Color(0xFF0A0A0A),
    onInk: Color(0xFFFFFFFF),
    muted: Color(0xFF6B6863),
    // Signal for text, deep enough to pass 4.5:1 on white. Fills use [signal] itself.
    go: Color(0xFFCF3A1A),
    goSoft: Color(0xFFFCEBE5),
    danger: Color(0xFFB3261E),
    shadow: Color(0x1F000000),
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
  static Color get shadow => _p.shadow;
}

/// Signal, the one accent, as a fill: the Connect button, the live dot, an unread dot. The same in
/// both looks, and its label is always black (white on Signal is too faint to read).
const signal = Color(0xFFFF5A36);
const onSignal = Color(0xFF0A0A0A);

/// A poster is a person's or event's picture card: always a dark picture with white words on it,
/// in both looks, the way a photo is.
class Poster {
  static const bg = Color(0xFF0B0B0B);
  static const ink = Color(0xFFFFFFFF);
  static const muted = Color(0xFFBDBDBD);
  /// A dark pane over the picture, for a chip, a note or a round button that must stay readable.
  static const glass = Color(0xA6101010);
  static const edge = Color(0x33FFFFFF);
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

/// Letterspaced caps in Signal, for the sidekick's own voice and the moments that matter.
TextStyle get eyebrow => TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: C.go);

/// The same caps in grey, for ordinary labels.
TextStyle get caps => TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: C.muted);

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
    // Screens slide in from the side and can be swiped back, on every platform.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {for (final t in TargetPlatform.values) t: const CupertinoPageTransitionsBuilder()},
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.ink),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.ink : p.soft),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onInk : p.muted),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.ink, textColor: p.ink),
    iconTheme: IconThemeData(color: p.ink),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.ink,
      selectionColor: p.go.withValues(alpha: 0.25),
      selectionHandleColor: p.go,
    ),
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
        disabledForegroundColor: p.muted,
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w500),
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
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.ink, width: 1.4)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.danger, width: 1.4)),
      floatingLabelStyle: TextStyle(color: p.muted),
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
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: p.onInk, fontSize: 15, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
