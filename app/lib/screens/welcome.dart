import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/identity.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/google_button.dart';
import '../widgets/ui.dart';

/// The welcome carousel from the last web version: the room, the picks, the match.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String? busy;
  String? error;
  int page = 0;
  final _pages = PageController();
  // Moves to the next slide on its own, like the web version did, until someone swipes.
  late final Timer _auto = Timer.periodic(const Duration(seconds: 7), (_) {
    if (_pages.hasClients) {
      _pages.animateToPage((page + 1) % 3, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    }
  });

  @override
  void initState() {
    super.initState();
    _auto; // start the timer
  }

  @override
  void dispose() {
    _auto.cancel();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _run(String which, Future<void> Function() fn) async {
    setState(() {
      busy = which;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = e is IdentityError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final slides = [
      _Slide(
        art: const _FigCard(label: 'THE ROOM', child: RoomViz()),
        top: 'Stay in the talk.',
        title: (s) => TextSpan(children: [
          TextSpan(text: 'Your sidekick ', style: displayStyle(s, color: C.go, style: FontStyle.italic)),
          TextSpan(text: 'works the room.', style: displayStyle(s)),
        ]),
        text: 'Talks or networking? Have both. Your sidekick scouts everyone at the event while you listen.',
      ),
      _Slide(
        art: const _Notes(),
        top: 'It finds the people',
        title: (s) => TextSpan(text: 'worth meeting', style: displayStyle(s, color: C.go, style: FontStyle.italic)),
        text: 'It reads what everyone is looking for and can offer, and tells you why each person is worth your time.',
      ),
      _Slide(
        art: const _MatchArt(),
        title: (s) => TextSpan(children: [
          TextSpan(text: 'Swipe. Match. ', style: displayStyle(s)),
          TextSpan(text: 'Say hi.', style: displayStyle(s, color: C.go, style: FontStyle.italic)),
        ]),
        text: 'Connect or pass. When you both connect, you swap contacts and get an opener for the break. Nobody sees who passed.',
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Wordmark()),
                  const SizedBox(height: 8),
                  // The slides take whatever height is left, so the words and both sign-in
                  // buttons fit on one screen without scrolling.
                  Expanded(
                    child: ScrollConfiguration(
                      // Let a mouse drag the slides too, not only touch.
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
                      ),
                      // The slides move on their own only until someone touches them.
                      child: Listener(
                        onPointerDown: (_) => _auto.cancel(),
                        child: PageView(
                          controller: _pages,
                          onPageChanged: (i) => setState(() => page = i),
                          children: slides,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < slides.length; i++)
                      GestureDetector(
                        onTap: () {
                          _auto.cancel();
                          _pages.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == page ? 26 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == page ? C.ink : C.line,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  GoogleButton(
                    enabled: busy == null,
                    onResult: (e) {
                      if (e != null && mounted) setState(() => error = e is IdentityError ? e.message : '$e');
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: busy != null ? null : () => _run('guest', session.continueAsGuest),
                    child: busy == 'guest'
                        ? ButtonProgress(color: C.ink)
                        : const Text('Continue as guest'),
                  ),
                  ErrorNote(error),
                  const SizedBox(height: 12),
                  Text(
                    'Both sides opt in. Contacts stay hidden until you match.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.art, this.top, required this.title, required this.text});
  final Widget art;

  /// A plain first line above the title, if the slide has one.
  final String? top;

  /// The title's coloured words, at the size the slide can afford.
  final TextSpan Function(double size) title;
  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          // Short screens get smaller type, so the words still fit under the picture.
          final short = c.maxHeight < 560;
          final size = short ? 34.0 : 42.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The picture takes the height left over above the words, and keeps its shape.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(width: c.maxWidth, child: art),
                  ),
                ),
              ),
              SizedBox(height: short ? 14 : 24),
              if (top != null) Text(top!, style: displayStyle(size)),
              Text.rich(title(size)),
              const SizedBox(height: 12),
              Text(text, style: TextStyle(color: C.muted, fontSize: short ? 15 : 16.5, height: 1.5)),
            ],
          );
        },
      );
}

TextStyle get _mono => TextStyle(fontFamily: 'monospace', fontSize: 11, color: C.muted, letterSpacing: 0.6);

/// A figure card: "Fig 1" and a label on top, the drawing, and a caption the drawing provides.
class _FigCard extends StatelessWidget {
  const _FigCard({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1.25,
        child: Container(
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(child: child),
            Positioned(left: 14, top: 12, child: Text('Fig 1', style: _mono)),
            Positioned(right: 14, top: 12, child: Text(label, style: _mono)),
          ]),
        ),
      );
}

/// A talk in progress, drawn as an isometric line model: a stage and screen at the back, 24 seats
/// with an agent above each, and the agents' notes travelling between them. Orange links are the
/// people worth meeting.
class RoomViz extends StatefulWidget {
  const RoomViz({super.key});
  @override
  State<RoomViz> createState() => _RoomVizState();
}

class _RoomVizState extends State<RoomViz> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final met = (_RoomPainter.hops.length * _c.value).floor();
          final toMeet = _RoomPainter.hops.take(met).where((h) => h.$3).length;
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _RoomPainter(_c.value))),
            Positioned(
              right: 14,
              bottom: 12,
              child: Text('${math.min(24, met + 1)} of 24 agents met · $toMeet to meet', style: _mono),
            ),
          ]);
        },
      );
}

