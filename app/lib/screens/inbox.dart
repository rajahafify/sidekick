import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/ui.dart';

/// Short, human time for the lists: "now", "12 min", "3 h", "Tue", "4 Nov".
String ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inDays < 1) return '${d.inHours} h';
  if (d.inDays < 7) return DateFormat('EEE').format(t);
  return DateFormat('d MMM').format(t);
}

/// The Alerts tab: new matches and messages, newest first.
class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key});
  @override
  Widget build(BuildContext context) => const _Inbox(alerts: true);
}

/// The Messages tab: the conversations you have with your matches, newest first.
class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key});
  @override
  Widget build(BuildContext context) => const _Inbox(alerts: false);
}

class _Inbox extends StatefulWidget {
  const _Inbox({required this.alerts});
  final bool alerts;
  @override
  State<_Inbox> createState() => _InboxState();
}

class _InboxState extends State<_Inbox> {
  NoteList? list;
  String? error;
  Api? api;
  bool loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = SessionScope.of(context);
    api = session.api;
    if (list == null && error == null && !session.guest) _load();
  }

  Future<void> _load() async {
    final a = api;
    if (a == null || loading) return;
    loading = true;
    try {
      final r = widget.alerts ? await a.alerts() : await a.chats();
      if (!mounted) return;
      setState(() {
        list = r;
        error = null;
      });
      // The dots stay on for this visit. The next visit starts clean.
      if (widget.alerts && r.unread > 0) {
        try {
          await a.readAlerts();
        } catch (_) {}
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final items = list?.items ?? const <Note>[];
    return SafeArea(
      child: RefreshIndicator(
        color: C.go,
        backgroundColor: C.surface,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            const Align(alignment: Alignment.centerLeft, child: Wordmark()),
            const SizedBox(height: 30),
            Text(widget.alerts ? 'Alerts' : 'Messages', style: displayStyle(44)),
            const SizedBox(height: 10),
            Text(
              widget.alerts ? 'New matches and messages show up here.' : 'Talk with the people you connected with.',
              style: TextStyle(color: C.muted, fontSize: 17, height: 1.45),
            ),
            const SizedBox(height: 24),
            if (session.guest)
              _SignInPrompt(
                reason: widget.alerts
                    ? 'Sign in to see who you connected with.'
                    : 'Sign in to message the people you connect with.',
              )
            else if (error != null)
              ErrorNote(error)
            else if (list == null)
              const Padding(padding: EdgeInsets.all(24), child: Loading())
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  widget.alerts
                      ? 'Nothing yet. When you connect with someone at an event, it shows up here.'
                      : 'Nothing yet. Once you match with someone, you can message them here.',
                  style: TextStyle(color: C.muted),
                ),
              )
            else
              for (final n in items)
                _NoteRow(
                  note: n,
                  alerts: widget.alerts,
                  onTap: () {
                    final person = Uri.encodeComponent(n.other);
                    context.push(widget.alerts && n.isMatch
                        ? '/e/${n.eventId}/m/$person'
                        : '/chat/${n.eventId}/$person');
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.alerts, required this.onTap});
  final Note note;
  final bool alerts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = alerts ? note.alertUnread : note.chatUnread;
    final String title;
    final String line;
    if (alerts) {
      title = note.isMatch ? 'You matched with ${note.name}' : '${note.name} sent a message';
      line = note.isMatch ? 'Say hi in Messages.' : note.preview;
    } else {
      title = note.name;
      line = note.preview.isEmpty ? 'Matched. Say hi.' : note.preview;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: onTap,
        child: Row(children: [
          Avatar(name: note.name, url: note.photoURL, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.w600 : FontWeight.w500),
              ),
              const SizedBox(height: 3),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted, fontSize: 14)),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(ago(note.at), style: TextStyle(color: C.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: unread ? C.go : Colors.transparent, shape: BoxShape.circle),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        decoration: BoxDecoration(
          color: C.goSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: C.go.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Expanded(child: Text(reason, style: const TextStyle(fontSize: 15, height: 1.35))),
          TextButton(onPressed: () => askToSignIn(context, reason: reason), child: const Text('Sign in')),
        ]),
      );
}
