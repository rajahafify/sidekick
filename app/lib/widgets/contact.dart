import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/contact.dart';
import '../models.dart';
import '../theme.dart';
import 'ui.dart';

/// A match's contact details: tap one to open it (LinkedIn, an email, WhatsApp), or the copy
/// button to copy it.
class ContactLinks extends StatelessWidget {
  const ContactLinks({super.key, required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (contact.linkedin.trim().isNotEmpty)
        _ContactRow(icon: Icons.work_outline_rounded, label: 'LinkedIn', value: contact.linkedin.trim(), uri: linkedinUri(contact.linkedin)),
      if (contact.email.trim().isNotEmpty)
        _ContactRow(icon: Icons.mail_outline_rounded, label: 'Email', value: contact.email.trim(), uri: emailUri(contact.email)),
      if (contact.phone.trim().isNotEmpty)
        _ContactRow(icon: Icons.phone_outlined, label: 'Phone or WhatsApp', value: contact.phone.trim(), uri: whatsappUri(contact.phone)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(indent: 62, color: C.line),
          rows[i],
        ],
      ]),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.value, required this.uri});
  final IconData icon;
  final String label;
  final String value;

  /// Where a tap goes, or null when the value can only be copied.
  final Uri? uri;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: value));
    toast(context, '$label copied');
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final u = uri;
          if (u == null) return _copy(context);
          final ok = await launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) => false);
          if (!ok && context.mounted) _copy(context);
        },
        onLongPress: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 13, 8, 13),
          child: Row(children: [
            Icon(icon, size: 22, color: C.ink),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(color: C.muted, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ]),
            ),
            IconButton(
              tooltip: 'Copy',
              onPressed: () => _copy(context),
              icon: Icon(Icons.copy_rounded, size: 18, color: C.muted),
            ),
          ]),
        ),
      );
}
