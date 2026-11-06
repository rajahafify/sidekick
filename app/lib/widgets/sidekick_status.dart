import 'package:flutter/material.dart';

import '../main.dart';
import '../theme.dart';
import 'ui.dart';

/// Shows whether the sidekick's model is answering. Loads the last known state, and "Check now"
/// sends the model a tiny prompt and reports how fast it replied (or why it didn't).
class SidekickStatusCard extends StatefulWidget {
  const SidekickStatusCard({super.key});
  @override
  State<SidekickStatusCard> createState() => _SidekickStatusCardState();
}

enum _State { unknown, working, down, off }

class _SidekickStatusCardState extends State<SidekickStatusCard> {
  bool checking = false;
  _State state = _State.unknown;
  String? model;
  String detail = 'Checking…';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (state == _State.unknown && detail == 'Checking…') _load();
  }

  Future<void> _load() async {
    try {
      final s = await SessionScope.of(context).api.status();
      if (!mounted) return;
      final ok = DateTime.tryParse('${s['lastOk'] ?? ''}');
      final err = s['lastError'] is Map ? (s['lastError'] as Map).cast<String, dynamic>() : null;
      final errAt = DateTime.tryParse('${err?['at'] ?? ''}');
      setState(() {
        model = s['model'] as String?;
        if (model == null) {
          state = _State.off;
          detail = 'No model is set up, so the sidekick uses quick reads.';
        } else if (ok == null && errAt == null) {
          state = _State.unknown;
          detail = 'No calls yet. Tap Check now.';
        } else if (errAt != null && (ok == null || errAt.isAfter(ok))) {
          state = _State.down;
          detail = 'Last call failed ${_ago(errAt)}: ${err?['error'] ?? 'no reply'}';
        } else {
          state = _State.working;
          detail = 'Last answered ${_ago(ok!)}.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => detail = '$e');
    }
  }

  Future<void> _check() async {
    setState(() => checking = true);
    try {
      final r = await SessionScope.of(context).api.checkSidekick();
      if (!mounted) return;
      setState(() {
        model = r['model'] as String? ?? model;
        if (r['model'] == null) {
          state = _State.off;
          detail = '${r['error']}';
        } else if (r['ok'] == true) {
          state = _State.working;
          detail = 'Answered just now in ${((r['ms'] as num) / 1000).toStringAsFixed(1)} s.';
        } else {
          state = _State.down;
          detail = 'No answer: ${r['error'] ?? 'unknown error'}. Picks fall back to quick reads.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => detail = '$e');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      _State.working => ('Working', C.go),
      _State.down => ('Not answering', C.danger),
      _State.off => ('Off', C.muted),
      _State.unknown => ('Not checked', C.muted),
    };
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('YOUR SIDEKICK', style: eyebrow)),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          Text(detail, style: const TextStyle(fontSize: 15, height: 1.4)),
          if (model != null) ...[
            const SizedBox(height: 4),
            Text(model!, style: const TextStyle(color: C.muted, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: checking ? null : _check,
            child: checking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.go))
                : const Text('Check now'),
          ),
        ],
      ),
    );
  }
}
