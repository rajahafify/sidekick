import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Brightness (0 = black, 1 = white) at a point of a box of the given size.
typedef DotField = double Function(Offset p, Size s);

/// Draws any brightness field as a halftone: a staggered grid of dots whose size follows the
/// brightness. This is Sidekick's whole image style.
class Dots extends StatelessWidget {
  const Dots(this.field, {super.key, this.step = 8, this.color, this.fade});
  final DotField field;
  final double step;

  /// Ink unless told otherwise.
  final Color? color;

  /// Fades the dots out between these fractions of the height (e.g. (0.5, 0.8)), so text can sit on top.
  final (double, double)? fade;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _DotsPainter(field, step, color ?? C.ink, fade), size: Size.infinite),
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
/// used until people have photos. Drawn light on dark: the face is the brightest thing, hair and
/// shoulders are mid grey, and the room behind falls away to black.
DotField portraitField(String seed, {double headY = 0.42, double scale = 1}) {
  final h = seed.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
  final lightLeft = h.isEven;
  final hair = (h >> 1) % 3; // 0 cropped, 1 short, 2 long
  final shift = ((h >> 3) % 7 - 3) * 0.012;
  final bg = 0.07 + ((h >> 6) % 4) * 0.03;
  return (p, s) {
    final u = math.min(s.width, s.height) * scale;
    final c = Offset(s.width * (0.5 + shift), s.height * headY);
    final dir = lightLeft ? -1.0 : 1.0;
    final light = Offset(s.width * (0.5 + 0.35 * dir), s.height * 0.1);
    // Background: a soft spotlight from the lit side.
    var v = bg * (1 - ((p - light).distance / (s.longestSide * 0.9))).clamp(0.0, 1.0);
    // Shoulders, brighter on the lit side.
    final sh = _ellipse(p, c.translate(0, u * 0.8), u * 0.5, u * 0.44);
    if (sh < 1 && p.dy > c.dy + u * 0.3) {
      final side = ((p.dx - c.dx) / (u * 0.5)) * dir;
      v = 0.3 + 0.2 * ((side + 1) / 2).clamp(0.0, 1.0);
    }
    // Neck, in shadow under the chin.
    if ((p.dx - c.dx).abs() < u * 0.085 && p.dy > c.dy + u * 0.12 && p.dy < c.dy + u * 0.42) {
      v = 0.42 + 0.14 * (((p.dx - c.dx) / (u * 0.085)) * dir).clamp(-1.0, 1.0);
    }
    // Long hair falls behind the head and neck.
    if (hair == 2 && _ellipse(p, c.translate(0, u * 0.07), u * 0.235, u * 0.31) < 1 && p.dy < c.dy + u * 0.34) {
      v = math.max(v, 0.36);
    }
    // Head, lit from one side.
    final hd = _ellipse(p, c, u * 0.165, u * 0.21);
    if (hd < 1) {
      final side = ((p.dx - c.dx) / (u * 0.165)) * dir;
      v = (0.8 + 0.16 * side.clamp(-1.0, 1.0) + 0.06 * (1 - hd)).clamp(0.0, 1.0);
    }
    // Hair on top: mid grey, so it reads against both the face and the dark behind.
    final crown = hair == 0 ? 0.13 : 0.1;
    if (_ellipse(p, c.translate(0, -u * 0.02), u * 0.18, u * 0.225) < 1 && p.dy < c.dy - u * crown) {
      v = 0.44 + 0.1 * (((p.dx - c.dx) / (u * 0.18)) * dir).clamp(-1.0, 1.0);
    }
    return v;
  };
}

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

/// A dim room with a lit stage and the heads of a crowd: the picture on an event's poster,
/// a little different for each event (seeded by its id).
DotField roomField(String seed) {
  final h = seed.codeUnits.fold<int>(11, (a, c) => (a * 31 + c) & 0x7fffffff);
  final lx = 0.3 + (h % 40) / 100.0;
  final lean = ((h >> 5) % 5 - 2) * 0.09;
  final heads = 5 + (h >> 9) % 3;
  return (p, s) {
    final x = p.dx / s.width, y = p.dy / s.height;
    // The beam, widening as it falls.
    final d = (x - lx - y * lean).abs();
    var v = (1 - d / (0.1 + y * 0.42)).clamp(0.0, 1.0) * (1 - y * 0.55) * 0.95;
    // A second, fainter light from the other side.
    final d2 = (x - (1 - lx) + y * lean * 0.6).abs();
    v = math.max(v, (1 - d2 / (0.06 + y * 0.3)).clamp(0.0, 1.0) * (1 - y * 0.7) * 0.4);
    // The crowd: dark heads along the bottom edge, with a rim of light.
    for (var i = 0; i < heads; i++) {
      final cx = (i + 0.5 + ((h >> (i + 2)) % 5 - 2) * 0.06) / heads;
      final cy = 0.98 - ((h >> (i + 4)) % 4) * 0.035;
      final r = s.width / heads * 0.36;
      final dist = (Offset(cx * s.width, cy * s.height) - p).distance / r;
      if (dist < 1) v = dist > 0.82 ? math.max(v, 0.5) : 0.04;
    }
    return v;
  };
}
