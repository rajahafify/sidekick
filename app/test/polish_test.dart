import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/logic/chat.dart';
import 'package:sidekick/logic/contact.dart';
import 'package:sidekick/logic/profile.dart';
import 'package:sidekick/logic/sidekick.dart';
import 'package:sidekick/models.dart';
import 'package:sidekick/theme.dart';
import 'package:sidekick/widgets/contact.dart';
import 'package:sidekick/widgets/match_moment.dart';
import 'package:sidekick/widgets/ui.dart';

/// Relative luminance and contrast, as WCAG defines them.
double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  group('colours', () {
    test('small text passes 4.5:1 on the page in both looks', () {
      for (final p in [Palette.light, Palette.dark]) {
        expect(contrast(p.ink, p.paper), greaterThan(7), reason: 'ink on paper');
        expect(contrast(p.muted, p.paper), greaterThan(4.5), reason: 'muted on paper');
        expect(contrast(p.go, p.paper), greaterThan(4.5), reason: 'Signal text on paper');
        expect(contrast(p.danger, p.paper), greaterThan(4.5), reason: 'danger on paper');
        expect(contrast(p.onBrand, p.brand), greaterThan(7), reason: 'label on the main colour');
        expect(contrast(p.onSecond, p.second), greaterThan(7), reason: 'words on the secondary colour');
        expect(contrast(p.go, p.second), greaterThan(4.5), reason: 'Signal text on the secondary colour');
        expect(contrast(p.muted, p.second), greaterThan(4.5), reason: 'muted on the secondary colour');
      }
    });

    test('the Connect button is black on Signal, and words on a poster are white on black', () {
      expect(contrast(onSignal, signal), greaterThan(4.5));
      expect(contrast(Poster.ink, Poster.bg), greaterThan(7));
      expect(contrast(Poster.muted, Poster.bg), greaterThan(4.5));
    });
  });

  group('the sidekick’s lines', () {
    test('a pick is a strong fit, a good fit, or worth a hello', () {
      expect(fitLabel(100), 'Strong fit');
      expect(fitLabel(70), 'Strong fit');
      expect(fitLabel(69), 'Good fit');
      expect(fitLabel(40), 'Good fit');
      expect(fitLabel(39), 'Worth a hello');
    });

    test('the room briefing counts people and strong fits', () {
      expect(roomBriefing(scouted: 0, strong: 0, scouting: true), 'Scouting the room…');
      expect(roomBriefing(scouted: 0, strong: 0, scouting: false), 'Nobody new to scout yet.');
      expect(roomBriefing(scouted: 1, strong: 0, scouting: false), 'Read 1 person for you. Best fit first.');
      expect(roomBriefing(scouted: 5, strong: 1, scouting: false), 'Read 5 people for you. 1 strong fit, shown first.');
      expect(roomBriefing(scouted: 5, strong: 2, scouting: true), 'Still reading 5 people for you. 2 strong fits, shown first.');
    });

    test('the profile nudge asks for the most useful missing thing, then stops', () {
      const full = Profile(
        displayName: 'Fify',
        photoURL: 'https://example.com/p.jpg',
        headline: 'Founder',
        lookingFor: ['Funding'],
        offering: ['Advice'],
        about: 'Building Sidekick.',
      );
      expect(profileNudge(full), isNull);
      expect(profileNudge(const Profile(displayName: 'F')), contains('looking for'));
      expect(profileNudge(const Profile(displayName: 'F', lookingFor: ['Funding'])), contains('offer'));
      expect(
        profileNudge(const Profile(displayName: 'F', lookingFor: ['Funding'], offering: ['Advice'], headline: 'Founder')),
        contains('photo'),
      );
    });

    test('the greeting follows the hour', () {
      expect(greeting(DateTime(2026, 11, 11, 8)), 'Good morning');
      expect(greeting(DateTime(2026, 11, 11, 13)), 'Good afternoon');
      expect(greeting(DateTime(2026, 11, 11, 19)), 'Good evening');
      expect(greeting(DateTime(2026, 11, 11, 3)), 'Good evening');
    });
  });

  group('contact links', () {
    test('LinkedIn opens a handle or a LinkedIn address, and nothing else', () {
      expect('${linkedinUri('fify')}', 'https://www.linkedin.com/in/fify');
      expect('${linkedinUri('@fify')}', 'https://www.linkedin.com/in/fify');
      expect('${linkedinUri('linkedin.com/in/fify')}', 'https://linkedin.com/in/fify');
      expect('${linkedinUri('http://www.linkedin.com/in/fify')}', 'https://www.linkedin.com/in/fify');
      // A link to another site in the LinkedIn field is never opened.
      expect(linkedinUri('https://evil.example/login'), isNull);
      expect(linkedinUri('https://linkedin.com.evil.example/in/x'), isNull);
      expect(linkedinUri('javascript:alert(1)'), isNull);
      expect(linkedinUri(''), isNull);
    });

    test('a phone number opens WhatsApp and an email opens mail, when they look like one', () {
      expect('${whatsappUri('+60 12-345 6789')}', 'https://wa.me/60123456789');
      expect(whatsappUri('call me'), isNull);
      expect('${emailUri(' fify@example.com ')}', 'mailto:fify@example.com');
      expect(emailUri('not an email'), isNull);
    });

    testWidgets('a LinkedIn field pointing somewhere else is copied, not opened', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      C.use(Brightness.light);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Palette.light),
        home: const Scaffold(
          body: ContactLinks(contact: Contact(linkedin: 'https://evil.example/login')),
        ),
      ));

      await tester.tap(find.text('https://evil.example/login'));
      await tester.pump();

      expect(copied, 'https://evil.example/login');
      expect(find.text('LinkedIn copied'), findsOneWidget);
    });
  });

  group('chat times', () {
    final now = DateTime(2026, 11, 11, 15);
    test('days are labelled Today, Yesterday, then by date', () {
      expect(dayLabel(DateTime(2026, 11, 11, 9), now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 10, 23), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 11, 4, 9), now), 'Wed, 4 Nov');
      expect(dayLabel(DateTime(2025, 12, 31, 9), now), '31 Dec 2025');
    });

    test('list times are short', () {
      expect(ago(null, now), '');
      expect(ago(now.subtract(const Duration(seconds: 20)), now), 'now');
      expect(ago(now.subtract(const Duration(minutes: 12)), now), '12 min');
      expect(ago(now.subtract(const Duration(hours: 3)), now), '3 h');
      expect(ago(now.subtract(const Duration(days: 2)), now), 'Mon');
      expect(ago(now.subtract(const Duration(days: 20)), now), '22 Oct');
    });
  });

  group('components', () {
    testWidgets('the segments switch on a tap and report the choice', (tester) async {
      C.use(Brightness.light);
      var value = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Palette.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, set) => Segments<int>(
              items: const [(0, 'For you · 4'), (1, 'Matches · 1')],
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Matches · 1'));
      await tester.pumpAndSettle();

      expect(value, 1);
    });

    for (final size in [const Size(320, 568), const Size(390, 844)]) {
      testWidgets('the match moment fits a ${size.width.toInt()} px phone and leads to the match', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        C.use(Brightness.light);
        bool? result;
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Palette.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showMatchMoment(
                  context,
                  me: (name: 'Fify Zaed', url: '', seed: 'me'),
                  them: (name: 'Aisha Rahman', url: '', seed: 'a'),
                  firstName: 'Aisha',
                ),
                child: const Text('Match'),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('Match'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('You and Aisha both want to connect'), findsOneWidget);
        expect(tester.getRect(find.text('Keep scouting')).bottom, lessThanOrEqualTo(size.height));

        await tester.tap(find.text('Say hi to Aisha'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
      });
    }

    testWidgets('a confirm sheet names its action, and Cancel answers no', (tester) async {
      C.use(Brightness.light);
      bool? result;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Palette.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await confirmSheet(
                context,
                title: 'Leave this event?',
                text: 'You come out of the room.',
                action: 'Leave event',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Leave event'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
