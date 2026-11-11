import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/api.dart';
import '../logic/chat.dart';
import '../logic/sidekick.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/mark.dart';
import '../widgets/ui.dart';

/// One conversation with a match. It refreshes every few seconds while it's open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.eventId, required this.other, this.draft});
  final String eventId;
  final String other;

  /// Text to start the message box with, such as the sidekick's opener.
  final String? draft;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _text = TextEditingController(text: widget.draft ?? '');
  Api? api;
  ChatThread? thread;
  String? error;
  Timer? _poll;

  /// Messages on their way: shown at once, and swapped for the saved ones when the server answers.
  final List<ChatMessage> _sending = [];

  /// The sidekick's opener for this match, offered while the conversation is empty.
  String? opener;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load(quiet: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    api ??= SessionScope.of(context).api;
    if (thread == null && error == null) _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final a = api;
    if (a == null) return;
    try {
      final t = await a.chat(widget.eventId, widget.other);
      if (!mounted) return;
      setState(() {
        thread = t;
        error = null;
      });
      if (t.messages.isEmpty && opener == null) _loadOpener();
    } on ApiError catch (e) {
      // A refresh that fails quietly keeps the messages already on screen.
      if (mounted && (!quiet || thread == null)) setState(() => error = e.message);
    }
  }

  Future<void> _loadOpener() async {
    opener = '';
    try {
      final m = await api!.match(widget.eventId, widget.other);
      if (mounted) setState(() => opener = m.exchange.opener);
    } catch (_) {
      // The conversation works without a suggestion.
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final a = api;
    if (text.isEmpty || a == null || thread == null) return;
    final pending = ChatMessage(id: 'sending-${DateTime.now().microsecondsSinceEpoch}', mine: true, text: text, at: DateTime.now());
    setState(() => _sending.add(pending));
    _text.clear();
    haptic();
    try {
      await a.send(widget.eventId, widget.other, text);
      await _load(quiet: true);
    } on ApiError catch (e) {
      if (mounted) {
        toast(context, e.message);
        // Give the words back, so nothing typed is lost.
        if (_text.text.isEmpty) _text.text = text;
      }
    } finally {
      if (mounted) setState(() => _sending.remove(pending));
    }
  }

  void _details() => context.push('/e/${widget.eventId}/m/${Uri.encodeComponent(widget.other)}');

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final name = t?.name ?? '';
    return Scaffold(
      appBar: BackBar(
        onBack: () => context.canPop() ? context.pop() : context.go('/messages'),
        title: t == null
            ? null
            : Semantics(
                button: true,
                label: 'See $name’s details',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _details,
                  child: Row(children: [
                    const SizedBox(width: 10),
                    Avatar(name: name, url: t.photoURL, size: 36),
                    const SizedBox(width: 10),
                    Flexible(child: Text(name.isEmpty ? 'Message' : name, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
        actions: [
          if (t != null) RoundIconButton(icon: Icons.person_outline_rounded, tooltip: 'Their details', onTap: _details),
        ],
      ),
      body: Column(children: [
        Expanded(child: _messages(t)),
        if (t?.left == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              '$name has left the event. You can still message each other.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
          ),
        if (t != null) _composer(),
      ]),
    );
  }

  Widget _messages(ChatThread? t) {
    if (t == null) {
      if (error == null) return const Center(child: Loading());
      return Center(
        child: EmptyState(
          mood: BuddyMood.normal,
          title: 'Can’t open this chat',
          text: error!,
          action: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(160, 50)),
            onPressed: () {
              setState(() => error = null);
              _load();
            },
            child: const Text('Try again'),
          ),
        ),
      );
    }
    final all = [...t.messages, ..._sending];
    if (all.isEmpty) {
      final first = firstName(t.name);
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Avatar(name: t.name, url: t.photoURL, seed: t.uid, size: 96),
            const SizedBox(height: 20),
            Text('You matched with $first', textAlign: TextAlign.center, style: displayStyle(30)),
            const SizedBox(height: 8),
            Text(
              'Say hi, and find each other at the break.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, fontSize: 15.5, height: 1.4),
            ),
            if ((opener ?? '').isNotEmpty) ...[
              const SizedBox(height: 22),
              Material(
                color: C.second,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    _text.text = opener!;
                    _text.selection = TextSelection.collapsed(offset: opener!.length);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const SidekickMark(size: 13, mood: BuddyMood.wink),
                        const SizedBox(width: 8),
                        Expanded(child: Text('YOUR SIDEKICK SUGGESTS', style: eyebrow.copyWith(fontSize: 10.5))),
                        Text('Tap to use', style: TextStyle(color: C.go, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      Text('“$opener”', style: displayStyle(21, style: FontStyle.italic).copyWith(height: 1.15)),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ),
      );
    }

    // Newest at the bottom, and the list starts there, so it always opens on the latest message.
    // Each row knows whether it starts a day, and whether it ends a run from one person.
    final rows = <Widget>[];
    for (var i = all.length - 1; i >= 0; i--) {
      final m = all[i];
      final older = i > 0 ? all[i - 1] : null;
      final newer = i < all.length - 1 ? all[i + 1] : null;
      final at = m.at;
      final startsDay = at != null && (older?.at == null || !sameDay(older!.at!, at));
      final endsRun = newer == null ||
          newer.mine != m.mine ||
          (at != null && newer.at != null && newer.at!.difference(at).inMinutes >= 5);
      rows.add(_Bubble(
        message: m,
        endsRun: endsRun,
        sending: m.id.startsWith('sending-'),
        day: startsDay ? dayLabel(at) : null,
      ));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message',
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: _text,
              builder: (_, v, _) {
                final can = v.text.trim().isNotEmpty;
                return Tooltip(
                  message: 'Send',
                  child: Material(
                    color: can ? C.brand : C.surface,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: can ? _send : null,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.arrow_upward_rounded, color: can ? C.onBrand : C.muted, size: 22),
                      ),
                    ),
                  ),
                );
              },
            ),
          ]),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.endsRun, required this.sending, this.day});
  final ChatMessage message;

  /// The last message of a run from one person: it gets the tail and the time.
  final bool endsRun;
  final bool sending;

  /// Set on the first message of a day, to label it.
  final String? day;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final at = message.at;
    const round = Radius.circular(20), tail = Radius.circular(6);
    return Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (day != null)
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 10),
            child: Text(day!.toUpperCase(), style: caps.copyWith(fontSize: 10.5)),
          ),
        ),
      Opacity(
        opacity: sending ? 0.6 : 1,
        child: Container(
          margin: EdgeInsets.only(top: 2, bottom: endsRun ? 2 : 1),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? C.brand : C.surface,
            borderRadius: BorderRadius.only(
              topLeft: round,
              topRight: round,
              bottomLeft: !mine && endsRun ? tail : round,
              bottomRight: mine && endsRun ? tail : round,
            ),
          ),
          child: Text(message.text, style: TextStyle(color: mine ? C.onBrand : C.ink, fontSize: 16, height: 1.35)),
        ),
      ),
      if (endsRun)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
          child: Text(
            sending ? 'Sending…' : (at == null ? '' : DateFormat.jm().format(at)),
            style: TextStyle(color: C.muted, fontSize: 11.5),
          ),
        ),
    ]);
  }
}
