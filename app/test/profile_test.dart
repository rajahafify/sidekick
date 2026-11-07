import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/data/session.dart';
import 'package:sidekick/main.dart';
import 'package:sidekick/screens/profile.dart';
import 'package:sidekick/theme.dart';

/// A session that signed in with Google as fify, without the network or the identity pool.
class GoogleSession extends Session {
  @override
  String get googleName => 'Fify R';

  @override
  String get googleEmail => 'fify@gmail.com';

  @override
  String get googlePhoto => '';
}

void main() {
  testWidgets('a Google sign-in starts the profile with its email, so nobody types it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(SessionScope(
      session: GoogleSession(),
      child: MaterialApp(theme: buildTheme(Palette.dark), home: const ProfileScreen()),
    ));
    await tester.pump();

    // The form is a list, so the email field is built once it scrolls into view.
    final emailField = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Email');
    await tester.scrollUntilVisible(
      emailField,
      200,
      // The first scrollable is the form's own list (text fields have scrollables inside them).
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byWidgetPredicate((w) => w is EditableText && w.controller.text == 'fify@gmail.com'),
      findsOneWidget,
    );
    expect(find.text('From your Google account'), findsOneWidget);
    // The main button is pinned to the bottom, so the form never needs scrolling to reach it.
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(tester.getBottomLeft(find.widgetWithText(FilledButton, 'Done')).dy, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
  });
}
