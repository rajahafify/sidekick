import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/identity.dart';
import '../logic/geo_when.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/google_button.dart';
import '../widgets/ui.dart';

/// A small admin screen: open reports, every event and everyone, with delete.
/// Shown on admin-sidekick.artifisi.com, and at /admin in the app. The API only answers
/// accounts listed in the ADMIN_IDENTITY_IDS GitHub variable, signed in with Google.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool notAdmin = false;
  bool loading = false;
  String _loadedFor = '';
  int tab = 0;
  String query = '';

  Api get api => SessionScope.of(context).api;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = SessionScope.of(context);
    final key = s.started && !s.guest ? s.uid : '';
    if (key != _loadedFor) {
      _loadedFor = key;
      if (key.isNotEmpty) _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await api.adminOverview();
      if (mounted) {
        setState(() {
          data = d;
          notAdmin = false;
        });
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          notAdmin = e.status == 403;
          error = e.status == 403 ? null : e.message;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _delete(String kind, String id, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('Delete $what?'),
        content: Text(switch (kind) {
          'users' => 'Their profile, check-ins, swipes and matches are deleted. This can’t be undone.',
          'events' => 'The event, everyone’s check-ins, swipes and matches there are deleted. This can’t be undone.',
          _ => 'The report is removed from the list.',
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(kind == 'reports' ? 'Remove' : 'Delete', style: const TextStyle(color: C.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await api.adminDelete(kind, id);
      if (mounted) toast(context, kind == 'reports' ? 'Report removed.' : 'Deleted.');
      await _load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final Widget body;
    if (!session.started || session.guest) {
      body = _SignIn(onError: (e) => setState(() => error = e));
    } else if (notAdmin) {
      body = _NotAdmin(id: session.uid, onSignOut: session.signOut, onRetry: _load);
    } else if (data == null) {
      body = error == null ? const Loading() : EmptyState(title: "Can't load", text: error!, action: FilledButton(onPressed: _load, child: const Text('Try again')));
    } else {
      body = _dashboard(session.uid);
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                  child: Row(children: [
                    const Wordmark(),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: C.goSoft, borderRadius: BorderRadius.circular(99)),
                      child: Text('ADMIN', style: eyebrow.copyWith(fontSize: 11)),
                    ),
                    const Spacer(),
                    if (data != null)
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: loading ? null : _load,
                        icon: loading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.go))
                            : const Icon(Icons.refresh, color: C.muted),
                      ),
                    if (session.started && !session.guest)
                      TextButton(onPressed: session.signOut, child: const Text('Sign out', style: TextStyle(color: C.muted))),
                  ]),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard(String myId) {
    final users = ((data!['users'] as List?) ?? []).cast<Map>();
    final events = ((data!['events'] as List?) ?? []).cast<Map>();
    final reports = ((data!['reports'] as List?) ?? []).cast<Map>();
    final q = query.trim().toLowerCase();
    bool hit(Map m, List<String> keys) => q.isEmpty || keys.any((k) => '${m[k] ?? ''}'.toLowerCase().contains(q));

    Widget stat(int i, String label, int n) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: tab == i ? C.soft : C.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: tab == i ? C.muted : C.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$n', style: displayStyle(34, color: i == 0 && n > 0 ? C.go : C.ink)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: C.muted, fontSize: 13)),
              ]),
            ),
          ),
        );

    final List<Widget> rows = switch (tab) {
      0 => [
          if (reports.isEmpty) const _Empty('No open reports.'),
          for (final r in reports.where((r) => hit(r, ['reportedName', 'reporterName', 'reason'])))
            _Row(
              title: '${_name(r['reportedName'], r['reported'])} was reported',
              subtitle: '“${r['reason']}”\nby ${_name(r['reporterName'], r['reporter'])} · ${_ago(r['at'])}',
              actions: [
                _Action('Delete person', C.danger, () => _delete('users', '${r['reported']}', _name(r['reportedName'], r['reported']))),
                _Action('Dismiss', C.muted, () => _delete('reports', '${r['id']}', 'this report')),
              ],
            ),
        ],
      1 => [
          if (events.isEmpty) const _Empty('No events yet.'),
          for (final e in events.where((e) => hit(e, ['name', 'place'])))
            _Row(
              title: '${e['name']}',
              subtitle: [
                if (e['kind'] == 'place') 'Check-in' else _when(e),
                if ('${e['place'] ?? ''}'.isNotEmpty) '${e['place']}',
              ].where((x) => x.isNotEmpty).join(' · '),
              onTap: () => _showEvent('${e['id']}'),
              actions: [_Action('Delete', C.danger, () => _delete('events', '${e['id']}', '“${e['name']}”'))],
            ),
        ],
      _ => [
          if (users.isEmpty) const _Empty('Nobody yet.'),
          for (final u in users.where((u) => hit(u, ['displayName', 'headline', 'id'])))
            _Row(
              title: _name(u['displayName'], u['id']) + (u['id'] == myId ? ' (you)' : ''),
              subtitle: [
                if ('${u['headline'] ?? ''}'.isNotEmpty) '${u['headline']}',
                u['guest'] == true ? 'Guest' : 'Google',
                'active ${_ago(u['updatedAt'])}',
              ].join(' · '),
              actions: [
                if (u['id'] != myId) _Action('Delete', C.danger, () => _delete('users', '${u['id']}', _name(u['displayName'], u['id']))),
              ],
            ),
        ],
    };

    return RefreshIndicator(
      color: C.go,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Row(children: [
            stat(0, 'Open reports', reports.length),
            const SizedBox(width: 10),
            stat(1, 'Events', events.length),
            const SizedBox(width: 10),
            stat(2, 'People', users.length),
          ]),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, color: C.muted), hintText: 'Search'),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 16),
          SectionLabel(['Reports', 'Events', 'People'][tab]),
          ...rows,
        ],
      ),
    );
  }

  Future<void> _showEvent(String id) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (c) => FractionallySizedBox(
        heightFactor: 0.75,
        child: FutureBuilder(
          future: api.adminEvent(id),
          builder: (c, s) {
            if (s.hasError) return EmptyState(title: "Can't load", text: '${s.error}');
            if (!s.hasData) return const Loading();
            final d = s.data!;
            final e = (d['event'] as Map).cast<String, dynamic>();
            final people = ((d['attendees'] as List?) ?? []).cast<Map>();
            return ListView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
              children: [
                Text('${e['name']}', style: displayStyle(32)),
                const SizedBox(height: 6),
                Text(
                  '${people.length} checked in · ${d['swipes']} swipes · ${d['matches']} matches',
                  style: const TextStyle(color: C.muted),
                ),
                const SizedBox(height: 4),
                SelectableText('id: $id', style: const TextStyle(color: C.muted, fontSize: 12)),
                const SizedBox(height: 18),
                const SectionLabel('Checked in'),
                if (people.isEmpty) const _Empty('Nobody checked in.'),
                for (final p in people)
                  _Row(
                    title: _name(p['displayName'], p['id']),
                    subtitle: [
                      if ('${p['headline'] ?? ''}'.isNotEmpty) '${p['headline']}',
                      if (p['guest'] == true) 'Guest',
                      if (p['visible'] == false) 'Hidden',
                    ].join(' · '),
                    actions: [
                      _Action('Delete person', C.danger, () {
                        Navigator.pop(c);
                        _delete('users', '${p['id']}', _name(p['displayName'], p['id']));
                      }),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _name(Object? name, Object? id) {
    final n = '${name ?? ''}'.trim();
    if (n.isNotEmpty) return n;
    final s = '${id ?? ''}';
    return s.length > 10 ? 'Unknown (${s.substring(s.length - 6)})' : 'Unknown';
  }

  static String _when(Map e) {
    final s = DateTime.tryParse('${e['startsAt'] ?? ''}');
    final end = DateTime.tryParse('${e['endsAt'] ?? ''}');
    final w = eventWhen(s?.toLocal(), end?.toLocal());
    return eventPhase(s, end) == EventPhase.ended ? 'Ended · $w' : w;
  }

  static String _ago(Object? iso) {
    final t = DateTime.tryParse('${iso ?? ''}');
    if (t == null) return '';
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _Action {
  const _Action(this.label, this.color, this.onTap);
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle, this.actions = const [], this.onTap});
  final String title;
  final String subtitle;
  final List<_Action> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: C.muted, fontSize: 14, height: 1.35)),
      ],
    ]);
    final buttons = [
      for (final a in actions) TextButton(onPressed: a.onTap, child: Text(a.label, style: TextStyle(color: a.color))),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
        child: LayoutBuilder(
          // On a phone the buttons go under the text, so the text keeps the width.
          builder: (context, c) => c.maxWidth < 480
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: text), if (onTap != null) const Icon(Icons.chevron_right, color: C.muted)]),
                  if (buttons.isNotEmpty) Transform.translate(offset: const Offset(-12, 0), child: Wrap(children: buttons)),
                ])
              : Row(children: [
                  Expanded(child: text),
                  ...buttons,
                  if (onTap != null) const Icon(Icons.chevron_right, color: C.muted),
                ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(text, style: const TextStyle(color: C.muted)));
}

