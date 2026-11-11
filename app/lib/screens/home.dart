import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../data/session.dart';
import '../logic/geo_when.dart';
import '../logic/profile.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/art.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/ui.dart';
import 'check_in.dart';
import 'inbox.dart';

/// Events, People, Messages and You, with the + in the middle (add an event, or check in to a
/// place). The place check-in is tab 2 and Alerts is tab 3: the + sheet and the bell open them,
/// so the bar doesn't show them.
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
  void didUpdateWidget(HomeShell old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) _counts();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  /// How many alerts and conversations are unread, for the badges.
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
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return Scaffold(
      // The lists run under the floating bar.
      extendBody: true,
      body: IndexedStack(
        index: tab,
        children: [
          // The tab you're on has just been seen, so it doesn't badge.
          EventsTab(active: tab == 0, alerts: tab == 3 ? 0 : alerts),
          MessagesTab(active: tab == 1),
          const CheckInView(),
          AlertsTab(active: tab == 3),
          const MeTab(),
          ConnectedTab(active: tab == 5),
        ],
      ),
      bottomNavigationBar: HomeTabBar(tab: tab, messages: tab == 1 ? 0 : chats),
    );
  }
}

/// The bottom bar: a floating pill with four tabs and the + in the middle.
class HomeTabBar extends StatelessWidget {
  const HomeTabBar({super.key, required this.tab, required this.messages});
  final int tab;
  final int messages;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, IconData active, String label, String path, {int badge = 0}) {
      final on = tab == i;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => context.go(path),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(clipBehavior: Clip.none, children: [
                Icon(on ? active : icon, color: on ? C.ink : C.muted, size: 24),
                if (badge > 0)
                  Positioned(
                    right: -5,
                    top: -2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: signal,
                        shape: BoxShape.circle,
                        border: Border.all(color: C.paper, width: 2),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: on ? C.ink : C.muted,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: C.brightness == Brightness.light ? C.paper : C.surface,
                borderRadius: BorderRadius.circular(33),
                border: Border.all(color: C.line),
                boxShadow: [BoxShadow(color: C.shadow, blurRadius: 28, offset: const Offset(0, 10))],
              ),
              child: Row(children: [
                item(0, Icons.event_outlined, Icons.event, 'Events', '/'),
                item(5, Icons.people_outline_rounded, Icons.people_rounded, 'People', '/connected'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Tooltip(
                    message: 'Add an event or check in',
                    child: Material(
                      color: C.brand,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _addSheet(context),
                        child: SizedBox(width: 50, height: 50, child: Icon(Icons.add_rounded, size: 28, color: C.onBrand)),
                      ),
                    ),
                  ),
                ),
                item(1, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages', '/messages', badge: messages),
                item(4, Icons.person_outline_rounded, Icons.person_rounded, 'You', '/me'),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

void _addSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetAction(
              icon: Icons.event_outlined,
              title: 'Add an event',
              text: 'Paste its link, or fill it in.',
              onTap: () {
                Navigator.pop(sheet);
                context.push('/new');
              },
            ),
            SheetAction(
              icon: Icons.place_outlined,
              title: 'Check in to a place',
              text: 'Coworking, café or venue. Meet who’s there today.',
              onTap: () {
                Navigator.pop(sheet);
                context.go('/places');
              },
            ),
          ]),
        ),
      ),
    );

class EventsTab extends StatefulWidget {
  const EventsTab({super.key, this.active = true, this.alerts = 0});

  /// Whether this tab is the one on screen. Coming back to it reloads the lists.
  final bool active;
  final int alerts;
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

