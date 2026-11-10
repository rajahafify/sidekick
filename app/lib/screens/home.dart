import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../data/session.dart';
import '../logic/geo_when.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/sidekick_status.dart';
import '../widgets/ui.dart';
import 'check_in.dart';
import 'inbox.dart';

/// Events, Connected, Messages, Alerts and You, with the raised + in the middle (add an event, or check in to
/// a place). The place check-in is tab 2; the + sheet opens it, so the bar doesn't show it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.tab});
  final int tab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  Session? session;
  Timer? timer;
  int alerts = 0;
  int chats = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (session != null) return;
    session = SessionScope.of(context);
    _counts();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _counts());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  /// How many alerts and conversations are unread, for the badges on the tabs.
  Future<void> _counts() async {
    final s = session;
    if (s == null || s.guest) return;
    try {
      final a = await s.api.alerts();
      final c = await s.api.chats();
      if (mounted) {
        setState(() {
          alerts = a.unread;
          chats = c.unread;
        });
      }
    } catch (_) {
      // A badge that's a little behind catches up on the next check.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: widget.tab,
          children: const [EventsTab(), MessagesTab(), CheckInView(), AlertsTab(), MeTab(), ConnectedTab()],
        ),
        bottomNavigationBar: _TabBar(
          tab: widget.tab,
          // The tab you're on has just been seen, so it doesn't badge.
          messages: widget.tab == 1 ? 0 : chats,
          alerts: widget.tab == 3 ? 0 : alerts,
        ),
      );
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.tab, required this.messages, required this.alerts});
  final int tab;
  final int messages;
  final int alerts;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, IconData active, String label, String path, {int badge = 0}) {
      final on = tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => context.go(path),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(on ? active : icon, color: on ? C.go : C.muted, size: 24),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: C.go,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.paper, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            // Five tabs share a narrow phone bar, so a long label shrinks rather than wrapping.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: TextStyle(fontSize: 12, color: on ? C.go : C.muted, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: C.paper, border: Border(top: BorderSide(color: C.line))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Row(children: [
              item(0, Icons.calendar_today_outlined, Icons.calendar_today, 'Events', '/'),
              item(5, Icons.people_outline, Icons.people, 'Connected', '/connected'),
              item(1, Icons.chat_bubble_outline, Icons.chat_bubble, 'Messages', '/messages', badge: messages),
              const SizedBox(width: 72),
              item(3, Icons.notifications_none, Icons.notifications, 'Alerts', '/alerts', badge: alerts),
              item(4, Icons.person_outline, Icons.person, 'You', '/me'),
            ]),
            Positioned(
              top: -22,
              child: Material(
                color: C.go,
                shape: const CircleBorder(),
                elevation: 6,
                shadowColor: C.go.withValues(alpha: 0.5),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _addSheet(context),
                  child: SizedBox(width: 60, height: 60, child: Icon(Icons.add_rounded, size: 32, color: C.onInk)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

void _addSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (sheet) {
        Widget row(IconData icon, String title, String text, String path) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
              leading: Icon(icon, color: C.go),
              title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
              subtitle: Text(text, style: TextStyle(color: C.muted)),
              onTap: () {
                Navigator.pop(sheet);
                path == '/places' ? context.go(path) : context.push(path);
              },
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              row(Icons.event_outlined, 'Add an event', 'Paste its link, or fill it in.', '/new'),
              row(Icons.my_location, 'Check in to a place', 'Coworking, café or venue. Meet who’s there today.', '/places'),
            ]),
          ),
        );
      },
    );

class EventsTab extends StatefulWidget {
  const EventsTab({super.key});
  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  List<MyEvent>? mine;
  List<EventDoc>? open;
  String? error;
  bool past = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mine == null && error == null) _load();
  }

  Future<void> _load() async {
    try {
      final r = await SessionScope.of(context).api.events();
      if (mounted) {
        setState(() {
          mine = r.mine;
          open = r.open;
          error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final now = DateTime.now();
    bool over(DateTime? s, DateTime? e) => eventPhase(s, e, now) == EventPhase.ended;
    final current = mine?.where((e) => !over(e.startsAt, e.endsAt)).toList();
    final ended = mine?.where((e) => over(e.startsAt, e.endsAt)).toList();
    final shown = past ? ended : current;
    final joined = {...?mine?.map((e) => e.id)};
    final others = open?.where((e) => !joined.contains(e.id)).toList();
    final first = (session.profile?.displayName ?? '').split(' ').first;

    return SafeArea(
      child: RefreshIndicator(
        color: C.go,
        backgroundColor: C.surface,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Row(children: [
              const Expanded(child: Align(alignment: Alignment.centerLeft, child: Wordmark())),
              GestureDetector(
                onTap: () => context.go('/me'),
                child: Avatar(name: session.profile?.displayName ?? '', url: session.profile?.photoURL ?? '', size: 38),
              ),
            ]),
            const SizedBox(height: 30),
            Text(first.isEmpty ? 'Hello' : 'Hi $first', style: displayStyle(44)),
            const SizedBox(height: 10),
            Text('Going to an event? Tap + to add it, or scan the QR code at the door.',
                style: TextStyle(color: C.muted, fontSize: 17, height: 1.45)),
            if (session.guest) ...[
              const SizedBox(height: 18),
              _GuestBanner(onSignIn: () => askToSignIn(context, reason: 'Sign in to connect with people you meet.')),
            ],
            const SizedBox(height: 24),
            SurfaceCard(
              onTap: () => context.go('/places'),
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: C.go.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.my_location, color: C.go, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Check in to a place', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                    SizedBox(height: 2),
                    Text("Coworking, café or venue. Meet who's there today.",
                        style: TextStyle(color: C.muted, fontSize: 14, height: 1.35)),
                  ]),
                ),
                Icon(Icons.chevron_right, color: C.muted),
              ]),
            ),
            if (error != null) ErrorNote(error),
            const SizedBox(height: 32),
            SectionLabel(
              'Your events',
              trailing: GestureDetector(
                onTap: () => setState(() => past = !past),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Upcoming', style: TextStyle(color: past ? C.muted : C.ink)),
                  TextSpan(text: '  ·  ', style: TextStyle(color: C.muted)),
                  TextSpan(text: 'Past', style: TextStyle(color: past ? C.ink : C.muted)),
                ]), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            ),
            if (shown == null && error == null)
              const Padding(padding: EdgeInsets.all(24), child: Loading())
            else if ((shown ?? []).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(past ? 'Events you went to show up here.' : "Events you join show up here.",
                    style: TextStyle(color: C.muted)),
              )
            else
              for (final e in shown!) _EventRow(id: e.id, name: e.name, place: e.place, start: e.startsAt, end: e.endsAt, place2: e.kind == 'place'),
            const SizedBox(height: 28),
            const SectionLabel('All events'),
            if (others == null && error == null)
              const Padding(padding: EdgeInsets.all(24), child: Loading())
            else if ((others ?? []).isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing on right now. Add one with +.', style: TextStyle(color: C.muted)),
              )
            else
              for (final e in others!) _EventRow(id: e.id, name: e.name, place: e.place, start: e.startsAt, end: e.endsAt, place2: e.isPlace),
          ],
        ),
      ),
    );
  }
}

