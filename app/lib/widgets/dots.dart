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

/// The quest marker: a four-point sparkle over a dot.
Path questMarkPath(Rect box) {
  // Designed in a 120 x 160 box (from the 200 x 200 artboard, offset by 40, 20).
  final sx = box.width / 120, sy = box.height / 160;
  Offset o(double x, double y) => Offset(box.left + (x - 40) * sx, box.top + (y - 20) * sy);
  final a = o(100, 30), b = o(104, 58), c = o(112, 66), d = o(140, 70);
  final p = Path()..moveTo(a.dx, a.dy);
  void cubic(Offset c1, Offset c2, Offset e) => p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
  cubic(b, c, d);
  cubic(o(112, 74), o(104, 82), o(100, 110));
  cubic(o(96, 82), o(88, 74), o(60, 70));
  cubic(o(88, 66), o(96, 58), a);
  p.close();
  final dot = o(100, 148);
  p.addOval(Rect.fromCircle(center: dot, radius: 22 * sx));
  return p;
}

/// The solid mark, for buttons and small places.
class QuestMark extends StatelessWidget {
  const QuestMark({super.key, this.size = 20, this.color = C.ink});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 0.75,
    height: size,
    child: CustomPaint(painter: _MarkPainter(color)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size s) => canvas.drawPath(questMarkPath(Offset.zero & s), Paint()..color = color);
  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// The mark drawn in dots, for the welcome screen and the splash.
DotField markField({double markHeight = 0.62}) {
  Size? last;
  late Path path;
  return (p, s) {
    if (s != last) {
      last = s;
      final h = s.height * markHeight;
      path = questMarkPath(Rect.fromCenter(center: s.center(Offset.zero), width: h * 0.75, height: h));
    }
    return path.contains(p) ? 1.0 : 0.0;
  };
}
