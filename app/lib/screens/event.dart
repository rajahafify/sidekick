import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/api.dart';
import '../data/location.dart';
import '../logic/geo_when.dart';
import '../logic/sidekick.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/dots.dart';
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

  Api get api => SessionScope.of(context).api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (widget.share && mounted && room != null) _shareSheet();
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
      final hadMatches = room?.matches.toSet() ?? <String>{};
      setState(() {
        room = r;
        loadError = null;
      });
      if (quiet) {
        final fresh = r.matches.where((m) => !hadMatches.contains(m));
        if (fresh.isNotEmpty && hadMatches.isNotEmpty) _celebrate(fresh.first);
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
    final e = room!.event;
    Map<String, dynamic>? fix;
    if (e.hasLocation) {
      final f = await currentFix();
      if (f == null) {
        throw ApiError("Turn on location so Sidekick can check you're there. It's only used for this check.");
      }
      fix = {'lat': f.lat, 'lng': f.lng, 'accuracy': f.accuracy};
    }
    await api.join(widget.id, fix);
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
    setState(() => _optimistic[p.uid] = like);
    try {
      final matched = await api.swipe(widget.id, p.uid, like);
      await _load(quiet: true);
      if (matched && mounted) _celebrate(p.uid);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _optimistic.remove(p.uid));
      if (e.needsLogin) {
        await askToSignIn(context);
      } else {
        toast(context, e.message);
      }
    }
  }

  void _celebrate(String uid) {
    final p = room?.people.where((x) => x.uid == uid).firstOrNull;
    if (p == null) return;
    final mine = room?.me;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("IT'S A MATCH", textAlign: TextAlign.center, style: eyebrow),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 128,
                  height: 72,
                  child: Stack(children: [
                    if (mine != null) Positioned(left: 0, child: Avatar(name: mine.displayName, url: mine.photoURL, size: 72)),
                    Positioned(right: 0, child: Avatar(name: p.displayName, url: p.photoURL, size: 72)),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              Text('You and ${firstName(p.displayName)} both want to connect',
                  textAlign: TextAlign.center, style: displayStyle(30)),
              const SizedBox(height: 8),
              const Text(
                'Your contacts are swapped, and your sidekick wrote an opener for the break.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () {
                  Navigator.pop(c);
                  context.push('/e/${widget.id}/m/${Uri.encodeComponent(uid)}');
                },
                child: const Text('See contact and opener'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Keep scouting', style: TextStyle(color: C.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareSheet() {
    final link = Config.eventLink(widget.id);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bring the room in', style: displayStyle(32)),
              const SizedBox(height: 8),
              const Text(
                'Sidekick only works when people are checked in. Share the link or put the code on screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(data: link, size: 200, backgroundColor: C.ink),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () =>
                    SharePlus.instance.share(ShareParams(text: '${room?.event.name ?? 'Join me'} on Sidekick: $link')),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share link'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu() async {
    final r = room!;
    final visible = r.me?.visible ?? true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('Share this event'),
              onTap: () => Navigator.pop(c, 'share'),
            ),
            if (r.checkedIn)
              ListTile(
                leading: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                title: Text(visible ? 'Hide me from new people' : 'Show me in the room again'),
                subtitle: Text(visible ? 'Matches you already have stay.' : '', style: const TextStyle(color: C.muted)),
                onTap: () => Navigator.pop(c, 'visible'),
              ),
            if (r.checkedIn)
              ListTile(
                leading: const Icon(Icons.logout, color: C.danger),
                title: const Text('Leave this event', style: TextStyle(color: C.danger)),
                onTap: () => Navigator.pop(c, 'leave'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'share') _shareSheet();
    if (choice == 'visible') {
      await _run(() async {
        await api.setVisible(widget.id, !visible);
        await _load();
      });
    }
    if (choice == 'leave') {
      await _run(() async {
        await api.leave(widget.id);
        await _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (notFound) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          title: 'Event not found',
          text: 'Check the link, or ask whoever shared it for a new one.',
          action: OutlinedButton(onPressed: () => context.go('/'), child: const Text('Go home')),
        ),
      );
    }
    final r = room;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loadError == null
            ? const Loading()
            : EmptyState(
                title: "Can't load this",
                text: loadError!,
                action: FilledButton(onPressed: _load, child: const Text('Try again')),
              ),
      );
    }
    final e = r.event;
    final phase = eventPhase(e.startsAt, e.endsAt);
    final when = e.isPlace
        ? 'CHECK-INS · ${e.startsAt == null ? 'TODAY' : eventWhen(e.startsAt, null).split(',').take(2).join(',').toUpperCase()}'
        : phase == EventPhase.live
        ? 'HAPPENING NOW'
        : [
            eventWhen(e.startsAt, e.endsAt).toUpperCase(),
            if (phase == EventPhase.ended) 'ENDED',
          ].where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      appBar: AppBar(
        // Opened from a link: there's nothing to go back to, so the wordmark goes home.
        automaticallyImplyLeading: false,
        leadingWidth: 110,
        // Opened from a link: there's nothing to go back to, so Back goes home.
        leading: TextButton.icon(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: C.ink),
          label: const Text('Back', style: TextStyle(color: C.ink, fontSize: 17, fontWeight: FontWeight.w400)),
        ),
        actions: [
          TextButton(
            onPressed: _shareSheet,
            child: const Text('Share', style: TextStyle(color: C.go, fontSize: 17, fontWeight: FontWeight.w400)),
          ),
          if (r.checkedIn) IconButton(onPressed: _menu, icon: const Icon(Icons.more_horiz, color: C.muted)),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      body: RefreshIndicator(
        color: C.go,
        backgroundColor: C.surface,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            const SizedBox(height: 16),
            Text(when.isEmpty ? 'HAPPENING NOW' : when, style: eyebrow.copyWith(letterSpacing: 2.2)),
            const SizedBox(height: 10),
            Text(e.name, style: displayStyle(42)),
            const SizedBox(height: 8),
            if (e.place.isNotEmpty)
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': e.place}),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${e.place} '),
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(Icons.north_east_rounded, size: 15, color: C.muted),
                    ),
                  ]),
                  style: const TextStyle(color: C.muted, fontSize: 16),
                ),
              ),
            const SizedBox(height: 4),
            Text('${r.count} checked in', style: const TextStyle(color: C.muted, fontSize: 14)),
            const SizedBox(height: 22),
            if (!r.checkedIn) ..._joinSection(r, phase) else ..._roomSection(r),
            ErrorNote(error),
          ],
        ),
      ),
    );
  }

  List<Widget> _joinSection(Room r, EventPhase phase) => [
    SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send your sidekick in', style: displayStyle(28)),
          const SizedBox(height: 8),
          Text(
            phase == EventPhase.ended
                ? 'This event has ended.'
                : 'Check in and your sidekick scouts everyone here, then shows you who is worth meeting. '
                      "Nobody sees who you pass on.${r.event.hasLocation ? " You need to be at the venue." : ''}",
            style: const TextStyle(color: C.muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: busy || phase == EventPhase.ended ? null : _join,
            child: busy ? const ButtonProgress() : Text(r.event.isPlace ? 'Check in here' : "I'm at this event"),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _roomSection(Room r) {
    final me = r.me!;
    final swipes = {...r.swipes, ..._optimistic};
    final matched = r.matches.toSet();
    final picks = {for (final p in scout?.picks ?? const <ScoutPick>[]) p.uid: p};
    final byId = {for (final p in r.people) p.uid: p};
    final deck =
        r.people
            .where(
              (p) => !matched.contains(p.uid) && (!swipes.containsKey(p.uid) || (showPassed && swipes[p.uid] == false)),
            )
            .map((p) => (person: p, pick: picks[p.uid] ?? templatePick(me, p)))
            .toList()
          ..sort((a, b) => b.pick.score.compareTo(a.pick.score));
    final passed = r.people.where((p) => swipes[p.uid] == false && !matched.contains(p.uid)).length;
    final waiting = r.people.where((p) => swipes[p.uid] == true && !matched.contains(p.uid)).length;
    final myMatches = r.matches.map((u) => byId[u]).whereType<Attendee>().toList();

    return [
      SurfaceCard(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        child: Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Visible to others', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 2),
              Text("Other people's sidekicks can suggest you.", style: TextStyle(color: C.muted, fontSize: 14)),
            ]),
          ),
          Switch(
            value: me.visible,
            activeTrackColor: C.go,
            activeThumbColor: C.ink,
            onChanged: busy
                ? null
                : (v) => _run(() async {
                      await api.setVisible(widget.id, v);
                      await _load();
                    }),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Row(children: [
          _TabLabel(text: deck.isEmpty ? 'Scouted' : 'Scouted · ${deck.length}', on: tab == 0, onTap: () => setState(() => tab = 0)),
          _TabLabel(
            text: myMatches.isEmpty ? 'Matches' : 'Matches · ${myMatches.length}',
            on: tab == 1,
            onTap: () => setState(() => tab = 1),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      if (tab == 0) ...[
        if (!me.visible)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              "You're hidden from new people. Matches you already have stay.",
              style: TextStyle(color: C.muted),
            ),
          ),
        if (r.guest)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              "You're a guest: you can see your picks. Sign in to connect.",
              style: const TextStyle(color: C.muted, fontSize: 14),
            ),
          ),
        if (r.people.isEmpty)
          const EmptyState(
            icon: Icons.radar,
            title: 'Your sidekick is waiting',
            text: "Nobody else is checked in yet. Share the event and they'll show up here.",
          )
        else if (deck.isEmpty)
          EmptyState(
            icon: Icons.check_circle_outline,
            title: "You've seen everyone",
            text: waiting > 0
                ? "You connected with $waiting ${waiting == 1 ? 'person' : 'people'}. If they connect back, it's a match."
                : 'New people show up here as they check in.',
          )
        else ...[
          _Deck(
            key: ValueKey(deck.first.person.uid),
            person: deck.first.person,
            pick: deck.first.pick,
            me: me,
            llm: scout?.source == 'llm',
            scouting: scouting,
            canSwipe: (like) => _canSwipe(deck.first.person, like),
            onSwipe: (like) => _swipe(deck.first.person, like),
          ),
          const SizedBox(height: 12),
          Text(
            '${deck.length - 1} more lined up',
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.muted, fontSize: 13),
          ),
        ],
        if (passed > 0)
          TextButton(
            onPressed: () => setState(() => showPassed = !showPassed),
            child: Text(showPassed ? 'Hide people you passed' : 'Show $passed you passed'),
          ),
      ] else ...[
        if (myMatches.isEmpty)
          const EmptyState(
            icon: Icons.handshake_outlined,
            title: 'No matches yet',
            text: 'When you and someone both connect, they show up here with their contact details.',
          )
        else
          for (final p in myMatches)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                onTap: () => context.push('/e/${widget.id}/m/${Uri.encodeComponent(p.uid)}'),
                child: Row(
                  children: [
                    Avatar(name: p.displayName, url: p.photoURL, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          if (p.headline.isNotEmpty)
                            Text(
                              p.headline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: C.muted),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: C.muted),
                  ],
                ),
              ),
            ),
      ],
    ];
  }
}

