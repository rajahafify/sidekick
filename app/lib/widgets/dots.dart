import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Brightness (0 = black, 1 = white) at a point of a box of the given size.
typedef DotField = double Function(Offset p, Size s);

/// Draws any brightness field as a halftone: a staggered grid of dots whose size follows the
/// brightness. This is Sidekick's whole image style.
class Dots extends StatelessWidget {
  const Dots(this.field, {super.key, this.step = 8, this.color = C.ink, this.fade});
  final DotField field;
  final double step;
  final Color color;

  /// Fades the dots out between these fractions of the height (e.g. (0.5, 0.8)), so text can sit on top.
  final (double, double)? fade;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _DotsPainter(field, step, color, fade), size: Size.infinite),
  );
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.field, this.step, this.color, this.fade);
  final DotField field;
  final double step;
  final Color color;
  final (double, double)? fade;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()..color = color;
    var row = 0;
    for (var y = step / 2; y < s.height; y += step, row++) {
      var f = 1.0;
      if (fade != null) {
        final (a, b) = fade!;
        final t = (y / s.height - a) / (b - a);
        f = 1 - t.clamp(0.0, 1.0);
        if (f <= 0) break;
      }
      for (var x = step / 2 + (row.isOdd ? step / 2 : 0); x < s.width; x += step) {
        final v = (field(Offset(x, y), s) * f).clamp(0.0, 1.0);
        final r = math.sqrt(v) * step * 0.52;
        if (r < 0.35) continue;
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.field != field || old.step != step || old.color != color || old.fade != fade;
}

double _ellipse(Offset p, Offset c, double rx, double ry) {
  final dx = (p.dx - c.dx) / rx, dy = (p.dy - c.dy) / ry;
  return dx * dx + dy * dy;
}

/// A studio-style head-and-shoulders portrait, different for each person (seeded by their id),
/// used until people have photos.
DotField portraitField(String seed, {double headY = 0.42, double scale = 1}) {
  final h = seed.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
  final lightLeft = h.isEven;
  final hair = (h >> 1) % 3; // 0 none, 1 short, 2 long
  final shift = ((h >> 3) % 7 - 3) * 0.012;
  final bg = 0.16 + ((h >> 6) % 4) * 0.05;
  return (p, s) {
    final u = math.min(s.width, s.height) * scale;
    final c = Offset(s.width * (0.5 + shift), s.height * headY);
    final dir = lightLeft ? -1.0 : 1.0;
    final light = Offset(s.width * (0.5 + 0.35 * dir), s.height * 0.1);
    // Background: a soft spotlight from the lit side.
    var v = bg * (1 - ((p - light).distance / (s.longestSide * 0.9))).clamp(0.0, 1.0);
    // Shoulders, with a rim of light on one side.
    final sh = _ellipse(p, c.translate(0, u * 0.7), u * 0.52, u * 0.36);
    if (sh < 1 && p.dy > c.dy + u * 0.36) {
      final side = ((p.dx - c.dx) / (u * 0.52)) * dir;
      v = 0.2 + 0.4 * ((side + 1) / 2).clamp(0.0, 1.0) * (0.4 + 0.6 * math.sqrt(sh));
    }
    // Neck, in shadow under the chin.
    if ((p.dx - c.dx).abs() < u * 0.1 && p.dy > c.dy + u * 0.12 && p.dy < c.dy + u * 0.42) {
      v = 0.28 + 0.2 * (((p.dx - c.dx) / (u * 0.1)) * dir).clamp(0.0, 1.0);
    }
    // Head, lit from one side.
    final hd = _ellipse(p, c, u * 0.18, u * 0.235);
    if (hd < 1) {
      final side = ((p.dx - c.dx) / (u * 0.18)) * dir;
      v = 0.5 + 0.45 * side.clamp(-1.0, 1.0) * 0.6 + 0.25 * (1 - hd);
    }
    // Hair.
    final cap = _ellipse(p, c.translate(0, -u * 0.07), u * 0.2, u * 0.21) < 1 && p.dy < c.dy - u * 0.08;
    final longHair = _ellipse(p, c.translate(0, u * 0.06), u * 0.25, u * 0.33) < 1;
    if (hair == 2 && longHair && hd >= 1 && p.dy < c.dy + u * 0.32) v = 0.1;
    if (hair > 0 && cap) v = 0.1 + 0.12 * (((p.dx - c.dx) / (u * 0.2)) * dir).clamp(0.0, 1.0);
    return v;
  };
}

enum BuddyMood { normal, wink, happy }

/// Width / height of Buddy.
const markAspect = 152 / 120;

/// Buddy, the Sidekick mascot: a round robot head with a visor and smiling orange eyes.
/// [size] is its height. It winks when it has spotted someone and beams on a match.
class SidekickMark extends StatelessWidget {
  const SidekickMark({
    super.key,
    this.size = 20,
    this.color = C.ink,
    this.visor = C.paper,
    this.eyes = C.go,
    this.mood = BuddyMood.normal,
  });
  final double size;
  final Color color;
  final Color visor;
  final Color eyes;
  final BuddyMood mood;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * markAspect,
    height: size,
    child: CustomPaint(
      painter: BuddyPainter(color: color, visor: visor, eyes: eyes, mood: mood),
    ),
  );
}

class BuddyPainter extends CustomPainter {
  BuddyPainter({required this.color, required this.visor, required this.eyes, required this.mood});
  final Color color, visor, eyes;
  final BuddyMood mood;

  // Drawn on a 200 x 200 artboard; Buddy spans x 24..176, y 52..172.
  static const art = Rect.fromLTRB(24, 52, 176, 172);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.scale(s.width / art.width, s.height / art.height);
    canvas.translate(-art.left, -art.top);
    final body = Paint()..color = color;
    // Ears, head, visor.
    canvas.drawCircle(const Offset(36, 113), 12, body);
    canvas.drawCircle(const Offset(164, 113), 12, body);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 52, 140, 120), const Radius.circular(56)), body);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(50, 76, 100, 70), const Radius.circular(35)),
      Paint()..color = visor,
    );
    // Smiling eyes and mouth.
    Paint stroke(double w) => Paint()
      ..color = eyes
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    Path arc(double x) => Path()
      ..moveTo(x - 12, 110)
      ..quadraticBezierTo(x, 94, x + 12, 110);
    if (mood == BuddyMood.wink) {
      canvas.drawCircle(const Offset(80, 104), 9, Paint()..color = eyes);
    } else {
      canvas.drawPath(arc(80), stroke(8));
    }
    canvas.drawPath(arc(120), stroke(8));
    if (mood == BuddyMood.happy) {
      // A wide open grin.
      canvas.drawPath(
        Path()
          ..moveTo(86, 124)
          ..quadraticBezierTo(100, 144, 114, 124)
          ..close(),
        Paint()..color = eyes,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(88, 126)
          ..quadraticBezierTo(100, 136, 112, 126),
        stroke(6),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BuddyPainter old) =>
      old.color != color || old.visor != visor || old.eyes != eyes || old.mood != mood;
}
