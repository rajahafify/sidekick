import 'package:flutter/material.dart';

import '../theme.dart';

enum BuddyMood { normal, wink, happy }

/// Width / height of Buddy.
const markAspect = 140 / 120;

/// Buddy, the Sidekick mascot: a soft round face with shiny eyes and orange cheeks.
/// [size] is its height. It winks when it has spotted someone and grins on a match.
class SidekickMark extends StatelessWidget {
  const SidekickMark({
    super.key,
    this.size = 20,
    this.color,
    this.features,
    this.cheeks,
    this.mood = BuddyMood.normal,
  });
  final double size;

  /// The face. Ink unless told otherwise.
  final Color? color;

  /// Eyes and mouth. Paper unless told otherwise.
  final Color? features;
  final Color? cheeks;
  final BuddyMood mood;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * markAspect,
    height: size,
    child: CustomPaint(
      painter: BuddyPainter(color: color ?? C.ink, features: features ?? C.paper, cheeks: cheeks ?? C.go, mood: mood),
    ),
  );
}

class BuddyPainter extends CustomPainter {
  BuddyPainter({required this.color, required this.features, required this.cheeks, required this.mood});
  final Color color, features, cheeks;
  final BuddyMood mood;

  // Drawn on a 200 x 200 artboard; Buddy spans x 30..170, y 52..172.
  static const art = Rect.fromLTRB(30, 52, 170, 172);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.scale(s.width / art.width, s.height / art.height);
    canvas.translate(-art.left, -art.top);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(30, 52, 140, 120), const Radius.circular(58)),
      Paint()..color = color,
    );
    final ink = Paint()..color = features;
    final line = Paint()
      ..color = features
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    // Cheeks.
    final blush = Paint()..color = cheeks.withValues(alpha: 0.9);
    canvas.drawOval(Rect.fromCenter(center: const Offset(62, 126), width: 20, height: 12), blush);
    canvas.drawOval(Rect.fromCenter(center: const Offset(138, 126), width: 20, height: 12), blush);
    // Eyes, with a shine. The right one closes for a wink.
    void eye(double x) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, 104), width: 22, height: 28), ink);
      canvas.drawCircle(Offset(x + 4, 98), 4, Paint()..color = color);
    }

    eye(78);
    if (mood == BuddyMood.wink) {
      canvas.drawPath(
        Path()
          ..moveTo(110, 106)
          ..quadraticBezierTo(122, 94, 134, 106),
        line,
      );
    } else {
      eye(122);
    }
    // Mouth: a smile, or a grin on a match.
    if (mood == BuddyMood.happy) {
      canvas.drawPath(
        Path()
          ..moveTo(86, 128)
          ..quadraticBezierTo(100, 150, 114, 128)
          ..close(),
        ink,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(88, 130)
          ..quadraticBezierTo(100, 142, 112, 130),
        line,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BuddyPainter old) =>
      old.color != color || old.features != features || old.cheeks != cheeks || old.mood != mood;
}