  @override
  void didUpdateWidget(EventsTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
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

  /// Opens an event, and reloads when the person comes back: they may have checked in or left.
  Future<void> _open(String id) async {
    await context.push('/e/$id');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final now = DateTime.now();
    bool over(DateTime? s, DateTime? e) => eventPhase(s, e, now) == EventPhase.ended;
    bool live(DateTime? s, DateTime? e) => eventPhase(s, e, now) == EventPhase.live;
    final current = mine?.where((e) => !over(e.startsAt, e.endsAt)).toList();
    final ended = mine?.where((e) => over(e.startsAt, e.endsAt)).toList();
    final joined = {...?mine?.map((e) => e.id)};
    final others = open?.where((e) => !joined.contains(e.id)).toList();
    final first = (session.profile?.displayName ?? '').split(' ').first;

    // The poster on top: the room I'm in right now, else something that's on right now.
    final mineNow = current?.where((e) => live(e.startsAt, e.endsAt)).firstOrNull;
    final openNow = mineNow == null ? others?.where((e) => !e.isPlace && live(e.startsAt, e.endsAt)).firstOrNull : null;
    final heroId = mineNow?.id ?? openNow?.id;
    final shown = (past ? ended : current)?.where((e) => e.id != heroId).toList();
    final discover = others?.where((e) => e.id != heroId).toList();
    final loading = mine == null && error == null;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: C.brand,
        backgroundColor: C.surface,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
          children: [
            Row(children: [
              const Expanded(child: Align(alignment: Alignment.centerLeft, child: Wordmark())),
              RoundIconButton(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Alerts',
                badge: widget.alerts > 0,
                onTap: () => context.go('/alerts'),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Your profile',
                child: GestureDetector(
                  onTap: () => context.go('/me'),
                  child: Avatar(name: session.profile?.displayName ?? '', url: session.profile?.photoURL ?? '', size: 42),
                ),
              ),
            ]),
            const SizedBox(height: 30),
            Text(first.isEmpty ? greeting(now) : '${greeting(now)},\n$first', style: displayStyle(44)),
            const SizedBox(height: 12),
            Text(
              mineNow != null
                  ? 'Your sidekick is working the room. Stay in the talk.'
                  : 'Check in when you arrive, and your sidekick works the room while you listen.',
              style: TextStyle(color: C.muted, fontSize: 16.5, height: 1.45),
            ),
            if (session.guest) ...[
              const SizedBox(height: 18),
              Nudge(
                text: 'You’re a guest. You can check in and see your picks.',
                action: 'Sign in',
                onTap: () => askToSignIn(context, reason: 'Sign in to connect with the people you meet.'),
              ),
            ],
            if (error != null) ErrorNote(error),
            const SizedBox(height: 24),
            if (loading)
              const Skeleton(height: 196, radius: 28)
            else if (mineNow != null)
              _EventPoster(
                id: mineNow.id,
                label: 'YOU’RE CHECKED IN',
                name: mineNow.name,
                place: mineNow.kind == 'place' ? 'Checked in today' : mineNow.place,
                action: 'Open the room',
                onTap: () => _open(mineNow.id),
              )
            else if (openNow != null)
              _EventPoster(
                id: openNow.id,
                label: 'HAPPENING NOW',
                name: openNow.name,
                place: openNow.place,
                action: 'I’m here',
                onTap: () => _open(openNow.id),
              ),
            if (loading || heroId != null) const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.place_outlined,
                  title: 'Check in',
                  text: 'To a café or venue',
                  onTap: () => context.go('/places'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickAction(
                  icon: Icons.add_rounded,
                  title: 'Add an event',
                  text: 'Paste its link',
                  onTap: () => context.push('/new'),
                ),
              ),
            ]),
            const SizedBox(height: 34),
            SectionLabel(
              'Your events',
              trailing: Segments<bool>(
                dense: true,
                items: const [(false, 'Upcoming'), (true, 'Past')],
                value: past,
                onChanged: (v) => setState(() => past = v),
              ),
            ),
            if (loading)
              const SkeletonRows(count: 2, round: false)
            else if ((shown ?? []).isEmpty)
              _Hint(
                past
                    ? 'Events you went to show up here.'
                    : heroId != null && mineNow != null
                        ? 'Nothing else coming up.'
                        : 'Events you check in to show up here.',
              )
            else
              for (final e in shown!)
                _EventRow(
                  name: e.name,
                  place: e.place,
                  start: e.startsAt,
                  end: e.endsAt,
                  isPlace: e.kind == 'place',
                  onTap: () => _open(e.id),
                ),
            const SizedBox(height: 30),
            const SectionLabel('Discover'),
            if (loading)
              const SkeletonRows(count: 3, round: false)
            else if ((discover ?? []).isEmpty)
              const _Hint('Nothing else on right now. Know of an event? Add it with +.')
            else
              for (final e in discover!)
                _EventRow(
                  name: e.name,
                  place: e.place,
                  start: e.startsAt,
                  end: e.endsAt,
                  isPlace: e.isPlace,
                  onTap: () => _open(e.id),
                ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: TextStyle(color: C.muted, fontSize: 15, height: 1.4)),
      );
}

