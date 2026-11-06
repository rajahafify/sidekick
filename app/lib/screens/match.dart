import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../logic/sidekick.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/dots.dart';
import '../widgets/ui.dart';

/// A match: their contact details, and what the two sidekicks said about why you should talk.
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (m == null && error == null) _load();
  }

  Future<void> _load() async {
    try {
      final r = await SessionScope.of(context).api.match(widget.eventId, widget.other);
      if (mounted) setState(() => m = r);
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, "Couldn't open that.");
  }

  String _linkedinUrl(String v) {
    final s = v.trim();
    if (s.startsWith('http')) return s;
    if (s.contains('linkedin.com')) return 'https://$s';
    return 'https://www.linkedin.com/in/$s';
  }

  Future<void> _safety() async {
    final api = SessionScope.of(context).api;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.block), title: const Text('Block'), onTap: () => Navigator.pop(c, 'block')),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: C.danger),
            title: const Text('Report and block', style: TextStyle(color: C.danger)),
            onTap: () => Navigator.pop(c, 'report'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'report') {
        final reason = await _askReason();
        if (reason == null) return;
        await api.report(widget.other, widget.eventId, reason);
      }
      await api.block(widget.other);
      if (mounted) {
        toast(context, 'Blocked. They won’t see you again.');
        context.pop();
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<String?> _askReason() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('What happened?'),
        content: TextField(controller: c, maxLength: 500, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel', style: TextStyle(color: C.muted))),
          TextButton(
            onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? 'No reason given' : c.text.trim()),
            child: const Text('Report', style: TextStyle(color: C.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = m;
    return Scaffold(
      appBar: AppBar(actions: [if (d != null) IconButton(onPressed: _safety, icon: const Icon(Icons.more_horiz))]),
      body: d == null
          ? (error == null ? const Loading() : EmptyState(title: 'Not available', text: error!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                const Row(
                  children: [
                    SidekickMark(size: 16, mood: BuddyMood.happy),
                    SizedBox(width: 8),
                    Text("IT'S A MATCH", style: eyebrow),
                  ],
                ),
                const SizedBox(height: 16),
                Avatar(name: d.person.displayName, url: d.person.photoURL, size: 84),
                const SizedBox(height: 16),
                Text(d.person.displayName, style: displayStyle(40)),
                if (d.person.headline.isNotEmpty)
                  Text(d.person.headline, style: const TextStyle(color: C.muted, fontSize: 16)),
                const SizedBox(height: 22),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    if (d.contact.linkedin.isNotEmpty)
                      _ContactRow(icon: Icons.work_outline, label: 'LinkedIn', value: d.contact.linkedin, onTap: () => _open(_linkedinUrl(d.contact.linkedin))),
                    if (d.contact.email.isNotEmpty)
                      _ContactRow(icon: Icons.mail_outline, label: 'Email', value: d.contact.email, onTap: () => _open('mailto:${d.contact.email}')),
                    if (d.contact.phone.isNotEmpty)
                      _ContactRow(
                        icon: Icons.chat_outlined,
                        label: 'Phone',
                        value: d.contact.phone,
                        onTap: () => _open('https://wa.me/${d.contact.phone.replaceAll(RegExp(r'[^0-9]'), '')}'),
                      ),
                  ]),
                ),
                const SizedBox(height: 26),
                const Text('YOUR SIDEKICKS TALKED', style: eyebrow),
                const SizedBox(height: 12),
                for (final t in d.exchange.turns) _Bubble(mine: t.speaker != widget.other, text: t.text),
                const SizedBox(height: 14),
                Text(d.exchange.reason, style: const TextStyle(color: C.muted, fontSize: 15, height: 1.4)),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: C.goSoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: C.go.withValues(alpha: 0.35)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('OPEN WITH', style: eyebrow.copyWith(fontSize: 11)),
                    const SizedBox(height: 8),
                    Text('“${d.exchange.opener}”', style: displayStyle(26, style: FontStyle.italic)),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: d.exchange.opener));
                          toast(context, 'Copied');
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy'),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('Say hi to ${firstName(d.person.displayName)} at the break, or send a message.',
                    textAlign: TextAlign.center, style: const TextStyle(color: C.muted, fontSize: 14)),
              ],
            ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: C.go),
        title: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(label, style: const TextStyle(color: C.muted)),
        trailing: const Icon(Icons.open_in_new, color: C.muted, size: 18),
        onTap: onTap,
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.mine, required this.text});
  final bool mine;
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? C.soft : C.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            border: Border.all(color: C.line),
          ),
          child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35)),
        ),
      );
}