/// The top card of the deck. Drag right to connect, left to pass, or use the buttons.
class _Deck extends StatefulWidget {
  const _Deck({
    super.key,
    required this.person,
    required this.pick,
    required this.me,
    required this.llm,
    required this.scouting,
    required this.canSwipe,
    required this.onSwipe,
  });
  final Attendee person;
  final ScoutPick pick;
  final Attendee me;
  final bool llm;
  final bool scouting;
  final Future<bool> Function(bool like) canSwipe;
  final ValueChanged<bool> onSwipe;

  @override
  State<_Deck> createState() => _DeckState();
}

class _DeckState extends State<_Deck> with SingleTickerProviderStateMixin {
  Offset drag = Offset.zero;
  late final AnimationController _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Offset _from = Offset.zero, _to = Offset.zero;

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  bool _going = false;

  Future<void> _go(bool like) async {
    if (_going) return;
    _going = true;
    if (!await widget.canSwipe(like)) {
      _going = false;
      if (mounted) _back();
      return;
    }
    if (!mounted) return;
    final w = MediaQuery.of(context).size.width;
    _from = drag;
    _to = Offset(like ? w * 1.4 : -w * 1.4, drag.dy + 40);
    _fly.addListener(() => setState(() => drag = Offset.lerp(_from, _to, Curves.easeIn.transform(_fly.value))!));
    await _fly.forward();
    widget.onSwipe(like);
  }