class _SignIn extends StatelessWidget {
  const _SignIn({required this.onError});
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Admin', style: displayStyle(44)),
              const SizedBox(height: 8),
              const Text('Sign in with the Google account that runs Sidekick.',
                  style: TextStyle(color: C.muted, fontSize: 16, height: 1.4)),
              const SizedBox(height: 24),
              GoogleButton(onResult: (e) {
                if (e != null) onError(e is IdentityError ? e.message : '$e');
              }),
            ]),
          ),
        ),
      );
}

class _NotAdmin extends StatelessWidget {
  const _NotAdmin({required this.id, required this.onSignOut, required this.onRetry});
  final String id;
  final VoidCallback onSignOut;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Not an admin yet', style: displayStyle(38)),
              const SizedBox(height: 10),
              const Text(
                'To make this account an admin, add its id to the GitHub variable ADMIN_IDENTITY_IDS '
                '(Settings → Secrets and variables → Actions → Variables), then re-run the Deploy workflow.',
                style: TextStyle(color: C.muted, fontSize: 15, height: 1.45),
              ),
              const SizedBox(height: 18),
              SurfaceCard(
                child: Row(children: [
                  Expanded(child: SelectableText(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: id));
                      toast(context, 'Copied.');
                    },
                    icon: const Icon(Icons.copy, color: C.muted, size: 20),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('I’ve added it, check again')),
              const SizedBox(height: 8),
              TextButton(onPressed: onSignOut, child: const Text('Use another account', style: TextStyle(color: C.muted))),
            ]),
          ),
        ),
      );
}
