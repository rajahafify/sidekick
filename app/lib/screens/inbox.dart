import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../logic/chat.dart';
import '../logic/sidekick.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/contact.dart';
import '../widgets/mark.dart';
import '../widgets/sign_in_sheet.dart';
import '../widgets/ui.dart';

export '../logic/chat.dart' show ago;

/// The Alerts screen: new matches and messages, newest first.
class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key, this.active = true});
  final bool active;
  @override
  Widget build(BuildContext context) => _Inbox(alerts: true, active: active);
}

/// The Messages tab: the conversations you have with your matches, newest first.
class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key, this.active = true});
  final bool active;
  @override
  Widget build(BuildContext context) => _Inbox(alerts: false, active: active);
}

/// The frame every list tab shares: the wordmark, a serif title and a line, then the list.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.title, required this.text, required this.onRefresh, required this.children, this.back = false});
  final String title;
  final String text;
  final Future<void> Function() onRefresh;
  final List<Widget> children;

  /// Shows a back button to Events instead of the wordmark, for a screen that isn't on the bar.
  final bool back;

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: C.brand,
          backgroundColor: C.surface,
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
            children: [
              SizedBox(
                height: 42,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: back
                      ? RoundIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back to events', onTap: () => context.go('/'))
                      : const Wordmark(),
                ),
              ),
              const SizedBox(height: 30),
              PageTitle(title, text: text, size: 44),
              const SizedBox(height: 22),
              ...children,
            ],
          ),
        ),
      );
}

class _SignInFirst extends StatelessWidget {
  const _SignInFirst({required this.title, required this.reason});
  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) => EmptyState(
        mood: BuddyMood.normal,
        title: title,
        text: reason,
        action: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(180, 50)),
          onPressed: () => askToSignIn(context, reason: reason),
          child: const Text('Sign in'),
        ),
      );
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        mood: BuddyMood.normal,
        title: 'Can’t load this',
        text: error,
        action: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(160, 50)),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      );
}

/// The People tab: everyone you've connected with, across events, so you needn't connect again.
class ConnectedTab extends StatefulWidget {
  const ConnectedTab({super.key, this.active = true});
  final bool active;
  @override
  State<ConnectedTab> createState() => _ConnectedTabState();
}

class _ConnectedTabState extends State<ConnectedTab> {
  final _search = TextEditingController();
  ConnectionList? list;
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

  @override
  void didUpdateWidget(ConnectedTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !SessionScope.of(context).guest) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final a = api;
    if (a == null || loading) return;
    loading = true;
    try {
      final r = await a.connections();
      if (!mounted) return;
      setState(() {
        list = r;
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      loading = false;
    }
  }

  void _open(Connection c) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => _ConnectionSheet(
          connection: c,
          onMessage: () {
            Navigator.of(sheet).pop();
            context.push('/chat/${c.eventId}/${Uri.encodeComponent(c.uid)}');
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final all = list?.items ?? const <Connection>[];
    final q = _search.text.trim().toLowerCase();
    final items = q.isEmpty
        ? all
        : all.where((c) => '${c.name} ${c.headline} ${c.eventName}'.toLowerCase().contains(q)).toList();
    return _TabPage(
      title: 'People',
      text: 'Everyone you’ve connected with. Reach them here, at any event.',
      onRefresh: _load,
      children: [
        if (session.guest)
          const _SignInFirst(title: 'Your people live here', reason: 'Sign in to connect, and keep everyone you meet in one place.')
        else if (error != null && list == null)
          _LoadFailed(error: error!, onRetry: _load)
        else if (list == null)
          const SkeletonRows(count: 4)
        else if (all.isEmpty)
          const EmptyState(
            mood: BuddyMood.normal,
            title: 'Nobody yet',
            text: 'When you and someone both connect at an event, they stay here, so you never have to connect twice.',
          )
        else ...[
          if (all.length > 5) ...[
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search ${all.length} people',
                prefixIcon: Icon(Icons.search_rounded, color: C.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Nobody matches “${_search.text.trim()}”.', style: TextStyle(color: C.muted, fontSize: 15)),
            ),
          for (final c in items)
            _Row(
              name: c.name,
              photoURL: c.photoURL,
              seed: c.uid,
              line: c.eventName.isEmpty ? c.headline : 'Met at ${c.eventName}',
              time: ago(c.matchedAt),
              onTap: () => _open(c),
            ),
        ],
      ],
    );
  }
}

/// A connection's details: where you met, how to reach them, and a button to message them.
class _ConnectionSheet extends StatelessWidget {
  const _ConnectionSheet({required this.connection, required this.onMessage});
  final Connection connection;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final c = connection;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(name: c.name, url: c.photoURL, seed: c.uid, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: displayStyle(30)),
                if (c.headline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(c.headline, style: TextStyle(color: C.muted, fontSize: 15, height: 1.3)),
                ],
              ]),
            ),
          ]),
          if (c.eventName.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.handshake_outlined, size: 17, color: C.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Met at ${c.eventName}${c.matchedAt == null ? '' : ' · ${ago(c.matchedAt)}'}',
                  style: TextStyle(color: C.muted, fontSize: 14.5),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 18),
          ContactLinks(contact: c.contact),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
            label: Text('Message ${firstName(c.name)}'),
          ),
        ]),
      ),
    );
  }
}

