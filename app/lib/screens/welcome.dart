import 'package:flutter/material.dart';

import '../data/identity.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/google_button.dart';
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

  static const _steps = [
    ('Join the event', 'Scan the QR code or open the link. No host needed.'),
    ('Your sidekick scouts', 'It reads who’s here and ranks who’s relevant to you, with a reason for each.'),
    ('Connect or pass', 'Nobody sees who passed, or who connected with them before it’s mutual.'),
    ('Match and swap contacts', 'When you both connect, you get each other’s contact and an opener.'),
  ];

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 40),
              children: [
                const Align(alignment: Alignment.centerLeft, child: Wordmark()),
                const SizedBox(height: 64),
                const Text('FOR PEOPLE WHO GO TO EVENTS', style: eyebrow),
                const SizedBox(height: 16),
                Text('Stay in the talk.', style: displayStyle(52)),
                Text('Your sidekick', style: displayStyle(52, color: C.go, style: FontStyle.italic)),
                Text('works the room.', style: displayStyle(52)),
                const SizedBox(height: 22),
                const Text(
                  'At every event you have to choose: listen to the talks, or go network. Your sidekick scouts '
                  'everyone in the room and lines up the people worth meeting. You swipe Connect or Pass. When you '
                  'both connect, you swap contacts and get an opener for the break.',
                  style: TextStyle(color: C.muted, fontSize: 17, height: 1.55),
                ),
                const SizedBox(height: 32),
                GoogleButton(
                  enabled: busy == null,
                  onResult: (e) {
                    if (e != null && mounted) setState(() => error = e is IdentityError ? e.message : '$e');
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy != null ? null : () => _run('guest', session.continueAsGuest),
                  child: busy == 'guest'
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.go))
                      : const Text('Continue as guest'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Guests can check in and see who the sidekick picks. Sign in with Google to connect.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted, fontSize: 13),
                ),
                ErrorNote(error),
                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 28),
                for (final (i, (title, text)) in _steps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text('${i + 1}', style: displayStyle(34, color: C.go, style: FontStyle.italic)),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text(text, style: const TextStyle(color: C.muted, fontSize: 15, height: 1.45)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Both sides opt in. Contacts stay hidden until you match.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
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
            title: "Can't reach Sidekick",
            text: session.startError ?? 'Check your connection and try again.',
            action: FilledButton(onPressed: session.retry, child: const Text('Try again')),
          ),
        ),
      ),
    );
  }
}
