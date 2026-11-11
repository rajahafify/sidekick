import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api.dart';
import '../logic/geo_when.dart';
import '../logic/sidekick.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/art.dart';
import '../widgets/mark.dart';
import '../widgets/match_moment.dart';
import '../widgets/room_share.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/ui.dart';

class EventScreen extends StatefulWidget {
  const EventScreen({super.key, required this.id, this.autoJoin = false, this.share = false});
  final String id;
  final bool autoJoin;
  final bool share;
  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  Room? room;
  String? loadError;
  bool notFound = false;
  Scout? scout;
  String _scoutedKey = '';
  bool scouting = false;
  bool busy = false;
  String? error;
  int tab = 0;
  bool showPassed = false;
  Timer? _poll;
  final Map<String, bool> _optimistic = {};

  /// The last person passed on, who Undo brings back, and the people Undo has brought back.
  String? _lastPassed;
  final Set<String> _restored = {};

  /// Matches already celebrated on this visit, so each gets its moment once.
  final Set<String> _celebrated = {};

  Api get api => SessionScope.of(context).api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (!mounted) return;
      if (widget.share && room != null) _shareSheet();
      if (widget.autoJoin && room != null && !room!.checkedIn) _join();
    });
    // Keep the room fresh: new people, and matches made on the other side.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && room?.checkedIn == true) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final r = await api.room(widget.id);
      if (!mounted) return;
      final before = room;
      setState(() {
        room = r;
        loadError = null;
      });
      if (before == null) {
        // Matches made before this visit were celebrated then, or are in Alerts.
        _celebrated.addAll(r.matches);
      } else if (quiet) {
        final fresh = r.matches.where((m) => !_celebrated.contains(m)).firstOrNull;
        if (fresh != null) _celebrate(fresh);
      }
      _maybeScout();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.status == 404) notFound = true;
        if (!quiet) loadError = e.message;
      });
    }
  }

  /// Ask the sidekick to scout whenever the room or my card changes.
  void _maybeScout() {
    final r = room;
    if (r == null || !r.checkedIn || r.people.isEmpty) return;
    final key = [r.me!.key, ...r.people.map((p) => p.key)].join('|');
    if (key == _scoutedKey) return;
    _scoutedKey = key;
    setState(() => scouting = true);
    api
        .scout(widget.id)
        .then((s) {
          if (mounted) setState(() => scout = s);
        })
        .catchError((_) {})
        .whenComplete(() {
          if (mounted) setState(() => scouting = false);
        });
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _join() => _run(() async {
    await api.join(widget.id);
    haptic();
    await _load();
  });

  Future<void> _setVisible(bool v) => _run(() async {
    await api.setVisible(widget.id, v);
    await _load();
  });

  /// Guests can look but not swipe: ask them to sign in first. True when they may swipe.
  Future<bool> _canSwipe(Attendee p, bool like) async {
    if (!SessionScope.of(context).guest) return true;
    final ok = await askToSignIn(
      context,
      reason: like
          ? 'Sign in to connect with ${firstName(p.displayName)}. Your profile and check-ins stay as they are.'
          : 'Sign in to start swiping. Your profile and check-ins stay as they are.',
    );
    if (ok) await _load(quiet: true);
    return ok && mounted;
  }

  Future<void> _swipe(Attendee p, bool like) async {
    haptic();
    setState(() {
      _optimistic[p.uid] = like;
      _restored.remove(p.uid);
      _lastPassed = like ? null : p.uid;
    });
    try {
      final matched = await api.swipe(widget.id, p.uid, like);
      if (matched && mounted) _celebrate(p.uid, person: p);
      await _load(quiet: true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _optimistic.remove(p.uid);
        if (_lastPassed == p.uid) _lastPassed = null;
      });
      if (e.needsLogin) {
        await askToSignIn(context);
      } else {
        toast(context, e.message);
      }
    }
  }

  /// Brings back the person just passed on, to look again.
  void _undo() {
    final uid = _lastPassed;
    if (uid == null) return;
    haptic();
    setState(() {
      _restored.add(uid);
      _lastPassed = null;
    });
  }

  Future<void> _celebrate(String uid, {Attendee? person}) async {
    if (!_celebrated.add(uid)) return;
    final p = person ?? room?.people.where((x) => x.uid == uid).firstOrNull;
    final mine = room?.me;
    if (p == null || mine == null) return;
    final see = await showMatchMoment(
      context,
      me: (name: mine.displayName, url: mine.photoURL, seed: mine.uid),
      them: (name: p.displayName, url: p.photoURL, seed: p.uid),
      firstName: firstName(p.displayName),
    );
    if (see && mounted) context.push('/e/${widget.id}/m/${Uri.encodeComponent(uid)}');
  }

  void _shareSheet() {
    showRoomShare(context, link: Config.eventLink(widget.id), eventName: room?.event.name);
  }

  Future<void> _menu() async {
    final r = room!;
    final visible = r.me?.visible ?? true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetAction(
                icon: Icons.qr_code_rounded,
                title: 'Bring people in',
                text: 'Share the link, or put the code on screen.',
                onTap: () => Navigator.pop(c, 'share'),
              ),
              SheetAction(
                icon: visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                title: visible ? 'Hide me from new people' : 'Show me in the room again',
                text: visible ? 'Sidekicks stop suggesting you. Your matches stay.' : 'Sidekicks can suggest you again.',
                onTap: () => Navigator.pop(c, 'visible'),
              ),
              SheetAction(
                icon: Icons.logout_rounded,
                title: r.event.isPlace ? 'Check out' : 'Leave this event',
                danger: true,
                onTap: () => Navigator.pop(c, 'leave'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'share') {
      _shareSheet();
    } else if (choice == 'visible') {
      await _setVisible(!visible);
    } else if (choice == 'leave') {
      final sure = await confirmSheet(
        context,
        title: r.event.isPlace ? 'Check out of here?' : 'Leave this event?',
        text: 'You come out of the room and your sidekick stops scouting here. You can check in again later.',
        action: r.event.isPlace ? 'Check out' : 'Leave event',
      );
      if (!sure || !mounted) return;
      await _run(() async {
        await api.leave(widget.id);
        await _load();
      });
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/');

  @override
  Widget build(BuildContext context) {
    if (notFound) {
      return Scaffold(
        appBar: BackBar(onBack: _back),
        body: Center(
          child: EmptyState(
            mood: BuddyMood.normal,
            title: 'Event not found',
            text: 'Check the link, or ask whoever shared it for a new one.',
            action: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(160, 50)),
              onPressed: () => context.go('/'),
              child: const Text('Go home'),
            ),
          ),
        ),
      );
    }
    final r = room;
    if (r == null) {
      return Scaffold(
        appBar: BackBar(onBack: _back),
        body: loadError == null
            ? const _RoomSkeleton()
            : Center(
                child: EmptyState(
                  mood: BuddyMood.normal,
                  title: 'Can’t load this',
                  text: loadError!,
                  action: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 50)),
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ),
              ),
      );
    }
    final e = r.event;
    final phase = eventPhase(e.startsAt, e.endsAt);
    final live = !e.isPlace && phase == EventPhase.live;
    final when = e.isPlace
        ? 'CHECK-INS · ${e.startsAt == null ? 'TODAY' : eventWhen(e.startsAt, null).split(',').take(2).join(',').toUpperCase()}'
        : [
            eventWhen(e.startsAt, e.endsAt).toUpperCase(),
            if (phase == EventPhase.ended) 'ENDED',
          ].where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      appBar: BackBar(
        onBack: _back,
        actions: [
          RoundIconButton(icon: Icons.ios_share_rounded, tooltip: 'Share this event', onTap: _shareSheet),
          if (r.checkedIn) RoundIconButton(icon: Icons.more_horiz_rounded, tooltip: 'More', onTap: _menu),
        ],
      ),
      body: RefreshIndicator(
        color: C.brand,
        backgroundColor: C.surface,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
          children: [
            if (live)
              Row(children: [
                const LiveDot(size: 7),
                const SizedBox(width: 4),
                Text('HAPPENING NOW', style: eyebrow.copyWith(letterSpacing: 2)),
              ])
            else if (when.isNotEmpty)
              Text(when, style: caps.copyWith(letterSpacing: 1.8)),
            const SizedBox(height: 10),
            Text(e.name, style: displayStyle(40)),
            const SizedBox(height: 10),
            if (e.place.isNotEmpty)
              Semantics(
                link: true,
                child: GestureDetector(
                  onTap: () => launchUrl(
                    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': e.place}),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${e.place} '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(Icons.north_east_rounded, size: 15, color: C.muted),
                      ),
                    ]),
                    style: TextStyle(color: C.muted, fontSize: 15.5, height: 1.35),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            _Headcount(room: r),
            const SizedBox(height: 22),
            if (!r.checkedIn) _joinSection(r, phase) else ..._roomSection(r),
            ErrorNote(error),
          ],
        ),
      ),
    );
  }

  Widget _joinSection(Room r, EventPhase phase) {
    final ended = phase == EventPhase.ended;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: ColoredBox(
        color: Poster.bg,
        child: Stack(children: [
          Positioned.fill(child: PosterArt(widget.id)),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x66000000)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 96, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ended ? 'This one’s over' : 'Send your sidekick in', style: displayStyle(34, color: Poster.ink)),
                const SizedBox(height: 10),
                Text(
                  ended
                      ? 'The event has ended, so the room is closed.'
                      : 'Check in and your sidekick reads everyone here, then shows you who’s worth meeting. '
                          'Nobody sees who you pass on.',
                  style: const TextStyle(color: Poster.muted, fontSize: 15.5, height: 1.45),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Poster.ink,
                    foregroundColor: Poster.bg,
                    disabledBackgroundColor: Poster.glass,
                    disabledForegroundColor: Poster.muted,
                  ),
                  onPressed: busy || ended ? null : _join,
                  child: busy
                      ? const ButtonProgress(color: Poster.bg)
                      : Text(ended ? 'Ended' : (r.event.isPlace ? 'Check in here' : 'I’m at this event')),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _roomSection(Room r) {
    final me = r.me!;
    final swipes = {...r.swipes, ..._optimistic};
    final matched = r.matches.toSet();
    final known = {for (final p in r.connected) p.uid};
    // Someone I matched with in this room is under Matches, not under "connected before".
    final alreadyHere = r.connected.where((p) => !matched.contains(p.uid)).toList();
    final picks = {for (final p in scout?.picks ?? const <ScoutPick>[]) p.uid: p};
    final byId = {for (final p in r.people) p.uid: p};
    bool back(String uid) => _restored.contains(uid);
    final candidates = r.people.where((p) => !matched.contains(p.uid) && !known.contains(p.uid)).toList();
    final deck =
        candidates
            .where((p) => !swipes.containsKey(p.uid) || back(p.uid) || (showPassed && swipes[p.uid] == false))
            .map((p) => (person: p, pick: picks[p.uid] ?? templatePick(me, p)))
            .toList()
          ..sort((a, b) {
            // Someone just brought back with Undo comes first; then the best fit.
            final ua = back(a.person.uid) ? 1 : 0, ub = back(b.person.uid) ? 1 : 0;
            return ua != ub ? ub - ua : b.pick.score.compareTo(a.pick.score);
          });
    final passed = candidates.where((p) => swipes[p.uid] == false && !back(p.uid)).length;
    final waiting = candidates.where((p) => swipes[p.uid] == true).length;
    final myMatches = r.matches.map((u) => byId[u]).whereType<Attendee>().toList();
    final strong = deck.where((d) => d.pick.score >= 70).length;
    final canUndo = _lastPassed != null && byId.containsKey(_lastPassed);

    return [
      if (!me.visible) ...[
        Nudge(
          text: 'You’re hidden from new people. Your matches stay.',
          action: 'Show me',
          onTap: () {
            if (!busy) _setVisible(true);
          },
        ),
        const SizedBox(height: 14),
      ],
      Segments<int>(
        items: [
          (0, deck.isEmpty ? 'For you' : 'For you · ${deck.length}'),
          (1, myMatches.isEmpty ? 'Matches' : 'Matches · ${myMatches.length}'),
        ],
        value: tab,
        onChanged: (v) => setState(() => tab = v),
      ),
      const SizedBox(height: 18),
      if (tab == 0) ...[
        if (r.people.isEmpty)
          EmptyState(
            mood: BuddyMood.normal,
            title: 'Your sidekick is waiting',
            text: 'Nobody else is checked in yet. Bring people in, and they show up here.',
            action: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
              onPressed: _shareSheet,
              icon: const Icon(Icons.qr_code_rounded, size: 19),
              label: const Text('Bring people in'),
            ),
          )
        else if (deck.isEmpty)
          EmptyState(
            mood: BuddyMood.wink,
            title: 'You’ve seen everyone',
            text: waiting > 0
                ? 'You asked to connect with $waiting ${waiting == 1 ? 'person' : 'people'}. '
                    'If they connect back, it’s a match. New people show up here as they check in.'
                : 'New people show up here as they check in.',
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 2),
            child: Row(children: [
              const SidekickMark(size: 13, mood: BuddyMood.wink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.guest
                      ? 'You’re a guest: look through your picks, then sign in to connect.'
                      : roomBriefing(scouted: deck.length, strong: strong, scouting: scouting),
                  style: TextStyle(color: C.muted, fontSize: 14, height: 1.3),
                ),
              ),
            ]),
          ),
          _Deck(
            key: ValueKey(deck.first.person.uid),
            person: deck.first.person,
            pick: deck.first.pick,
            next: deck.length > 1 ? deck[1].person : null,
            me: me,
            scouting: scouting,
            onUndo: canUndo ? _undo : null,
            canSwipe: (like) => _canSwipe(deck.first.person, like),
            onSwipe: (like) => _swipe(deck.first.person, like),
          ),
        ],
        if (deck.isEmpty && canUndo)
          Center(
            child: TextButton.icon(
              onPressed: _undo,
              icon: Icon(Icons.undo_rounded, size: 18, color: C.ink),
              label: const Text('Undo the last pass'),
            ),
          ),
        if (passed > 0 || showPassed)
          Center(
            child: TextButton(
              onPressed: () => setState(() => showPassed = !showPassed),
              child: Text(
                showPassed ? 'Hide people you passed' : 'Look again at $passed you passed',
                style: TextStyle(color: C.muted, fontSize: 14.5),
              ),
            ),
          ),
        if (alreadyHere.isNotEmpty) ...[
          const SizedBox(height: 26),
          const SectionLabel('Already connected'),
          for (final p in alreadyHere)
            _PersonRow(
              person: p,
              line: 'You’ve met. No need to connect again.',
              onTap: () => context.push('/chat/${r.connectedEvents[p.uid] ?? widget.id}/${Uri.encodeComponent(p.uid)}'),
              onMessage: () => context.push('/chat/${r.connectedEvents[p.uid] ?? widget.id}/${Uri.encodeComponent(p.uid)}'),
            ),
        ],
      ] else ...[
        if (myMatches.isEmpty)
          const EmptyState(
            mood: BuddyMood.normal,
            title: 'No matches yet',
            text: 'When you and someone both connect, they show up here with their contact details.',
          )
        else
          for (final p in myMatches)
            _PersonRow(
              person: p,
              line: p.headline,
              onTap: () => context.push('/e/${widget.id}/m/${Uri.encodeComponent(p.uid)}'),
              onMessage: () => context.push('/chat/${widget.id}/${Uri.encodeComponent(p.uid)}'),
            ),
      ],
    ];
  }
}