class _Inbox extends StatefulWidget {
  const _Inbox({required this.alerts, required this.active});
  final bool alerts;
  final bool active;
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
    // Alerts are marked read when they load, so they only load once the screen is really open.
    if (list == null && error == null && !session.guest && (widget.active || !widget.alerts)) _load();
  }

  @override
  void didUpdateWidget(_Inbox old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !SessionScope.of(context).guest) _load();
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

  Future<void> _open(Note n, {bool match = false}) async {
    final person = Uri.encodeComponent(n.other);
    await context.push(match ? '/e/${n.eventId}/m/$person' : '/chat/${n.eventId}/$person');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final items = list?.items ?? const <Note>[];
    // In Messages, matches nobody has written to yet sit in a strip on top, like new arrivals.
    final fresh = widget.alerts ? const <Note>[] : items.where((n) => n.preview.isEmpty).toList();
    final talks = widget.alerts ? items : items.where((n) => n.preview.isNotEmpty).toList();
    return _TabPage(
      back: widget.alerts,
      title: widget.alerts ? 'Alerts' : 'Messages',
      text: widget.alerts ? 'New matches and messages, as they happen.' : 'Talk with the people you matched with.',
      onRefresh: _load,
      children: [
        if (session.guest)
          _SignInFirst(
            title: widget.alerts ? 'Nothing to tell you yet' : 'Messages need an account',
            reason: widget.alerts
                ? 'Sign in to connect with people. Your matches show up here.'
                : 'Sign in to connect with people and message your matches.',
          )
        else if (error != null && list == null)
          _LoadFailed(error: error!, onRetry: _load)
        else if (list == null)
          const SkeletonRows(count: 4)
        else if (items.isEmpty)
          EmptyState(
            mood: BuddyMood.normal,
            title: widget.alerts ? 'All quiet' : 'No conversations yet',
            text: widget.alerts
                ? 'When someone connects back, or writes to you, you’ll see it here.'
                : 'Once you match with someone at an event, you can message them here.',
            action: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(180, 50)),
              onPressed: () => context.go('/'),
              child: const Text('Find an event'),
            ),
          )
        else ...[
          if (fresh.isNotEmpty) ...[
            const SectionLabel('New matches'),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: fresh.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _FreshMatch(note: fresh[i], onTap: () => _open(fresh[i])),
              ),
            ),
            const SizedBox(height: 18),
            if (talks.isNotEmpty) const SectionLabel('Conversations'),
          ],
          for (final n in talks)
            if (widget.alerts)
              _Row(
                name: n.name,
                photoURL: n.photoURL,
                seed: n.other,
                line: n.isMatch ? 'You matched. Say hi at the break.' : n.preview,
                time: ago(n.at),
                unread: n.alertUnread,
                badge: n.isMatch ? Icons.handshake_rounded : Icons.chat_bubble_rounded,
                onTap: () => _open(n, match: n.isMatch),
              )
            else
              _Row(
                name: n.name,
                photoURL: n.photoURL,
                seed: n.other,
                line: n.preview,
                time: ago(n.at),
                unread: n.chatUnread,
                onTap: () => _open(n),
              ),
        ],
      ],
    );
  }
}

/// A new match in the strip on top of Messages: a face with a Signal ring.
class _FreshMatch extends StatelessWidget {
  const _FreshMatch({required this.note, required this.onTap});
  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Say hi to ${note.name}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 76,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(color: signal, shape: BoxShape.circle),
                child: Avatar(name: note.name, url: note.photoURL, seed: note.other, size: 64, ring: C.paper),
              ),
              const SizedBox(height: 8),
              Text(
                firstName(note.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ),
      );
}

/// One person in a list: their face, a name or headline, a line under it, and when.
class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.photoURL,
    required this.seed,
    required this.line,
    required this.time,
    required this.onTap,
    this.unread = false,
    this.badge,
  });
  final String name;
  final String photoURL;
  final String seed;

  final String line;
  final String time;
  final bool unread;

  /// A small icon on the corner of the face, saying what kind of alert this is.
  final IconData? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Avatar(name: name, url: photoURL, seed: seed, size: 56),
              if (badge != null)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: C.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.paper, width: 2),
                    ),
                    child: Icon(badge, size: 11, color: C.onBrand),
                  ),
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16.5, fontWeight: unread ? FontWeight.w600 : FontWeight.w500),
                ),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: unread ? C.ink : C.muted, fontSize: 14.5),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(time, style: TextStyle(color: C.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: unread ? signal : Colors.transparent, shape: BoxShape.circle),
              ),
            ]),
          ]),
        ),
      );
}