/// The event that's on right now, as a poster: lit colour, its name, and one thing to do.
class _EventPoster extends StatelessWidget {
  const _EventPoster({
    required this.id,
    required this.label,
    required this.name,
    required this.place,
    required this.action,
    required this.onTap,
  });
  final String id;
  final String label;
  final String name;
  final String place;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 196,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Poster.bg, borderRadius: BorderRadius.circular(28)),
            child: SizedBox(
              child: Stack(fit: StackFit.expand, children: [
                PosterArt(id),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x59000000)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const LiveDot(size: 7),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Poster.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ]),
                    const Spacer(),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: displayStyle(32, color: Poster.ink),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Poster.muted, fontSize: 14.5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                        decoration: BoxDecoration(color: Poster.ink, borderRadius: BorderRadius.circular(99)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            action,
                            style: const TextStyle(color: Poster.bg, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, size: 16, color: Poster.bg),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.title, required this.text, required this.onTap});
  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: C.second, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: C.onSecond),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13.5)),
        ]),
      );
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.name, required this.place, this.start, this.end, this.isPlace = false, required this.onTap});
  final String name;
  final String place;
  final DateTime? start;
  final DateTime? end;
  final bool isPlace;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = eventPhase(start, end) == EventPhase.live;
    final sub = [
      if (isPlace) 'Check-in' else place,
      if (!isPlace) live ? 'On now' : eventWhen(start, end),
    ].where((x) => x.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        onTap: onTap,
        child: Row(children: [
          DateTile(date: start, icon: isPlace ? Icons.place_outlined : null, live: live && !isPlace),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 14)),
              ],
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: C.muted),
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
    final nudge = p == null ? null : profileNudge(p);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
        children: [
          const SizedBox(height: 4),
          const Align(alignment: Alignment.centerLeft, child: Wordmark()),
          const SizedBox(height: 30),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Avatar(name: p?.displayName ?? '', url: p?.photoURL ?? '', size: 84),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.displayName ?? '', style: displayStyle(34)),
                if ((p?.headline ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(p!.headline, style: TextStyle(color: C.muted, fontSize: 15, height: 1.3)),
                ],
              ]),
            ),
          ]),
          if ((p?.about ?? '').isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(p!.about, style: const TextStyle(fontSize: 15.5, height: 1.5)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => context.push('/profile'), child: const Text('Edit profile'))),
            if (session.guest) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => askToSignIn(
                    context,
                    reason: 'Keep your profile and check-ins, and connect with people. Guests can’t swipe.',
                  ),
                  child: const Text('Sign in'),
                ),
              ),
            ],
          ]),
          if (nudge != null) ...[
            const SizedBox(height: 14),
            Nudge(text: nudge, action: 'Add', onTap: () => context.push('/profile')),
          ],
          if (p != null && (p.lookingFor.isNotEmpty || p.offering.isNotEmpty)) ...[
            const SizedBox(height: 30),
            const SectionLabel('What your sidekick tells the room'),
            SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (p.lookingFor.isNotEmpty) ...[
                  Text('Looking for', style: TextStyle(color: C.muted, fontSize: 13.5)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final t in p.lookingFor) _PaperTag(t)]),
                ],
                if (p.lookingFor.isNotEmpty && p.offering.isNotEmpty) const SizedBox(height: 18),
                if (p.offering.isNotEmpty) ...[
                  Text('Can offer', style: TextStyle(color: C.muted, fontSize: 13.5)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final t in p.offering) _PaperTag(t)]),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 30),
          const SectionLabel('Appearance'),
          Segments<ThemeChoice>(
            items: const [(ThemeChoice.system, 'System'), (ThemeChoice.light, 'Light'), (ThemeChoice.dark, 'Dark')],
            value: session.theme,
            onChanged: session.setTheme,
          ),
          const SizedBox(height: 30),
          const SectionLabel('Account'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _SettingRow(
                icon: session.guest ? Icons.person_outline_rounded : Icons.verified_user_outlined,
                title: session.guest ? 'Guest' : 'Signed in with Google',
                text: session.guest
                    ? 'You can check in and see your picks.'
                    : (session.googleEmail.isEmpty ? 'You can connect and message.' : session.googleEmail),
              ),
              Divider(indent: 62, color: C.line),
              _SettingRow(
                icon: Icons.logout_rounded,
                title: session.guest ? 'Leave guest mode' : 'Sign out',
                onTap: () async {
                  if (session.guest &&
                      !await confirmSheet(
                        context,
                        title: 'Leave guest mode?',
                        text: 'A guest profile can’t be recovered. Your profile and check-ins will be lost.',
                        action: 'Leave guest mode',
                      )) {
                    return;
                  }
                  await session.signOut();
                },
              ),
              Divider(indent: 62, color: C.line),
              _SettingRow(
                icon: Icons.delete_outline_rounded,
                title: 'Delete my account',
                danger: true,
                onTap: () async {
                  if (!await confirmSheet(
                    context,
                    title: 'Delete your account?',
                    text: 'Your profile and check-ins are deleted, and you leave every event. This can’t be undone.',
                    action: 'Delete my account',
                  )) {
                    return;
                  }
                  try {
                    await session.deleteAccount();
                  } catch (e) {
                    if (context.mounted) toast(context, '$e');
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 22),
          Text(
            'Both sides opt in. Contacts stay hidden until you match.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// A tag on a grey card: white, so it still reads as a chip.
class _PaperTag extends StatelessWidget {
  const _PaperTag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: C.paper, borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: const TextStyle(fontSize: 13.5, height: 1.1)),
      );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.icon, required this.title, this.text, this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String? text;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? C.danger : C.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
        child: Row(children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: color)),
              if (text != null) ...[
                const SizedBox(height: 2),
                Text(text!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 13.5)),
              ],
            ]),
          ),
          if (onTap != null && !danger) Icon(Icons.chevron_right_rounded, color: C.muted),
        ]),
      ),
    );
  }
}
