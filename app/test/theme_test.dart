import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/models.dart';
import 'package:sidekick/theme.dart';

void main() {
  test('a saved or admin theme name is read back, with a fallback for anything else', () {
    expect(ThemeChoice.parse('light'), ThemeChoice.light);
    expect(ThemeChoice.parse('system'), ThemeChoice.system);
    expect(ThemeChoice.parse('neon'), ThemeChoice.dark);
    expect(ThemeChoice.parse(null), ThemeChoice.dark);
    expect(ThemeChoice.parse(null, fallback: ThemeChoice.light), ThemeChoice.light);
  });

  test('system follows the phone or browser, the other choices do not', () {
    expect(brightnessOf(ThemeChoice.system, Brightness.light), Brightness.light);
    expect(brightnessOf(ThemeChoice.system, Brightness.dark), Brightness.dark);
    expect(brightnessOf(ThemeChoice.light, Brightness.dark), Brightness.light);
    expect(brightnessOf(ThemeChoice.dark, Brightness.light), Brightness.dark);
  });

  test('the colours in use follow the look, and both looks have a matching theme', () {
    C.use(Brightness.light);
    expect(C.paper, Palette.light.paper);
    expect(C.ink, Palette.light.ink);
    expect(buildTheme(Palette.light).brightness, Brightness.light);

    C.use(Brightness.dark);
    expect(C.paper, Palette.dark.paper);
    expect(C.ink, Palette.dark.ink);
    expect(buildTheme(Palette.dark).brightness, Brightness.dark);
  });
}
