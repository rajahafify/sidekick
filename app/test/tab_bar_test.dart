import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/screens/home.dart';
import 'package:sidekick/theme.dart';

/// Pumps the floating bottom bar alone, on a phone [width] logical pixels wide.
Future<void> pumpTabBar(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  C.use(Brightness.light);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Palette.light),
      home: const Scaffold(
        body: SizedBox.shrink(),
        bottomNavigationBar: HomeTabBar(tab: 0, messages: 2),
      ),
    ),
  );
}

/// The tap area (the tab's slot in the bar) that holds [content].
Rect tapArea(WidgetTester tester, Finder content) =>
    tester.getRect(find.ancestor(of: content, matching: find.byType(InkWell)));

void main() {
  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('on a ${width.toInt()} px phone the + sits in the middle, clear of every tab', (tester) async {
      await pumpTabBar(tester, width);

      final plus = tapArea(tester, find.byIcon(Icons.add_rounded));
      expect(plus.center.dx, closeTo(width / 2, 1));

      final tabs = [
        for (final label in ['Events', 'People', 'Messages', 'You']) tapArea(tester, find.text(label)),
      ];
      for (var i = 0; i < tabs.length; i++) {
        expect(tabs[i].overlaps(plus), isFalse, reason: 'tab $i overlaps the +');
        // Half a pixel of tolerance for the rounding in the flex split.
        expect(tabs[i].left, greaterThanOrEqualTo(-0.5));
        expect(tabs[i].right, lessThanOrEqualTo(width + 0.5));
        for (var j = i + 1; j < tabs.length; j++) {
          expect(tabs[i].overlaps(tabs[j]), isFalse, reason: 'tabs $i and $j overlap');
        }
      }
    });
  }
}
