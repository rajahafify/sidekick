import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../logic/sidekick.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/contact.dart';
import '../widgets/mark.dart';
import '../widgets/ui.dart';

/// A match: who they are, how to reach them, the opener, and what the two sidekicks said.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.eventId, required this.other});
  final String eventId;
  final String other;
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  MatchDetails? m;
  String? error;
  bool showTalk = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (m == null && error == null) _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final r = await SessionScope.of(context).api.match(widget.eventId, widget.other);
      if (mounted) setState(() => m = r);
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/');

  void _message({String? draft}) {
    final q = draft == null ? '' : '?draft=${Uri.encodeQueryComponent(draft)}';
    context.push('/chat/${widget.eventId}/${Uri.encodeComponent(widget.other)}$q');
  }

  Future<void> _safety() async {
    final api = SessionScope.of(context).api;
    final name = firstName(m?.person.displayName ?? '');
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetAction(
              icon: Icons.block_rounded,
              title: 'Block $name',
              text: 'You stop seeing each other, here and at other events.',
              onTap: () => Navigator.pop(c, 'block'),
            ),
            SheetAction(
              icon: Icons.flag_outlined,
              title: 'Report and block',
              text: 'Tell us what happened. We look at every report.',
              danger: true,
              onTap: () => Navigator.pop(c, 'report'),
            ),
          ]),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'report') {
        final reason = await _askReason();
        if (reason == null) return;
        await api.report(widget.other, widget.eventId, reason);
      } else if (!await confirmSheet(
        context,
        title: 'Block $name?',
        text: 'You won’t see each other again, and this conversation is hidden.',
        action: 'Block',
      )) {
        return;
      }
      await api.block(widget.other);
      if (mounted) {
        toast(context, 'Blocked. They won’t see you again.');
        _back();
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<String?> _askReason() {
    final c = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (d) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.viewInsetsOf(d).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('What happened?', style: displayStyle(30)),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              maxLength: 500,
              maxLines: 4,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'A sentence or two is enough.'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.danger, foregroundColor: C.paper),
              onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? 'No reason given' : c.text.trim()),
              child: const Text('Report and block'),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: C.muted))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = m;
    if (d == null) {
      return Scaffold(
        appBar: BackBar(onBack: _back),
        body: error == null
            ? const Loading()
            : Center(
                child: EmptyState(
                  mood: BuddyMood.normal,
                  title: 'Not available',
                  text: error!,
                  action: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(160, 50)),
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ),
              ),
      );
    }
    final name = firstName(d.person.displayName);
    final top = MediaQuery.paddingOf(context).top;
    final height = (MediaQuery.sizeOf(context).height * 0.5).clamp(320.0, 480.0);
    return Scaffold(
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            SizedBox(
              height: height,
              child: PortraitPoster(
                name: d.person.displayName,
                seed: d.person.uid,
                url: d.person.photoURL,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const SidekickMark(
                          size: 15,
                          mood: BuddyMood.happy,
                          color: Poster.ink,
                          features: Poster.bg,
                          cheeks: signal,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'IT’S A MATCH',
                          style: TextStyle(color: signal, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 2),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(d.person.displayName, style: displayStyle(46, color: Poster.ink)),
                      if (d.person.headline.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(d.person.headline, style: const TextStyle(color: Poster.muted, fontSize: 16, height: 1.3)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(
                  onPressed: _message,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                  label: Text('Message $name'),
                ),
                if (d.exchange.opener.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
                    decoration: BoxDecoration(color: C.second, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const SidekickMark(size: 14, mood: BuddyMood.wink),
                        const SizedBox(width: 8),
                        Text('OPEN WITH', style: eyebrow.copyWith(fontSize: 11)),
                      ]),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('“${d.exchange.opener}”', style: displayStyle(27, style: FontStyle.italic).copyWith(height: 1.12)),
                      ),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: d.exchange.opener));
                            toast(context, 'Opener copied');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy'),
                        ),
                        TextButton.icon(
                          onPressed: () => _message(draft: d.exchange.opener),
                          icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                          label: const Text('Send it'),
                        ),
                      ]),
                    ]),
                  ),
                ],
                if (!d.contact.isEmpty) ...[
                  const SizedBox(height: 28),
                  SectionLabel('How to reach $name'),
                  ContactLinks(contact: d.contact),
                ],
                if (d.person.about.isNotEmpty || d.person.lookingFor.isNotEmpty || d.person.offering.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  SectionLabel('About $name'),
                  if (d.person.about.isNotEmpty) ...[
                    Text(d.person.about, style: const TextStyle(fontSize: 15.5, height: 1.5)),
                    const SizedBox(height: 14),
                  ],
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in d.person.lookingFor) Tag('Wants: $t'),
                    for (final t in d.person.offering) Tag('Offers: $t'),
                  ]),
                ],
                if (d.exchange.reason.isNotEmpty || d.exchange.turns.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const SectionLabel('Why you two'),
                  if (d.exchange.reason.isNotEmpty)
                    Text(d.exchange.reason, style: const TextStyle(fontSize: 16, height: 1.5)),
                  if (d.exchange.turns.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: C.muted),
                        onPressed: () => setState(() => showTalk = !showTalk),
                        icon: Icon(showTalk ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
                        label: Text(showTalk ? 'Hide what your sidekicks said' : 'Read what your sidekicks said'),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: showTalk
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(children: [
                                for (final t in d.exchange.turns)
                                  _Bubble(
                                    mine: t.speaker != widget.other,
                                    who: t.speaker != widget.other ? 'Your sidekick' : '$name’s sidekick',
                                    text: t.text,
                                  ),
                              ]),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ],
              ]),
            ),
          ],
        ),
        Positioned(
          left: 14,
          right: 14,
          top: top + 9,
          child: Row(children: [
            RoundIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', glass: true, onTap: _back),
            const Spacer(),
            RoundIconButton(icon: Icons.more_horiz_rounded, tooltip: 'Block or report', glass: true, onTap: _safety),
          ]),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.mine, required this.who, required this.text});
  final bool mine;
  final String who;
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 5),
              bottomRight: Radius.circular(mine ? 5 : 18),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(who.toUpperCase(), style: caps.copyWith(fontSize: 10)),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(fontSize: 15, height: 1.4)),
          ]),
        ),
      );
}
