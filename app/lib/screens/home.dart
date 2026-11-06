import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../logic/geo_when.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/sidekick_status.dart';
import '../widgets/ui.dart';
import 'check_in.dart';

/// The three tabs: events, check in to a place, and you.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.tab});
  final int tab;

  static const _paths = ['/', '/places', '/me'];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: const [EventsTab(), CheckInView(), MeTab()]),
        floatingActionButton: tab == 0
            ? FloatingActionButton(
                onPressed: () => context.push('/new'),
                backgroundColor: C.ink,
                foregroundColor: C.onInk,
                shape: const CircleBorder(),
                child: const Icon(Icons.add_rounded, size: 30),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => context.go(_paths[i]),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Events'),
            NavigationDestination(
                icon: Icon(Icons.my_location_outlined), selectedIcon: Icon(Icons.my_location), label: 'Check in'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'You'),
          ],
        ),
      );
}

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
              const Expanded(child: Text('SIDEKICK', style: eyebrow)),
              GestureDetector(
                onTap: () => context.go('/me'),
                child: Avatar(name: session.profile?.displayName ?? '', url: session.profile?.photoURL ?? '', size: 34),
              ),
            ]),
            const SizedBox(height: 18),
            Text(first.isEmpty ? 'Hello' : 'Hi $first', style: displayStyle(46)),
            const SizedBox(height: 8),
            const Text('Going to an event? Tap + to add it, or open its link.',
                style: TextStyle(color: C.muted, fontSize: 16)),
            if (session.guest) ...[
              const SizedBox(height: 18),
              _GuestBanner(onSignIn: () => askToSignIn(context, reason: 'Sign in to connect with people you meet.')),
            ],
            const SizedBox(height: 18),
            SurfaceCard(
              onTap: () => context.go('/places'),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: C.go.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: const Icon(Icons.my_location, color: C.go, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Check in to a place', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                    SizedBox(height: 2),
                    Text("Coworking, café or venue. Meet who's there today.", style: TextStyle(color: C.muted, fontSize: 14)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: C.muted),
              ]),
            ),
            if (error != null) ErrorNote(error),
            const SizedBox(height: 30),
            Row(children: [
              Expanded(child: Text('Your events', style: displayStyle(28))),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: C.soft,
                  selectedForegroundColor: C.ink,
                  foregroundColor: C.muted,
                  side: const BorderSide(color: C.line),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('Upcoming')),
                  ButtonSegment(value: true, label: Text('Past')),
                ],
                selected: {past},
                onSelectionChanged: (v) => setState(() => past = v.first),
              ),
            ]),
            const SizedBox(height: 12),
            if (shown == null && error == null)
              const Padding(padding: EdgeInsets.all(24), child: Loading())
            else if ((shown ?? []).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(past ? 'Events you went to show up here.' : "Events you join show up here.",
                    style: const TextStyle(color: C.muted)),
              )
            else
              for (final e in shown!) _EventRow(id: e.id, name: e.name, place: e.place, start: e.startsAt, end: e.endsAt, place2: e.kind == 'place'),
            const SizedBox(height: 30),
            Text('All events', style: displayStyle(28)),
            const SizedBox(height: 12),
            if (others == null && error == null)
              const Padding(padding: EdgeInsets.all(24), child: Loading())
            else if ((others ?? []).isEmpty)
              const Padding(
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
    final phase = eventPhase(start, end);
    final when = place2 ? 'Check-ins today' : eventWhen(start, end);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        onTap: () => context.push('/e/$id'),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (phase == EventPhase.live && !place2) ...[
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: C.go, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('LIVE', style: eyebrow),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(when.isEmpty ? 'No date' : when,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 6),
              Text(name, style: displayStyle(24)),
              if (place.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 14)),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right, color: C.muted),
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
          const Text('YOU', style: eyebrow),
          const SizedBox(height: 18),
          Row(children: [
            Avatar(name: p?.displayName ?? '', url: p?.photoURL ?? '', size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.displayName ?? '', style: displayStyle(32)),
                if ((p?.headline ?? '').isNotEmpty)
                  Text(p!.headline, style: const TextStyle(color: C.muted, fontSize: 15)),
                const SizedBox(height: 6),
                Tag(session.guest ? 'Guest' : 'Signed in with Google', highlight: !session.guest),
              ]),
            ),
          ]),
          const SizedBox(height: 22),
          if (p != null) ...[
            if (p.lookingFor.isNotEmpty) ...[
              const Text('Looking for', style: TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final t in p.lookingFor) Tag(t)]),
              const SizedBox(height: 16),
            ],
            if (p.offering.isNotEmpty) ...[
              const Text('Can offer', style: TextStyle(color: C.muted, fontSize: 13)),
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
          const SidekickStatusCard(),
          const SizedBox(height: 20),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: C.muted),
            title: Text(session.guest ? 'Leave guest mode' : 'Sign out'),
            subtitle: session.guest
                ? const Text('Guest profiles can’t be recovered after you leave.', style: TextStyle(color: C.muted))
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
            leading: const Icon(Icons.delete_outline, color: C.danger),
            title: const Text('Delete my account', style: TextStyle(color: C.danger)),
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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel', style: TextStyle(color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes', style: TextStyle(color: C.danger))),
        ],
      ),
    ) ==
    true;
