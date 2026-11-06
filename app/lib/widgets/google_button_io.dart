import 'package:flutter/material.dart';

import '../main.dart';
import 'ui.dart';

/// Signs in with Google and reports the result: null on success, or the error.
class GoogleButton extends StatefulWidget {
  const GoogleButton({super.key, required this.onResult, this.enabled = true});
  final ValueChanged<Object?> onResult;
  final bool enabled;
  @override
  State<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<GoogleButton> {
  bool busy = false;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy || !widget.enabled
        ? null
        : () async {
            setState(() => busy = true);
            Object? error;
            try {
              await SessionScope.of(context).signInWithGoogle();
            } catch (e) {
              error = e;
            }
            if (mounted) setState(() => busy = false);
            widget.onResult(error);
          },
    icon: busy ? const ButtonProgress() : const GoogleMark(),
    label: const Text('Continue with Google'),
  );
}
