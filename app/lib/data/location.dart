import 'package:geolocator/geolocator.dart';

import '../logic/geo_when.dart';

/// The device's location, or null if it's unavailable or the person says no.
Future<Fix?> currentFix() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
    );
    return Fix(p.latitude, p.longitude, p.accuracy);
  } catch (_) {
    return null;
  }
}