class _RoomPainter extends CustomPainter {
  _RoomPainter(this.t);
  final double t;

  static const cols = 6, rows = 4;
  // Your agent sits at seat 9. Each hop: from, to, and whether that person is worth meeting.
  static const you = 9;
  static const hops = [
    (9, 2, false), (2, 15, false), (15, 20, true), (20, 11, false), (11, 4, false),
    (4, 17, false), (17, 22, false), (22, 13, true), (13, 6, false), (6, 0, false),
    (0, 19, false), (19, 9, false),
  ];

  late Size _s;
  late double _u;

  /// Isometric projection of a point on the floor (gx along the rows, gy towards the back), lifted by z.
  Offset iso(double gx, double gy, [double z = 0]) {
    final cx = _s.width * 0.5, cy = _s.height * 0.6;
    return Offset(cx - (gx - gy) * _u * 0.87, cy + (gx + gy) * _u * 0.5 - z * _u);
  }

  Path quad(List<Offset> p) => Path()..addPolygon(p, true);

  Offset seatPos(int i) {
    final c = i % cols, r = i ~/ cols;
    return Offset(-2.6 + c * 1.05, -0.6 + r * 1.05);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _s = size;
    _u = size.width / 14.2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.ink.withValues(alpha: 0.55);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.ink.withValues(alpha: 0.22);
    final fill = Paint()..color = C.paper;
    final top = Paint()..color = C.soft;

    // The floor slab, with a little thickness.
    const x0 = -3.6, x1 = 3.4, y0 = -3.4, y1 = 3.8, h = 0.35;
    final slabTop = [iso(x0, y0, h), iso(x1, y0, h), iso(x1, y1, h), iso(x0, y1, h)];
    final front = [iso(x1, y0, h), iso(x1, y1, h), iso(x1, y1), iso(x1, y0)];
    final side = [iso(x0, y1, h), iso(x1, y1, h), iso(x1, y1), iso(x0, y1)];
    for (final f in [front, side]) {
      canvas.drawPath(quad(f), fill);
      canvas.drawPath(quad(f), line);
    }
    canvas.drawPath(quad(slabTop), top);
    canvas.drawPath(quad(slabTop), line);

    // The stage along the back, the speaker, and the screen standing behind.
    final st = [iso(-3.3, -3.1, h + 0.3), iso(3.1, -3.1, h + 0.3), iso(3.1, -1.7, h + 0.3), iso(-3.3, -1.7, h + 0.3)];
    canvas.drawPath(quad([iso(3.1, -3.1, h + 0.3), iso(3.1, -1.7, h + 0.3), iso(3.1, -1.7, h), iso(3.1, -3.1, h)]), fill);
    canvas.drawPath(quad([iso(-3.3, -1.7, h + 0.3), iso(3.1, -1.7, h + 0.3), iso(3.1, -1.7, h), iso(-3.3, -1.7, h)]), fill);
    canvas.drawPath(quad([iso(-3.3, -1.7, h + 0.3), iso(3.1, -1.7, h + 0.3), iso(3.1, -1.7, h), iso(-3.3, -1.7, h)]), line);
    canvas.drawPath(quad(st), top);
    canvas.drawPath(quad(st), line);
    final scr = [iso(-2.6, -3.0, h + 3.2), iso(1.2, -3.0, h + 3.2), iso(1.2, -3.0, h + 0.9), iso(-2.6, -3.0, h + 0.9)];
    canvas.drawPath(quad(scr), fill);
    canvas.drawPath(quad(scr), line);
    for (var k = 0; k < 4; k++) {
      final y = h + 2.7 - k * 0.38;
      canvas.drawLine(iso(-2.2, -3.0, y), iso(-2.2 + (k == 0 ? 1.6 : 3.0 - k * 0.3), -3.0, y), faint);
    }
    for (final lx in [-2.2, 0.8]) {
      canvas.drawLine(iso(lx, -3.0, h + 0.9), iso(lx, -3.0, h + 0.3), line);
    }
    _agent(canvas, iso(0.9, -2.3, h + 0.3), line, fill, glow: 0.4 + 0.3 * math.sin(t * math.pi * 24));

    // Where the note is now.
    final n = hops.length;
    final f = t * n;
    final hop = f.floor() % n;
    final along = Curves.easeInOut.transform(f - f.floor());
    final metSoFar = <int>{you};
    final worth = <int>{};
    for (var i = 0; i <= hop; i++) {
      metSoFar.add(hops[i].$1);
      if (i < hop || along > 0.95) {
        metSoFar.add(hops[i].$2);
        if (hops[i].$3) worth.add(hops[i].$2);
      }
    }

    // Seats, back rows first so the front ones overlap them.
    for (var i = 0; i < cols * rows; i++) {
      final p = seatPos(i);
      final g = Offset(p.dx, p.dy);
      final a = [iso(g.dx - 0.3, g.dy - 0.3, h + 0.3), iso(g.dx + 0.3, g.dy - 0.3, h + 0.3), iso(g.dx + 0.3, g.dy + 0.3, h + 0.3), iso(g.dx - 0.3, g.dy + 0.3, h + 0.3)];
      canvas.drawPath(quad([a[1], a[2], iso(g.dx + 0.3, g.dy + 0.3, h), iso(g.dx + 0.3, g.dy - 0.3, h)]), fill);
      canvas.drawPath(quad([a[3], a[2], iso(g.dx + 0.3, g.dy + 0.3, h), iso(g.dx - 0.3, g.dy + 0.3, h)]), fill);
      canvas.drawPath(quad([a[3], a[2], iso(g.dx + 0.3, g.dy + 0.3, h), iso(g.dx - 0.3, g.dy + 0.3, h)]), faint);
      canvas.drawPath(quad(a), top);
      canvas.drawPath(quad(a), line);
      // Seat back.
      canvas.drawPath(quad([iso(g.dx - 0.3, g.dy + 0.3, h + 0.3), iso(g.dx + 0.3, g.dy + 0.3, h + 0.3), iso(g.dx + 0.3, g.dy + 0.3, h + 0.85), iso(g.dx - 0.3, g.dy + 0.3, h + 0.85)]), fill);
      canvas.drawPath(quad([iso(g.dx - 0.3, g.dy + 0.3, h + 0.3), iso(g.dx + 0.3, g.dy + 0.3, h + 0.3), iso(g.dx + 0.3, g.dy + 0.3, h + 0.85), iso(g.dx - 0.3, g.dy + 0.3, h + 0.85)]), line);
      final isYou = i == you;
      _agent(canvas, iso(g.dx, g.dy, h + 0.55), line, fill,
          accent: isYou || worth.contains(i), glow: isYou ? 1 : (worth.contains(i) ? 0.8 : (metSoFar.contains(i) ? 0.25 : 0)));
    }

    // The note travelling between agents, with a dotted trail.
    final (from, to, good) = hops[hop];
    final pa = iso(seatPos(from).dx, seatPos(from).dy, h + 1.25);
    final pb = iso(seatPos(to).dx, seatPos(to).dy, h + 1.25);
    final mid = Offset((pa.dx + pb.dx) / 2, math.min(pa.dy, pb.dy) - _u * 1.4);
    final path = Path()
      ..moveTo(pa.dx, pa.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, pb.dx, pb.dy);
    final m = path.computeMetrics().first;
    final dot = Paint()..color = (good ? C.go : C.ink).withValues(alpha: 0.7);
    for (var d = 0.0; d < m.length * along; d += 5) {
      final tp = m.getTangentForOffset(d);
      if (tp != null) canvas.drawCircle(tp.position, 0.9, dot);
    }
    final head = m.getTangentForOffset(m.length * along);
    if (head != null) {
      canvas.drawCircle(head.position, 2.6, Paint()..color = good ? C.go : C.ink);
    }
  }

