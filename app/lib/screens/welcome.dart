import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/identity.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/dots.dart';
import '../widgets/ui.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String? busy;
  String? error;

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
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        SidekickMark(size: 14),
                        SizedBox(width: 10),
                        Text('SIDEKICK', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 2)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const AspectRatio(aspectRatio: 1.1, child: RoomViz()),
                    const SizedBox(height: 28),
                    Text('Stay in the talk.', style: displayStyle(46)),
                    Text(
                      'Your sidekick works the room.',
                      style: displayStyle(46, color: C.go, style: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Check in to an event or a place. Your sidekick scouts everyone there and tells you who is worth meeting. '
                      'Connect or pass. When you both connect, you swap contacts.',
                      style: TextStyle(color: C.muted, fontSize: 16, height: 1.45),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: busy != null ? null : () => _run('google', session.signInWithGoogle),
                      icon: busy == 'google' ? const ButtonProgress() : const _GoogleMark(),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy != null ? null : () => _run('guest', session.continueAsGuest),
                      child: busy == 'guest'
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: C.go),
                            )
                          : const Text('Continue as guest'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Guests can check in and see who the sidekick picks. Sign in with Google when you want to connect.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.muted, fontSize: 13),
                    ),
                    ErrorNote(error),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    child: const Text(
      'G',
      style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w700, fontSize: 14),
    ),
  );
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
            title: "Can't reach Sidekick",
            text: session.startError ?? 'Check your connection and try again.',
            action: FilledButton(onPressed: session.retry, child: const Text('Try again')),
          ),
        ),
      ),
    );
  }
}

/// A talk in progress, seen from above: the audience faces the stage, and their sidekicks
/// quietly trade notes across the room. The accent links are the matches being found.
class RoomViz extends StatefulWidget {
  const RoomViz({super.key});
  @override
  State<RoomViz> createState() => _RoomVizState();
}

class _RoomVizState extends State<RoomViz> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: C.paper,
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The stage light, in dots.
          const Dots(_spotlight, step: 9),
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(painter: _RoomPainter(_c.value)),
          ),
        ],
      ),
    ),
  );
}

double _spotlight(Offset p, Size s) {
  final d = (p - Offset(s.width / 2, s.height * 0.1)).distance / (s.longestSide * 0.95);
  return (0.75 * (1 - d) * (1 - d)).clamp(0.0, 1.0);
}

class _RoomPainter extends CustomPainter {
  _RoomPainter(this.t);
  final double t;

  static const rows = 6;
  static const cols = 7;
  // Pairs of seats whose sidekicks talk, and when in the loop (0..1) each link lights up.
  static const links = [
    [3, 30, 0.05],
    [8, 26, 0.18],
    [12, 39, 0.31],
    [1, 22, 0.44],
    [17, 33, 0.57],
    [5, 41, 0.70],
    [20, 36, 0.83],
  ];

  Offset seat(int i, Size s) {
    final r = i ~/ cols, c = i % cols;
    final top = s.height * 0.34, bottom = s.height * 0.92;
    final y = top + (bottom - top) * r / (rows - 1);
    final spread = 0.62 + 0.3 * r / (rows - 1); // rows widen towards the back
    final x = s.width / 2 + (c - (cols - 1) / 2) / ((cols - 1) / 2) * s.width * 0.42 * spread;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size s) {
    // Stage and speaker.
    final stage = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.13), width: s.width * 0.5, height: s.height * 0.07),
      const Radius.circular(10),
    );
    canvas.drawRRect(stage, Paint()..color = C.paper);
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 6);
    canvas.drawCircle(Offset(s.width / 2, s.height * 0.13), 5 + pulse * 1.5, Paint()..color = C.ink);
    for (var k = 1; k <= 3; k++) {
      final r = 12.0 + k * 10 + pulse * 4;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(s.width / 2, s.height * 0.13), radius: r),
        math.pi * 0.15,
        math.pi * 0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = C.ink.withValues(alpha: 0.18 / k),
      );
    }

    // Who is lit right now.
    final lit = <int, double>{};
    for (final l in links) {
      final start = l[2];
      var p = (t - start) % 1.0;
      if (p < 0) p += 1;
      if (p > 0.32) continue;
      final a = l[0].toInt(), b = l[1].toInt();
      final strength = p < 0.08 ? p / 0.08 : (p > 0.24 ? (0.32 - p) / 0.08 : 1.0);
      final pa = seat(a, s), pb = seat(b, s);
      final mid = Offset((pa.dx + pb.dx) / 2, math.min(pa.dy, pb.dy) - 30);
      final path = Path()
        ..moveTo(pa.dx, pa.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, pb.dx, pb.dy);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = C.go.withValues(alpha: 0.55 * strength),
      );
      // A note travelling along the link.
      final metric = path.computeMetrics().first;
      final along = ((p / 0.32) * 2) % 1.0;
      final tan = metric.getTangentForOffset(metric.length * along);
      if (tan != null) {
        canvas.drawCircle(tan.position, 2.4, Paint()..color = C.go.withValues(alpha: strength));
      }
      lit[a] = math.max(lit[a] ?? 0, strength);
      lit[b] = math.max(lit[b] ?? 0, strength);
    }

    // The audience, facing the stage.
    for (var i = 0; i < rows * cols; i++) {
      final p = seat(i, s);
      final glow = lit[i] ?? 0;
      if (glow > 0) {
        canvas.drawCircle(p, 12, Paint()..color = C.go.withValues(alpha: 0.18 * glow));
      }
      canvas.drawCircle(p, 6.4, Paint()..color = C.paper);
      canvas.drawCircle(p, 4.6, Paint()..color = Color.lerp(const Color(0xFFBDBDBD), C.go, glow)!);
    }
  }

  @override
  bool shouldRepaint(_RoomPainter old) => old.t != t;
}
