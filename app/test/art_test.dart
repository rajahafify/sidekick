import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/theme.dart';
import 'package:sidekick/widgets/art.dart';
import 'package:sidekick/widgets/ui.dart';

import 'polish_test.dart' show contrast;

void main() {
  test('initials come from the first and last name', () {
    expect(initialsOf('Aisha Rahman'), 'AR');
    expect(initialsOf('  mei  '), 'M');
    expect(initialsOf('Ana Maria de Souza'), 'AS');
    expect(initialsOf(''), '?');
  });

  test('a poster keeps its colour, and light words read on every colour', () {
    expect(toneOf('u1'), toneOf('u1'));
    for (final seed in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']) {
      final (light, deep) = toneOf(seed);
      expect(contrast(Poster.ink, light), greaterThan(4.5));
      expect(contrast(Poster.muted, deep), greaterThan(7));
    }
  });

  testWidgets('a face with no photo shows initials on colour, at any size', (tester) async {
    for (final look in [Palette.light, Palette.dark]) {
      C.use(look.brightness);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(look),
        home: const Column(children: [
          Avatar(name: 'Aisha Rahman', size: 40),
          Avatar(name: 'Aisha Rahman', size: 104),
          SizedBox(width: 300, height: 380, child: PortraitPoster(name: 'Aisha Rahman', seed: 'u1')),
        ]),
      ));
      expect(find.text('A'), findsNWidgets(2));
      expect(find.text('AR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