  /// A little capsule agent with a ring above it.
  void _agent(Canvas canvas, Offset base, Paint line, Paint fill, {bool accent = false, double glow = 0}) {
    final w = _u * 0.16, hgt = _u * 0.4;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(base.dx - w, base.dy - hgt, w * 2, hgt), Radius.circular(w));
    canvas.drawRRect(body, fill);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent ? C.go : C.ink.withValues(alpha: 0.5 + 0.5 * glow),
    );
    final ring = Rect.fromCenter(center: base.translate(0, -hgt - _u * 0.28), width: _u * 0.4, height: _u * 0.18);
    canvas.drawOval(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (accent ? C.go : C.ink).withValues(alpha: accent ? 0.9 : 0.15 + 0.5 * glow),
    );
  }

  @override
  bool shouldRepaint(_RoomPainter old) => old.t != t;
}

/// Slide 2: two notes from your sidekick about people in the room.
class _Notes extends StatelessWidget {
  const _Notes();

  @override
  Widget build(BuildContext context) {
    Widget note(String who, String text) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(name: who, seed: who, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: C.go, width: 2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('YOUR SIDEKICK', style: eyebrow.copyWith(fontSize: 10.5)),
                  const SizedBox(height: 4),
                  Text(text, style: const TextStyle(fontSize: 15, height: 1.35)),
                ]),
              ),
            ),
          ]),
        );
    return AspectRatio(
      aspectRatio: 1.25,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Padding(padding: const EdgeInsets.only(right: 34), child: note('Aisha R', 'Invests in seed fintech, and you’re raising.')),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.only(left: 34), child: note('Daniel O', 'Needs engineers. You offer engineering help.')),
      ]),
    );
  }
}

/// Slide 3: the match, and the opener your sidekick writes.
class _MatchArt extends StatelessWidget {
  const _MatchArt();

  @override
  Widget build(BuildContext context) {
    Widget circle(String t) => Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(color: signal, shape: BoxShape.circle),
          child: Avatar(name: t, seed: t, size: 90, ring: C.paper),
        );
    return AspectRatio(
      aspectRatio: 1.25,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text("IT'S A MATCH", style: eyebrow),
        const SizedBox(height: 16),
        SizedBox(
          width: 176,
          height: 96,
          child: Stack(children: [Positioned(left: 0, child: circle('Aisha R')), Positioned(right: 0, child: circle('You, here'))]),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(color: C.goSoft, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('OPENER', style: eyebrow.copyWith(fontSize: 10.5)),
            const SizedBox(height: 4),
            Text('“What made you start backing fintech?”', style: displayStyle(20, style: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }
}

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Can’t reach Sidekick',
            text: session.startError ?? 'Check your connection and try again.',
            action: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(180, 50)),
              onPressed: session.retry,
              child: const Text('Try again'),
            ),
          ),
        ),
      ),
    );
  }
}