class _GuestBanner extends StatelessWidget {
  const _GuestBanner({required this.onSignIn});
  final VoidCallback onSignIn;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          color: C.goSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: C.go.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Expanded(
            child: Text("You're browsing as a guest. You can check in and see your picks. Sign in to connect.",
                style: TextStyle(fontSize: 14, height: 1.35)),
          ),
          TextButton(onPressed: onSignIn, child: const Text('Sign in')),
        ]),
      );
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.id, required this.name, required this.place, this.start, this.end, this.place2 = false});
  final String id;
  final String name;
  final String place;
  final DateTime? start;
  final DateTime? end;
  final bool place2;

  @override
  Widget build(BuildContext context) {
    final live = !place2 && eventPhase(start, end) == EventPhase.live;
    final sub = [if (place2) 'Check-in' else place, if (!place2 && !live) eventWhen(start, end)]
        .where((x) => x.isNotEmpty)
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        onTap: () => context.push('/e/$id'),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (place2) ...[
                  Icon(Icons.my_location, color: C.go, size: 14),
                  const SizedBox(width: 7),
                ] else if (live) ...[
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: C.go, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                ),
              ]),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 14)),
              ],
            ]),
          ),
          Icon(Icons.chevron_right, color: C.muted),
        ]),
      ),
    );
  }
}

class MeTab extends StatelessWidget {
  const MeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final p = session.profile;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          const Align(alignment: Alignment.centerLeft, child: Wordmark()),
          const SizedBox(height: 28),
          Row(children: [
            Avatar(name: p?.displayName ?? '', url: p?.photoURL ?? '', size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.displayName ?? '', style: displayStyle(32)),
                if ((p?.headline ?? '').isNotEmpty)
                  Text(p!.headline, style: TextStyle(color: C.muted, fontSize: 15)),
                const SizedBox(height: 6),
                Tag(session.guest ? 'Guest' : 'Signed in with Google', highlight: !session.guest),
              ]),
            ),
          ]),
          const SizedBox(height: 22),
          if (p != null) ...[
            if (p.lookingFor.isNotEmpty) ...[
              Text('Looking for', style: TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final t in p.lookingFor) Tag(t)]),
              const SizedBox(height: 16),
            ],
            if (p.offering.isNotEmpty) ...[
              Text('Can offer', style: TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final t in p.offering) Tag(t)]),
              const SizedBox(height: 16),
            ],
          ],
          OutlinedButton(onPressed: () => context.push('/profile'), child: const Text('Edit profile')),
          const SizedBox(height: 12),
          if (session.guest)
            FilledButton(
              onPressed: () => askToSignIn(context,
                  reason: 'Keep your profile and check-ins, and connect with people. Guests can’t swipe.'),
              child: const Text('Sign in with Google'),
            ),
          const SizedBox(height: 24),
          const SectionLabel('Appearance'),
          SegmentedButton<ThemeChoice>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeChoice.system, label: Text('System')),
              ButtonSegment(value: ThemeChoice.light, label: Text('Light')),
              ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
            ],
            selected: {session.theme},
            onSelectionChanged: (choice) => session.setTheme(choice.first),
          ),
          const SizedBox(height: 28),
          const SidekickStatusCard(),
          const SizedBox(height: 20),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: C.muted),
            title: Text(session.guest ? 'Leave guest mode' : 'Sign out'),
            subtitle: session.guest
                ? Text('Guest profiles can’t be recovered after you leave.', style: TextStyle(color: C.muted))
                : null,
            onTap: () async {
              if (session.guest && !await _confirm(context, 'Leave guest mode?', 'Your guest profile and check-ins will be lost.')) {
                return;
              }
              await session.signOut();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: C.danger),
            title: Text('Delete my account', style: TextStyle(color: C.danger)),
            onTap: () async {
              if (!await _confirm(context, 'Delete your account?',
                  'Your profile and check-ins are deleted, and you leave every event. This can’t be undone.')) {
                return;
              }
              try {
                await session.deleteAccount();
              } catch (e) {
                if (context.mounted) toast(context, '$e');
              }
            },
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancel', style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text('Yes', style: TextStyle(color: C.danger))),
        ],
      ),
    ) ==
    true;
