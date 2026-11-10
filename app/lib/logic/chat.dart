import 'package:intl/intl.dart';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// The label over a day's messages: "Today", "Yesterday", or "Tue, 4 Nov".
String dayLabel(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  if (sameDay(t, n)) return 'Today';
  if (sameDay(t, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  return DateFormat(t.year == n.year ? 'EEE, d MMM' : 'd MMM y').format(t);
}

/// Short, human time for the lists: "now", "12 min", "3 h", "Tue", "4 Nov".
String ago(DateTime? t, [DateTime? now]) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inDays < 1) return '${d.inHours} h';
  if (d.inDays < 7) return DateFormat('EEE').format(t);
  return DateFormat('d MMM').format(t);
}
