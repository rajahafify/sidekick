import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/widgets/dots.dart';

void main() {
  test('the mask fills the box it is drawn in', () {
    const box = Rect.fromLTWH(10, 20, 172, 80);
    final b = maskPath(box).getBounds();
    expect(b.left, closeTo(10, 1));
    expect(b.right, closeTo(182, 1));
    expect(b.height, greaterThan(60));
    // The open eye is a hole; the winking eye is solid.
    expect(maskPath(box).contains(const Offset(10 + 62 - 14, 20 + 96 - 56)), isFalse);
    expect(maskPath(box).contains(const Offset(10 + 138 - 14, 20 + 96 - 56)), isTrue);
    expect(maskPath(box, wink: false).contains(const Offset(10 + 138 - 14, 20 + 96 - 56)), isFalse);
  });
}
