import 'package:flutter/material.dart';

import '../theme.dart';

/// The deep colours a poster can be lit in. Each person and event keeps one (picked from its id),
/// so a face with no photo is still told apart at a glance. All are dark enough for Oat words.
const _tones = <(Color, Color)>[
  (Color(0xFF1F6148), Color(0xFF0A2419)), // pine
  (Color(0xFF1C5A63), Color(0xFF0A2227)), // lagoon
  (Color(0xFF56602B), Color(0xFF1B2110)), // moss
  (Color(0xFF8A4A30), Color(0xFF2C150D)), // clay
  (Color(0xFF58385F), Color(0xFF1E1222)), // plum
];

int _hash(String seed) => seed.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);

/// The two colours of the poster for [seed], light then deep.
(Color, Color) toneOf(String seed) => _tones[_hash(seed) % _tones.length];

/// Up to two initials for a name, or "?".
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first.toUpperCase();
  return words.length == 1 ? first : first + words.last.characters.first.toUpperCase();
}

/// Soft lit colour: what a poster shows where there is no photo. A deep gradient with a glow of
/// light from one corner, a little different for each [seed].
class PosterArt extends StatelessWidget {
  const PosterArt(this.seed, {super.key, this.monogram, this.monogramAt = const Alignment(0, -0.3)});
  final String seed;

  /// Initials set large in the serif, for a person.
  final String? monogram;
  final Alignment monogramAt;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _ArtPainter(_hash(seed)),
          child: monogram == null
              ? const SizedBox.expand()
              : LayoutBuilder(
                  builder: (_, c) => Align(
                    alignment: monogramAt,
                    child: Text(
                      monogram!,
                      style: displayStyle(
                        c.biggest.shortestSide * (monogram!.length > 1 ? 0.4 : 0.5),
                        color: Poster.ink.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ),
        ),
      );
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.h);
  final int h;

  @override
  void paint(Canvas canvas, Size s) {
    final (hi, lo) = _tones[h % _tones.length];
    final rect = Offset.zero & s;
    final left = (h >> 3).isEven;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: left ? Alignment.topLeft : Alignment.topRight,
          end: left ? Alignment.bottomRight : Alignment.bottomLeft,
          colors: [hi, lo],
        ).createShader(rect),
    );
    void glow(Offset c, double r, Color color) => canvas.drawCircle(
          c,
          r,
          Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
        );
    final x = 0.18 + ((h >> 5) % 20) / 100.0;
    glow(Offset(s.width * (left ? x : 1 - x), s.height * 0.12), s.longestSide * 0.7, const Color(0x38FFFFFF));
    glow(Offset(s.width * (left ? 0.95 : 0.05), s.height * 0.78), s.longestSide * 0.55, hi.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.h != h;
}
