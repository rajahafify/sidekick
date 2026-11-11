import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/widgets/mark.dart';

void main() {
  testWidgets('Buddy draws in every mood at its own aspect ratio', (tester) async {
    for (final mood in BuddyMood.values) {
      await tester.pumpWidget(Center(child: SidekickMark(size: 40, mood: mood)));
      final size = tester.getSize(find.byType(SidekickMark));
      expect(size.height, 40);
      expect(size.width, closeTo(40 * markAspect, 0.01));
    }
  });
}
