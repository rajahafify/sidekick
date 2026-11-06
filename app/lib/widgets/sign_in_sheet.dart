import 'package:flutter/material.dart';

import '../data/identity.dart';
import '../main.dart';
import '../theme.dart';
import 'ui.dart';

/// Guests can look, but connecting needs a real account. Returns true once signed in.
/// Everything the guest did (profile, check-ins) carries over.
Future<bool> askToSignIn(BuildContext context, {String? reason}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SignInSheet(reason: reason),
  );
  return ok == true;
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({this.reason});
  final String? reason;
  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  bool busy = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in to connect', style: displayStyle(34)),
            const SizedBox(height: 10),
            Text(
              widget.reason ??
                  'Connecting shares your contact details when it’s mutual, so it needs a real account. '
                      'Your profile and check-ins stay as they are.',
              style: const TextStyle(color: C.muted, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await session.signInWithGoogle();
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setState(() => error = e is IdentityError ? e.message : '$e');
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: busy ? const ButtonProgress() : const Text('Continue with Google'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now', style: TextStyle(color: C.muted)),
            ),
            ErrorNote(error),
          ],
        ),
      ),
    );
  }
}
