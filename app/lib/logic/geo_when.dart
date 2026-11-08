import 'dart:math' as math;

import 'package:intl/intl.dart';

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

class Fix extends LatLng {
  const Fix(super.lat, super.lng, this.accuracy);
  final double accuracy;
}

/// Great-circle distance in metres.
double distanceM(LatLng a, LatLng b) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371000 * math.asin(math.sqrt(h));
}

String formatDistance(double m) {
  if (m < 1000) return '${(m / 10).round() * 10} m';
  return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';
}

/// "Thu, 5 Nov, 6:00 PM – 9:00 PM", "Thu, 5 Nov – Sat, 7 Nov", or "" when there's no date.
String eventWhen(DateTime? start, DateTime? end) {
  String day(DateTime d) => DateFormat('EEE, d MMM').format(d);
  String time(DateTime d) => DateFormat.jm().format(d);
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (start == null) return end != null ? 'Until ${day(end)}, ${time(end)}' : '';
  if (end == null) return '${day(start)}, ${time(start)}';
  if (sameDay(start, end)) return '${day(start)}, ${time(start)} – ${time(end)}';
  return '${day(start)} – ${day(end)}';
}

enum EventPhase { upcoming, live, ended, unknown }

/// Where an event is in time. Without an end, it counts as live for 6 hours after it starts.
EventPhase eventPhase(DateTime? start, DateTime? end, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final finish = end ?? start?.add(const Duration(hours: 6));
  if (finish != null && n.isAfter(finish)) return EventPhase.ended;
  if (start != null && n.isBefore(start)) return EventPhase.upcoming;
  return (start != null || end != null) ? EventPhase.live : EventPhase.unknown;
}
