import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../data/location.dart';
import '../logic/geo_when.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/place_field.dart';
import '../widgets/ui.dart';

/// Check in to a place that isn't an event: a café, a coworking space, a venue. Everyone who
/// checks in at the same place on the same day lands in the same room. Guests can check in.
class CheckInScreen extends StatelessWidget {
  const CheckInScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(), body: const CheckInView(showHeader: false));
}

class CheckInView extends StatefulWidget {
  const CheckInView({super.key, this.showHeader = true});
  final bool showHeader;
  @override
  State<CheckInView> createState() => _CheckInViewState();
}

class _CheckInViewState extends State<CheckInView> {
  final place = TextEditingController();
  PlaceDetails? picked;
  Fix? fix;
  List<PlaceDetails>? nearby;
  bool locating = false;
  bool pending = false;
  String? error;

  @override
  void dispose() {
    place.dispose();
    super.dispose();
  }

  Future<void> _findNearby() async {
    setState(() {
      locating = true;
      error = null;
    });
    final here = await currentFix();
    if (!mounted) return;
    if (here == null) {
      setState(() {
        locating = false;
        error = "Couldn't get your location. Allow location for Sidekick in Settings, or type the place.";
      });
      return;
    }
    final list = await SessionScope.of(context).api.nearby(here.lat, here.lng);
    if (!mounted) return;
    setState(() {
      fix = here;
      nearby = list;
      locating = false;
    });
  }

  void _pick(PlaceDetails p) {
    final label = p.label.length > 140 ? p.label.substring(0, 140) : p.label;
    setState(() {
      place.text = label;
      picked = p;
      nearby = null;
    });
  }

  Future<void> _checkIn() async {
    if (place.text.trim().isEmpty) return;
    setState(() {
      pending = true;
      error = null;
    });
    final api = SessionScope.of(context).api;
    try {
      // We only need your location if we know where the place is.
      if (fix == null && picked != null) fix = await currentFix();
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      String two(int n) => n.toString().padLeft(2, '0');
      final id = await api.checkIn({
        'place': place.text.trim(),
        if (picked != null) 'placeId': picked!.placeId,
        if (picked?.lat != null && picked?.lng != null) ...{'lat': picked!.lat, 'lng': picked!.lng},
        'day': '${now.year}${two(now.month)}${two(now.day)}',
        'dayStart': dayStart.toUtc().toIso8601String(),
        if (fix != null) 'fix': {'lat': fix!.lat, 'lng': fix!.lng, 'accuracy': fix!.accuracy},
      });
      if (mounted) context.push('/e/$id');
    } on ApiError catch (e) {
      if (e.needsLocation) {
        final here = await currentFix();
        if (here != null && mounted) {
          fix = here;
          setState(() => pending = false);
          return _checkIn();
        }
      }
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            if (widget.showHeader) ...[
              const Align(alignment: Alignment.centerLeft, child: Wordmark()),
              const SizedBox(height: 30),
            ],
            Text('Check in to a place', style: displayStyle(40)),
            const SizedBox(height: 10),
            Text(
              'At a coworking space, a café or a venue with no event page? Check in, and your sidekick scouts '
              'everyone else checked in there today.',
              style: TextStyle(color: C.muted, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: locating ? null : _findNearby,
              icon: locating
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.go))
                  : Icon(Icons.my_location, color: C.go),
              label: Text(locating ? 'Finding places near you…' : 'Use my location'),
            ),
            if (nearby != null && nearby!.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No places found nearby. Type the name below.', style: TextStyle(color: C.muted)),
              ),
            if (nearby != null && nearby!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final p in nearby!)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text(
                        [
                          if (fix != null && p.lat != null)
                            formatDistance(distanceM(fix!, LatLng(p.lat!, p.lng!))),
                          p.address,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: TextStyle(color: C.muted),
                      ),
                      onTap: () => _pick(p),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 18),
            PlaceField(
              controller: place,
              label: 'Where are you?',
              hint: 'Common Ground, Bukit Bintang',
              onPicked: (p) => setState(() => picked = p),
            ),
            ErrorNote(error),
            const SizedBox(height: 18),
            ValueListenableBuilder(
              valueListenable: place,
              builder: (_, v, _) => FilledButton(
                onPressed: pending || v.text.trim().isEmpty ? null : _checkIn,
                child: pending ? const ButtonProgress() : const Text('Check in here'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When we know where the place is, you need to be there to check in. Your location is only used for that check.',
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
            const SizedBox(height: 22),
            Center(
              child: TextButton(
                onPressed: () => context.push('/new'),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Going to an event instead? ', style: TextStyle(color: C.muted)),
                  TextSpan(text: 'Add the event', style: TextStyle(color: C.go, fontWeight: FontWeight.w500)),
                ])),
              ),
            ),
          ],
        ),
      );
}
