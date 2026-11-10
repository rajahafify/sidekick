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
  Widget build(BuildContext context) => const Scaffold(appBar: BackBar(), body: CheckInView(showHeader: false));
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
    FocusScope.of(context).unfocus();
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
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      String two(int n) => n.toString().padLeft(2, '0');
      final id = await api.checkIn({
        'place': place.text.trim(),
        if (picked != null) 'placeId': picked!.placeId,
        if (picked?.lat != null && picked?.lng != null) ...{'lat': picked!.lat, 'lng': picked!.lng},
        'day': '${now.year}${two(now.month)}${two(now.day)}',
        'dayStart': dayStart.toUtc().toIso8601String(),
      });
      if (mounted) {
        // The room opens checked in, and the form is clean for next time.
        place.clear();
        setState(() {
          picked = null;
          nearby = null;
        });
        context.push('/e/$id');
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
          children: [
            if (widget.showHeader) ...[
              const SizedBox(height: 42, child: Align(alignment: Alignment.centerLeft, child: Wordmark())),
              const SizedBox(height: 30),
            ],
            const PageTitle(
              'Check in to a place',
              text: 'At a coworking space, a café or a venue with no event page? Check in, and your sidekick '
                  'scouts everyone else who checked in there today.',
            ),
            const SizedBox(height: 24),
            PlaceField(
              controller: place,
              label: 'Where are you?',
              hint: 'Common Ground, Bukit Bintang',
              onPicked: (p) => setState(() => picked = p),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: locating ? null : _findNearby,
                icon: locating
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink))
                    : Icon(Icons.near_me_outlined, size: 18, color: C.ink),
                label: Text(locating ? 'Finding places near you…' : 'Find places near me'),
              ),
            ),
            if (nearby != null && nearby!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text('No places found nearby. Type the name above.', style: TextStyle(color: C.muted)),
              ),
            if (nearby != null && nearby!.isNotEmpty) ...[
              const SizedBox(height: 6),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  for (final p in nearby!)
                    ListTile(
                      leading: Icon(Icons.place_outlined, color: C.muted, size: 21),
                      title: Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        [
                          if (fix != null && p.lat != null)
                            formatDistance(distanceM(fix!, LatLng(p.lat!, p.lng!))),
                          p.address,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: C.muted, fontSize: 13.5),
                      ),
                      onTap: () => _pick(p),
                    ),
                ]),
              ),
            ],
            ErrorNote(error),
            const SizedBox(height: 18),
            ValueListenableBuilder(
              valueListenable: place,
              builder: (_, v, _) => FilledButton(
                onPressed: pending || v.text.trim().isEmpty ? null : _checkIn,
                child: pending ? const ButtonProgress() : const Text('Check in here'),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: () => context.push('/new'),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Going to an event instead? ', style: TextStyle(color: C.muted, fontWeight: FontWeight.w400)),
                  TextSpan(
                    text: 'Add the event',
                    style: TextStyle(color: C.ink, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                  ),
                ])),
              ),
            ),
          ],
        ),
      );
}
