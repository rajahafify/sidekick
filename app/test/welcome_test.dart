import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/data/session.dart';
import 'package:sidekick/main.dart';
import 'package:sidekick/screens/welcome.dart';
import 'package:sidekick/theme.dart';

void main() {
  // The sign-in screen must fit without scrolling: the first slide's words and both buttons are
  // on screen, and nothing overflows (flutter_test fails the test on an overflow).
  for (final size in [const Size(360, 640), const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('sign-in fits ${size.width.toInt()}x${size.height.toInt()} without scrolling', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(SessionScope(
        session: Session(),
        child: MaterialApp(theme: buildTheme(Palette.dark), home: const WelcomeScreen()),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tester.getBottomLeft(find.text('Continue as guest')).dy, lessThanOrEqualTo(size.height));
      expect(tester.getBottomLeft(find.text('Continue with Google')).dy, lessThanOrEqualTo(size.height));
      expect(tester.getBottomLeft(find.text('Stay in the talk.')).dy, lessThanOrEqualTo(size.height));
      expect(find.byType(SingleChildScrollView), findsNothing);

      // Dispose the carousel and its timers before the test ends.
      await tester.pumpWidget(const SizedBox());
    });
  }
}
