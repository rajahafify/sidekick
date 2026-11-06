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

/// The Sidekick mark: a domino mask with a wink. The left eye is open; the right eye is a
/// sparkle (your sidekick spotted someone). Drawn on a 200 x 200 artboard; the mask spans
/// x 14..186 and y 56..136.
const _maskOutline =
    'M14 96 C24 64 66 56 100 70 C134 56 176 64 186 96 C178 128 146 138 120 122 C111 116 105 115 100 120 '
    'C95 115 89 116 80 122 C54 138 22 128 14 96Z';
const _leftEye = 'M40 98 C46 84 70 80 84 92 C78 106 52 110 40 98Z';
const _rightEye = 'M160 98 C154 84 130 80 116 92 C122 106 148 110 160 98Z';
const _spark = 'M138 76 C140 88 143 91 155 93 C143 95 140 98 138 110 C136 98 133 95 121 93 C133 91 136 88 138 76Z';
const _art = Rect.fromLTRB(14, 56, 186, 136);

/// Width / height of the mark.
const markAspect = 172 / 80;

/// Parses the absolute M / C / Z path data used above.
Path _svg(String d, Rect box) {
  final sx = box.width / _art.width, sy = box.height / _art.height;
  final t = RegExp(r'[MCZ]|-?\d+(\.\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  final p = Path();
  var i = 0;
  double n() => double.parse(t[i++]);
  Offset pt() {
    final x = n(), y = n();
    return Offset(box.left + (x - _art.left) * sx, box.top + (y - _art.top) * sy);
  }

  String cmd = 'M';
  while (i < t.length) {
    if (RegExp(r'^[MCZ]$').hasMatch(t[i])) cmd = t[i++];
    if (cmd == 'Z') {
      p.close();
      continue;
    }
    if (cmd == 'M') {
      final a = pt();
      p.moveTo(a.dx, a.dy);
      cmd = 'C';
    } else {
      final a = pt(), b = pt(), c = pt();
      p.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
    }
  }
  return p;
}

/// The mask with its eye holes. With [wink], the right eye is left closed for the sparkle.
Path maskPath(Rect box, {bool wink = true}) {
  final p = _svg(_maskOutline, box)..addPath(_svg(_leftEye, box), Offset.zero);
  if (!wink) p.addPath(_svg(_rightEye, box), Offset.zero);
  return p..fillType = PathFillType.evenOdd;
}

Path sparkPath(Rect box) => _svg(_spark, box);

/// The mark. [size] is its height. The sparkle takes [sparkColor]; without one, both eyes are open.
class SidekickMark extends StatelessWidget {
  const SidekickMark({super.key, this.size = 20, this.color = C.ink, this.sparkColor = C.go});
  final double size;
  final Color color;
  final Color? sparkColor;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * markAspect,
    height: size,
    child: CustomPaint(painter: _MarkPainter(color, sparkColor)),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color, this.spark);
  final Color color;
  final Color? spark;
  @override
  void paint(Canvas canvas, Size s) {
    final box = Offset.zero & s;
    canvas.drawPath(maskPath(box, wink: spark != null), Paint()..color = color);
    if (spark != null) canvas.drawPath(sparkPath(box), Paint()..color = spark!);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color || old.spark != spark;
}
