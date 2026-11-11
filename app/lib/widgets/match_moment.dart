
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'mark.dart';
import 'ui.dart';

/// The match moment: the whole screen goes dark, the two faces come together, and there is one
/// thing to do next. Returns true when the person wants to see the match.
Future<bool> showMatchMoment(
  BuildContext context, {
  required ({String name, String url, String seed}) me,
  required ({String name, String url, String seed}) them,
  required String firstName,
}) async {
  HapticFeedback.heavyImpact();
  return await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) =>
            _MatchMoment(me: me, them: them, firstName: firstName),
        transitionBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ) ==
      true;
}

class _MatchMoment extends StatefulWidget {
  const _MatchMoment({
    required this.me,
    required this.them,
    required this.firstName,
  });
  final ({String name, String url, String seed}) me;
  final ({String name, String url, String seed}) them;
  final String firstName;

  @override
  State<_MatchMoment> createState() => _MatchMomentState();
}

class _MatchMomentState extends State<_MatchMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// A burst of dots from the middle, fading at the edges.
  @override
  Widget build(BuildContext context) {
    final come = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.1, 0.7, curve: Curves.easeOutBack),
    );
    final words = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.45, 1, curve: Curves.easeOut),
    );
    Widget face(({String name, String url, String seed}) p) => Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(color: signal, shape: BoxShape.circle),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          color: Poster.bg,
          shape: BoxShape.circle,
        ),
        child: Avatar(name: p.name, url: p.url, seed: p.seed, size: 108),
      ),
    );
    return Material(
      color: Poster.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.0, end: 0.5).animate(
              CurvedAnimation(parent: _c, curve: const Interval(0, 0.6)),
            ),
            // A glow of Signal behind the two faces.
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.5),
                  radius: 0.95,
                  colors: [signal, Color(0x00FF5A36)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The faces and the words shrink together on a short screen, so the buttons always fit.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (_, box) => Align(
                            alignment: const Alignment(0, -0.25),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: box.maxWidth,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedBuilder(
                                      animation: come,
                                      builder: (_, _) {
                                        final gap = 150 - 110 * come.value;
                                        return SizedBox(
                                          height: 120,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Transform.translate(
                                                offset: Offset(
                                                  -gap / 2 - 16,
                                                  0,
                                                ),
                                                child: face(widget.me),
                                              ),
                                              Transform.translate(
                                                offset: Offset(gap / 2 + 16, 0),
                                                child: face(widget.them),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 34),
                                    FadeTransition(
                                      opacity: words,
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SidekickMark(
                                                size: 16,
                                                mood: BuddyMood.happy,
                                                color: Poster.ink,
                                                features: Poster.bg,
                                                cheeks: signal,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'IT’S A MATCH',
                                                style: const TextStyle(
                                                  color: signal,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'You and ${widget.firstName} both want to connect',
                                            textAlign: TextAlign.center,
                                            style: displayStyle(
                                              38,
                                              color: Poster.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          const Text(
                                            'Your contacts are swapped, and your sidekick wrote an opener for the break.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Poster.muted,
                                              fontSize: 15.5,
                                              height: 1.45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FadeTransition(
                        opacity: words,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SignalButton(
                              label: 'Say hi to ${widget.firstName}',
                              onPressed: () => Navigator.pop(context, true),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text(
                                'Keep scouting',
                                style: TextStyle(color: Poster.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
