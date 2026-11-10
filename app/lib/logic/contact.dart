/// Where a LinkedIn contact detail opens: a full LinkedIn address as it is, or a bare handle as
/// a profile page. Null for a link to anywhere else, which is never opened (it's shown as text),
/// so a contact field can't send a match to another site.
Uri? linkedinUri(String value) {
  final s = value.trim();
  if (s.isEmpty) return null;
  if (s.contains('/') || s.contains('.')) {
    final u = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http')) return null;
    final host = u.host.toLowerCase();
    if (host != 'linkedin.com' && !host.endsWith('.linkedin.com')) return null;
    return u.replace(scheme: 'https');
  }
  final handle = s.startsWith('@') ? s.substring(1) : s;
  if (!RegExp(r'^[A-Za-z0-9_-]{2,100}$').hasMatch(handle)) return null;
  return Uri.https('www.linkedin.com', '/in/$handle');
}

/// A WhatsApp chat with a phone number, or null when there aren't enough digits to be one.
Uri? whatsappUri(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length < 7 ? null : Uri.https('wa.me', '/$digits');
}

/// An email to an address, or null when it isn't one.
Uri? emailUri(String email) {
  final s = email.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? Uri(scheme: 'mailto', path: s) : null;
}
