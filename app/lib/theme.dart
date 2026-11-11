import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'models.dart';

/// The colours of one look. Three colours do the work:
///
/// * Pine, the main colour: the page ink, the main buttons, the picture cards.
/// * Oat, the secondary: a warm neutral that sits beside Pine, for tinted cards, tiles and chips.
/// * Signal, the accent: kept for the moments that matter (Connect, live, unread, a match).
///
/// Light is Pine on warm paper with Oat tints. Dark swaps them: Oat on deep Pine.
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
    required this.brand,
    required this.onBrand,
    required this.second,
    required this.onSecond,
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

  /// The main colour as a fill (the main button, a picked choice), and what is written on it.
  final Color brand;
  final Color onBrand;

  /// The secondary colour as a fill (a tinted card, a date tile, a face with no photo).
  final Color second;
  final Color onSecond;
  final Color go;
  final Color goSoft;
  final Color danger;

  /// The soft shadow under raised things (the tab bar, the deck). Barely there on dark.
  final Color shadow;

  static const dark = Palette(
    brightness: Brightness.dark,
    paper: Color(0xFF08130E),
    surface: Color(0xFF101E17),
    soft: Color(0xFF192B21),
    line: Color(0xFF24382C),
    ink: Color(0xFFF6F2EA),
    onInk: Color(0xFF08130E),
    muted: Color(0xFF93A69B),
    brand: oat,
    onBrand: Color(0xFF0E2E21),
    second: Color(0xFF14382A),
    onSecond: Color(0xFFF6F2EA),
    go: Color(0xFFFF6B49),
    goSoft: Color(0xFF2C160E),
    danger: Color(0xFFFF8A80),
    shadow: Color(0x00000000),
  );

  static const light = Palette(
    brightness: Brightness.light,
    paper: Color(0xFFFBF9F4),
    surface: Color(0xFFF4EFE5),
    soft: Color(0xFFEAE4D6),
    line: Color(0xFFDFD8C8),
    ink: Color(0xFF10261C),
    onInk: Color(0xFFFBF9F4),
    muted: Color(0xFF5C6A61),
    brand: pine,
    onBrand: Color(0xFFFBF9F4),
    second: oat,
    onSecond: pine,
    // Signal for text, deep enough to pass 4.5:1 on paper. Fills use [signal] itself.
    go: Color(0xFFB8300C),
    goSoft: Color(0xFFFBE7DF),
    danger: Color(0xFFB3261E),
    shadow: Color(0x24102A1E),
  );
}

/// The three named colours.
const pine = Color(0xFF12402E);
const oat = Color(0xFFEDE4D3);

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
  static Color get brand => _p.brand;
  static Color get onBrand => _p.onBrand;
  static Color get second => _p.second;
  static Color get onSecond => _p.onSecond;
  static Color get go => _p.go;
  static Color get goSoft => _p.goSoft;
  static Color get danger => _p.danger;
  static Color get shadow => _p.shadow;
}

/// Signal, the accent, as a fill: the Connect button, the live dot, an unread dot. The same in
/// both looks, and its label is always dark (white on Signal is too faint to read).
const signal = Color(0xFFFF5A36);
const onSignal = Color(0xFF0B1A13);

/// A poster is a person's or event's picture card: always deep Pine with Oat words on it, in both
/// looks, the way a photo is.
class Poster {
  static const bg = Color(0xFF0E2E21);
  static const ink = Color(0xFFFBF9F4);
  static const muted = Color(0xFFC6D2C9);
  /// A dark pane over the picture, for a chip, a note or a round button that must stay readable.
  static const glass = Color(0xA608130E);
  static const edge = Color(0x33FBF9F4);
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
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.brand),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.brand : p.soft),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onBrand : p.muted),
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
        backgroundColor: p.brand,
        foregroundColor: p.onBrand,
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
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.brand : p.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onBrand : p.ink),
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
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.brand, width: 1.4)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.danger, width: 1.4)),
      floatingLabelStyle: TextStyle(color: p.muted),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      selectedColor: p.second,
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
      backgroundColor: p.brightness == Brightness.light ? pine : p.soft,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: Poster.ink, fontSize: 15, fontWeight: FontWeight.w500),
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