/// Who's in the room: a few faces and a count.
class _Headcount extends StatelessWidget {
  const _Headcount({required this.room});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final r = room;
    final faces = [
      if (r.me != null) (name: r.me!.displayName, url: r.me!.photoURL),
      for (final p in r.people) (name: p.displayName, url: p.photoURL),
    ];
    final n = math.max(r.count, faces.length);
    return Row(children: [
      if (faces.isNotEmpty) ...[AvatarStack(people: faces), const SizedBox(width: 8)],
      Text(
        n == 0
            ? 'Nobody’s checked in yet'
            : r.checkedIn
                ? '$n here, you included'
                : '$n checked in',
        style: TextStyle(color: C.muted, fontSize: 14.5),
      ),
    ]);
  }
}

class _RoomSkeleton extends StatelessWidget {
  const _RoomSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Skeleton(width: 150, height: 12),
          SizedBox(height: 14),
          Skeleton(width: 280, height: 34),
          SizedBox(height: 12),
          Skeleton(width: 200, height: 14),
          SizedBox(height: 26),
          Skeleton(height: 48, radius: 24),
          SizedBox(height: 18),
          Expanded(child: Skeleton(height: double.infinity, radius: 30)),
          SizedBox(height: 40),
        ]),
      );
}

/// Someone in the room I can already reach: a match, or a connection from before.
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.line, required this.onTap, required this.onMessage});
  final Attendee person;
  final String line;
  final VoidCallback onTap;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SurfaceCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          onTap: onTap,
          child: Row(children: [
            Avatar(name: person.displayName, url: person.photoURL, seed: person.uid, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  person.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
                ),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 14)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Material(
              color: C.paper,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: 'Message',
                child: InkWell(
                  onTap: onMessage,
                  child: SizedBox(width: 42, height: 42, child: Icon(Icons.chat_bubble_outline_rounded, size: 19, color: C.ink)),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// The top card of the deck: a poster of one person, with what the sidekick says about them.
/// Drag it right to connect and left to pass, or use the buttons under it.
class _Deck extends StatefulWidget {
  const _Deck({
    super.key,
    required this.person,
    required this.pick,
    required this.next,
    required this.me,
    required this.scouting,
    required this.onUndo,
    required this.canSwipe,
    required this.onSwipe,
  });
  final Attendee person;
  final ScoutPick pick;

  /// The person behind this one, whose card peeks out.
  final Attendee? next;
  final Attendee me;
  final bool scouting;
  final VoidCallback? onUndo;
  final Future<bool> Function(bool like) canSwipe;
  final ValueChanged<bool> onSwipe;

  @override
  State<_Deck> createState() => _DeckState();
}

class _DeckState extends State<_Deck> with TickerProviderStateMixin {
  double drag = 0;
  bool _going = false;
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
    ..forward();
  double _from = 0, _to = 0;
  Curve _curve = Curves.easeOut;

  @override
  void initState() {
    super.initState();
    _move.addListener(() => setState(() => drag = _from + (_to - _from) * _curve.transform(_move.value)));
  }

  @override
  void dispose() {
    _move.dispose();
    _enter.dispose();
    super.dispose();
  }

  Future<void> _animate(double to, Curve curve) {
    _from = drag;
    _to = to;
    _curve = curve;
    return _move.forward(from: 0);
  }

  Future<void> _go(bool like) async {
    if (_going) return;
    _going = true;
    if (!await widget.canSwipe(like)) {
      _going = false;
      if (mounted) _animate(0, Curves.easeOut);
      return;
    }
    if (!mounted) return;
    final w = MediaQuery.of(context).size.width;
    await _animate(like ? w * 1.3 : -w * 1.3, Curves.easeIn);
    widget.onSwipe(like);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final width = MediaQuery.of(context).size.width;
    final t = (drag / (width * 0.32)).clamp(-1.0, 1.0);
    final theyHelp = overlap(widget.me.lookingFor, p.offering).toSet();
    final iHelp = overlap(p.lookingFor, widget.me.offering).toSet();
    final strong = widget.pick.score >= 70;
    // Tall enough to be a poster, short enough that the buttons under it stay on screen.
    final height = (MediaQuery.of(context).size.height * 0.47).clamp(320.0, 500.0);

    final card = SizedBox(
        height: height,
        child: PortraitPoster(
          name: p.displayName,
          seed: p.uid,
          url: p.photoURL,
          radius: BorderRadius.circular(30),
          child: Stack(fit: StackFit.expand, children: [
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: strong ? signal : Poster.glass,
                  borderRadius: BorderRadius.circular(99),
                  border: strong ? null : Border.all(color: Poster.edge),
                ),
                child: Text(
                  fitLabel(widget.pick.score).toUpperCase(),
                  style: TextStyle(
                    color: strong ? onSignal : Poster.ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
            ),
            if (t.abs() > 0.12)
              Positioned(
                right: t > 0 ? null : 18,
                left: t > 0 ? 18 : null,
                top: 64,
                child: Opacity(
                  opacity: ((t.abs() - 0.12) / 0.5).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: t > 0 ? -0.16 : 0.16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: t > 0 ? signal : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t > 0 ? signal : Poster.ink, width: 2),
                      ),
                      child: Text(
                        t > 0 ? 'CONNECT' : 'PASS',
                        style: TextStyle(
                          color: t > 0 ? onSignal : Poster.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: displayStyle(40, color: Poster.ink),
                ),
                if (p.headline.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    p.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Poster.muted, fontSize: 15.5, height: 1.3),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 11),
                  decoration: BoxDecoration(
                    color: Poster.glass,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Poster.edge),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: widget.scouting
                          ? const SizedBox(
                              width: 15,
                              height: 13,
                              child: Center(
                                child: SizedBox(
                                  width: 11,
                                  height: 11,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: signal),
                                ),
                              ),
                            )
                          : const SidekickMark(
                              size: 13,
                              mood: BuddyMood.wink,
                              color: Poster.ink,
                              features: Poster.bg,
                              cheeks: signal,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.pick.reason,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Poster.ink, fontSize: 14.5, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
    );

    Widget label(String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: caps));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Stack(children: [
        // The next person's card, peeking out behind and rising as this one leaves.
        if (widget.next != null)
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, 12 - 12 * t.abs()),
              child: Transform.scale(
                scale: 0.94 + 0.06 * t.abs(),
                child: Opacity(
                  opacity: 0.55 + 0.45 * t.abs(),
                  child: PortraitPoster(
                    name: widget.next!.displayName,
                    seed: widget.next!.uid,
                    url: widget.next!.photoURL,
                    radius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ),
        Semantics(
          label: '${p.displayName}. ${p.headline}. ${widget.pick.reason}',
          child: GestureDetector(
            onHorizontalDragUpdate: (d) {
              if (!_going) setState(() => drag += d.delta.dx);
            },
            onHorizontalDragEnd: (d) {
              final v = d.velocity.pixelsPerSecond.dx;
              if (drag > width * 0.26 || v > 900) {
                _go(true);
              } else if (drag < -width * 0.26 || v < -900) {
                _go(false);
              } else {
                _animate(0, Curves.easeOutBack);
              }
            },
            child: FadeTransition(
              opacity: _enter,
              child: Transform.translate(
                offset: Offset(drag, drag.abs() * 0.06),
                child: Transform.rotate(angle: t * math.pi / 30, child: card),
              ),
            ),
          ),
        ),
      ]),
      SizedBox(height: widget.next != null ? 26 : 16),
      Row(children: [
        _CircleAction(icon: Icons.close_rounded, tooltip: 'Pass', onTap: () => _go(false)),
        if (widget.onUndo != null) ...[
          const SizedBox(width: 10),
          _CircleAction(icon: Icons.undo_rounded, tooltip: 'Undo the last pass', onTap: widget.onUndo!),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 58,
            child: SignalButton(label: 'Connect', icon: Icons.handshake_outlined, onPressed: () => _go(true)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Text(
        'Nobody sees a pass. Contacts swap only if you both connect.',
        textAlign: TextAlign.center,
        style: TextStyle(color: C.muted, fontSize: 12.5),
      ),
      if (p.about.isNotEmpty || p.lookingFor.isNotEmpty || p.offering.isNotEmpty) ...[
        const SizedBox(height: 22),
        SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.about.isNotEmpty) ...[
              label('ABOUT ${firstName(p.displayName).toUpperCase()}'),
              Text(p.about, style: const TextStyle(fontSize: 15.5, height: 1.5)),
              if (p.lookingFor.isNotEmpty || p.offering.isNotEmpty) const SizedBox(height: 20),
            ],
            if (p.lookingFor.isNotEmpty) ...[
              label('LOOKING FOR'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final x in p.lookingFor) _DeckTag(x, highlight: iHelp.contains(x))],
              ),
              if (p.offering.isNotEmpty) const SizedBox(height: 18),
            ],
            if (p.offering.isNotEmpty) ...[
              label('CAN OFFER'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final x in p.offering) _DeckTag(x, highlight: theyHelp.contains(x))],
              ),
            ],
            if (iHelp.isNotEmpty || theyHelp.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Highlighted where the two of you line up.',
                style: TextStyle(color: C.muted, fontSize: 12.5),
              ),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class _DeckTag extends StatelessWidget {
  const _DeckTag(this.label, {required this.highlight});
  final String label;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: highlight ? C.second : C.paper,
          borderRadius: BorderRadius.circular(99),
          ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.1,
            color: highlight ? C.onSecond : C.ink,
            fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      );
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: C.paper,
          shape: CircleBorder(side: BorderSide(color: C.line, width: 1.4)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 58, height: 58, child: Icon(icon, size: 26, color: C.ink)),
          ),
        ),
      );
}
