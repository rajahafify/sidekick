import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';

/// A "Where" field with place suggestions from Amazon Location. Typing freely still works.
class PlaceField extends StatefulWidget {
  const PlaceField({super.key, required this.controller, required this.onPicked, this.label = 'Where', this.hint});
  final TextEditingController controller;

  /// Called with the place when a suggestion is picked, or null when the text is edited by hand.
  final ValueChanged<PlaceDetails?> onPicked;
  final String label;
  final String? hint;

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  List<PlaceDetails> suggestions = const [];
  Timer? _debounce;
  String _picked = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String v) {
    if (v != _picked) widget.onPicked(null);
    _debounce?.cancel();
    if (v.trim().length < 3) {
      setState(() => suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final api = SessionScope.of(context).api;
      final s = await api.placeSuggestions(v.trim());
      if (mounted && widget.controller.text == v) setState(() => suggestions = s);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.controller,
            maxLength: 140,
            onChanged: _changed,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              counterText: '',
              prefixIcon: const Icon(Icons.place_outlined, color: C.muted),
            ),
          ),
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.line),
              ),
              child: Column(
                children: [
                  for (final p in suggestions)
                    ListTile(
                      dense: true,
                      title: Text(p.name, style: const TextStyle(fontSize: 15)),
                      subtitle: p.address.isEmpty ? null : Text(p.address, style: const TextStyle(color: C.muted)),
                      onTap: () {
                        final label = p.label.length > 140 ? p.label.substring(0, 140) : p.label;
                        _picked = label;
                        widget.controller.text = label;
                        widget.onPicked(p);
                        setState(() => suggestions = const []);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                ],
              ),
            ),
        ],
      );
}
