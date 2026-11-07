import '../logic/geo_when.dart';
import '../models.dart';
import 'api.dart';
import 'location.dart';

/// The day on the phone's clock as yyyymmdd. A place's check-in room is one per day.
String dayKey(DateTime now) => '${now.year}${_two(now.month)}${_two(now.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// Checks in to a place and returns the id of its room. Everyone who checks in at the same place on
/// the same day shares that room. Location is only used for this check, when the server needs it.
Future<String> checkInToPlace(Api api, {required String label, PlaceDetails? place, Fix? fix}) async {
  final text = label.length > 140 ? label.substring(0, 140) : label;
  // We only need your location if we know where the place is.
  final here = fix ?? (place != null ? await currentFix() : null);
  try {
    return await api.checkIn(_checkInBody(text, place, here, DateTime.now()));
  } on ApiError catch (e) {
    if (!e.needsLocation) rethrow;
    final again = await currentFix();
    if (again == null) rethrow;
    return api.checkIn(_checkInBody(text, place, again, DateTime.now()));
  }
}

Map<String, dynamic> _checkInBody(String label, PlaceDetails? place, Fix? fix, DateTime now) {
  final dayStart = DateTime(now.year, now.month, now.day);
  return {
    'place': label,
    if (place != null) 'placeId': place.placeId,
    if (place?.lat != null && place?.lng != null) ...{'lat': place!.lat, 'lng': place.lng},
    'day': dayKey(now),
    'dayStart': dayStart.toUtc().toIso8601String(),
    if (fix != null) 'fix': {'lat': fix.lat, 'lng': fix.lng, 'accuracy': fix.accuracy},
  };
}
