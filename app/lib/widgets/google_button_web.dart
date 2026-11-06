import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as gis;

import '../config.dart';
import '../main.dart';
import 'google_button_io.dart' as io;

/// Google's own sign-in button. The result arrives through the session once Google is done.
class GoogleButton extends StatefulWidget {
  const GoogleButton({super.key, required this.onResult, this.enabled = true});
  final ValueChanged<Object?> onResult;
  final bool enabled;
  @override
  State<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<GoogleButton> {
  Future<void>? _ready;
  StreamSubscription<Object?>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Config.useDevApi || _ready != null) return;
    final session = SessionScope.of(context);
    _ready = session.prepareGoogle();
    _sub = session.webSignIns.listen(widget.onResult);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The local dev server fakes Google, so the normal button is enough there.
    if (Config.useDevApi) return io.GoogleButton(onResult: widget.onResult, enabled: widget.enabled);
    return SizedBox(
      height: 54,
      child: FutureBuilder(
        future: _ready,
        builder: (context, s) => s.connectionState != ConnectionState.done
            ? const SizedBox.shrink()
            : Center(
                child: LayoutBuilder(
                  builder: (context, c) => gis.renderButton(
                    configuration: gis.GSIButtonConfiguration(
                      theme: gis.GSIButtonTheme.outline,
                      shape: gis.GSIButtonShape.pill,
                      size: gis.GSIButtonSize.large,
                      text: gis.GSIButtonText.continueWith,
                      minimumWidth: c.maxWidth.clamp(200, 400).toDouble(),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
