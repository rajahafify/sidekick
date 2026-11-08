import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// One conversation with a match. It refreshes every few seconds while it's open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.eventId, required this.other});
  final String eventId;
  final String other;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  Api? api;
  ChatThread? thread;
  String? error;
  bool sending = false;
  Timer? _poll;

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
      if (mounted) {
        setState(() {
          thread = t;
          error = null;
        });
      }
    } on ApiError catch (e) {
      // A refresh that fails quietly keeps the messages already on screen.
      if (mounted && (!quiet || thread == null)) setState(() => error = e.message);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final a = api;
    if (text.isEmpty || sending || a == null) return;
    setState(() => sending = true);
    try {
      await a.send(widget.eventId, widget.other, text);
      _text.clear();
      await _load(quiet: true);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final name = t?.name ?? '';
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Avatar(name: name, url: t?.photoURL ?? '', size: 34),
          const SizedBox(width: 12),
          Flexible(child: Text(name.isEmpty ? 'Message' : name, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Their details',
            icon: const Icon(Icons.contact_page_outlined),
            onPressed: () => context.push('/e/${widget.eventId}/m/${Uri.encodeComponent(widget.other)}'),
          ),
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
        _composer(),
      ]),
    );
  }

  Widget _messages(ChatThread? t) {
    if (t == null) {
      if (error == null) return const Center(child: Loading());
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: ErrorNote(error)),
      );
    }
    if (t.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'You matched with ${t.name}. Say hi.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, fontSize: 16, height: 1.4),
          ),
        ),
      );
    }
    // Newest at the bottom, and the list starts there, so it always opens on the latest message.
    final newestFirst = t.messages.reversed.toList();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: newestFirst.length,
      itemBuilder: (_, i) => _Bubble(message: newestFirst[i]),
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
                decoration: const InputDecoration(hintText: 'Message', counterText: ''),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: sending ? null : _send,
              style: IconButton.styleFrom(backgroundColor: C.ink, foregroundColor: C.onInk),
              icon: sending ? const ButtonProgress() : const Icon(Icons.arrow_upward_rounded),
            ),
          ]),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: mine ? C.ink : C.soft, borderRadius: BorderRadius.circular(18)),
        child: Text(message.text, style: TextStyle(color: mine ? C.onInk : C.ink, fontSize: 16, height: 1.35)),
      ),
    );
  }
}