  void _back() {
    _from = drag;
    _to = Offset.zero;
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    c.addListener(() => setState(() => drag = Offset.lerp(_from, _to, Curves.easeOut.transform(c.value))!));
    c.forward().whenComplete(c.dispose);
  }

  String get _fit {
    final s = widget.pick.score;
    if (s >= 70) return 'Strong fit';
    if (s >= 40) return 'Good fit';
    return 'Worth a hello';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final width = MediaQuery.of(context).size.width;
    final t = (drag.dx / (width * 0.35)).clamp(-1.0, 1.0);
    final theyHelp = overlap(widget.me.lookingFor, p.offering).toSet();
    final iHelp = overlap(p.lookingFor, widget.me.offering).toSet();

    final initials = p.displayName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(t, style: const TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.6)),
        );

    return GestureDetector(
      onPanUpdate: (d) => setState(() => drag += d.delta),
      onPanEnd: (d) {
        final v = d.velocity.pixelsPerSecond.dx;
        if (drag.dx > width * 0.28 || v > 900) {
          _go(true);
        } else if (drag.dx < -width * 0.28 || v < -900) {
          _go(false);
        } else {
          _back();
        }
      },
      child: Transform.translate(
        offset: drag,
        child: Transform.rotate(
          angle: t * math.pi / 28,
          child: Container(
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: t > 0.15
                    ? C.go.withValues(alpha: t)
                    : t < -0.15
                    ? C.muted.withValues(alpha: -t)
                    : C.line,
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 400,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (p.photoURL.isNotEmpty)
                        ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white, Colors.white, Colors.transparent],
                            stops: [0, 0.5, 1],
                          ).createShader(r),
                          blendMode: BlendMode.dstIn,
                          child: Image.network(p.photoURL, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                        )
                      else
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF1E1410), C.surface],
                            ),
                          ),
                          child: Align(
                            alignment: const Alignment(0, -0.2),
                            child: Text(
                              initials,
                              style: displayStyle(150, color: C.go.withValues(alpha: 0.22), style: FontStyle.italic),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 18,
                        top: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: C.line),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(_fit.toUpperCase(), style: eyebrow.copyWith(fontSize: 11)),
                            if (widget.scouting) ...[
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: C.go),
                              ),
                            ],
                          ]),
                        ),
                      ),
                      if (t.abs() > 0.15)
                        Positioned(
                          right: 20,
                          top: 22,
                          child: Text(
                            t > 0 ? 'CONNECT' : 'PASS',
                            style: eyebrow.copyWith(color: t > 0 ? C.go : C.muted, fontSize: 14),
                          ),
                        ),
                      Positioned(
                        left: 22,
                        right: 22,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.displayName, style: displayStyle(40)),
                            if (p.headline.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(p.headline, style: const TextStyle(color: C.ink, fontSize: 16)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xFF0B0B0B),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(left: 16),
                        decoration: const BoxDecoration(border: Border(left: BorderSide(color: C.go, width: 2))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const SidekickMark(size: 12, mood: BuddyMood.wink),
                            const SizedBox(width: 7),
                            Text('YOUR SIDEKICK · QUICK READ', style: eyebrow.copyWith(fontSize: 11)),
                          ]),
                          const SizedBox(height: 8),
                          Text(widget.pick.reason, style: const TextStyle(fontSize: 16, height: 1.45)),
                        ]),
                      ),
                      if (p.about.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(p.about, style: const TextStyle(color: C.muted, fontSize: 15, height: 1.45)),
                      ],
                      if (p.lookingFor.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        label('LOOKING FOR'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final x in p.lookingFor) Tag(x, highlight: iHelp.contains(x))],
                        ),
                      ],
                      if (p.offering.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        label('CAN OFFER'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final x in p.offering) Tag(x, highlight: theyHelp.contains(x))],
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(backgroundColor: C.soft),
                            onPressed: () => _go(false),
                            child: const Text('Pass'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: FilledButton(onPressed: () => _go(true), child: const Text('Connect'))),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, required this.on, required this.onTap});
  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? C.soft : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: on ? C.ink : C.muted)),
          ),
        ),
      );
}
