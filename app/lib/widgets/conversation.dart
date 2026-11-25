import 'package:flutter/material.dart';

import '../data/api.dart';
import '../logic/sidekick.dart';
import '../models.dart';
import '../theme.dart';
import 'ui.dart';

/// One line of the sidekicks' talk. `mine` lines are my sidekick's, and sit on the right.
class TalkBubble extends StatelessWidget {
  const TalkBubble({super.key, required this.mine, required this.who, required this.text});
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

/// Before I swipe: what the two sidekicks would say about this person. Loaded when opened, so the
/// deck itself stays light. Only the profiles go into it, so it says nothing about who has swiped.
class ConversationSheet extends StatefulWidget {
  const ConversationSheet({super.key, required this.api, required this.eventId, required this.me, required this.person});
  final Api api;
  final String eventId;
  final Attendee me;
  final Attendee person;

  @override
  State<ConversationSheet> createState() => _ConversationSheetState();
}

class _ConversationSheetState extends State<ConversationSheet> {
  late final Future<Exchange> _talk = widget.api.conversation(widget.eventId, widget.person.uid);

  @override
  Widget build(BuildContext context) {
    final name = firstName(widget.person.displayName);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: FutureBuilder<Exchange>(
          future: _talk,
          builder: (context, snap) {
            final Widget body;
            if (snap.connectionState != ConnectionState.done) {
              body = const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              );
            } else if (snap.hasError || snap.data == null) {
              body = Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  'Your sidekick couldn’t reach this conversation just now. Try again in a moment.',
                  style: TextStyle(color: C.muted, fontSize: 15, height: 1.4),
                ),
              );
            } else {
              final ex = snap.data!;
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionLabel('Before you connect'),
                if (ex.reason.isNotEmpty) ...[
                  Text(ex.reason, style: const TextStyle(fontSize: 16, height: 1.5)),
                  const SizedBox(height: 16),
                ],
                for (final t in ex.turns)
                  TalkBubble(
                    mine: t.speaker == widget.me.uid,
                    who: t.speaker == widget.me.uid ? 'Your sidekick' : '$name’s sidekick',
                    text: t.text,
                  ),
                if (ex.opener.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('If you connect, try', style: caps),
                  const SizedBox(height: 6),
                  Text('“${ex.opener}”', style: displayStyle(22, style: FontStyle.italic).copyWith(height: 1.15)),
                ],
              ]);
            }
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('How your sidekicks would talk', style: displayStyle(26)),
                const SizedBox(height: 4),
                Text('With ${firstName(widget.person.displayName)}. Nobody sees if you connect or pass.',
                    style: TextStyle(color: C.muted, fontSize: 14, height: 1.4)),
                const SizedBox(height: 18),
                body,
              ]),
            );
          },
        ),
      ),
    );
  }
}
