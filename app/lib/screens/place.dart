import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import '../data/check_in.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// A place's page: photos, hours, phone and website from Google, who's checked in there today, and
/// a check-in. Guests can look.
class PlaceScreen extends StatefulWidget {
  const PlaceScreen({super.key, required this.placeId});
  final String placeId;

  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  PlacePage? page;
  String? loadError;
  bool notFound = false;
  bool busy = false;
  String? error;

  Api get api => SessionScope.of(context).api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final p = await api.placePage(widget.placeId, dayKey(DateTime.now()));
      if (!mounted) return;
      setState(() {
        page = p;
        loadError = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        notFound = e.status == 404;
        loadError = e.message;
      });
    }
  }

  Future<void> _checkIn(PlacePage p) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await checkInToPlace(api, label: p.asPlace.label, place: p.asPlace);
      if (mounted) context.push('/e/$id');
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final p = page;
    final Widget body;
    if (p != null) {
      body = _content(p);
    } else if (loadError != null) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: EmptyState(
          title: notFound ? 'No such place' : "Can't load this",
          text: notFound ? 'Pick the place again from check-in.' : loadError!,
          action: notFound ? null : FilledButton(onPressed: _load, child: const Text('Try again')),
        ),
      );
    } else {
      body = const Loading();
    }
    return Scaffold(appBar: AppBar(), body: body);
  }

  Widget _content(PlacePage p) {
    final room = p.room;
    final inRoom = room?.checkedIn == true;
    final count = room?.count ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        if (p.photos.isNotEmpty) ...[_PhotoStrip(photos: p.photos, onOpen: _open), const SizedBox(height: 22)],
        Text('PLACE', style: eyebrow.copyWith(letterSpacing: 2.2)),
        const SizedBox(height: 10),
        Text(p.name, style: displayStyle(40)),
        if (p.address.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(p.address, style: const TextStyle(color: C.muted, fontSize: 16, height: 1.4)),
        ],
        if (p.rating != null) ...[
          const SizedBox(height: 10),
          Text(
            '★ ${p.rating!.toStringAsFixed(1)} · ${NumberFormat.decimalPattern().format(p.ratingCount)} ratings on Google',
            style: const TextStyle(color: C.muted, fontSize: 14),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: busy
              ? null
              : inRoom
              ? () => context.push('/e/${room!.id}')
              : () => _checkIn(p),
          child: busy ? const ButtonProgress() : Text(inRoom ? 'Open your room' : 'Check in here'),
        ),
        if (count > 0) ...[
          const SizedBox(height: 10),
          Text(
            count == 1 ? '1 person checked in here today' : '$count people checked in here today',
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.muted, fontSize: 14),
          ),
        ],
        ErrorNote(error),
        if (p.hours.isNotEmpty) ...[const SizedBox(height: 22), _Hours(hours: p.hours, today: p.today)],
        if (p.phone.isNotEmpty || p.website.isNotEmpty || p.mapsUri.isNotEmpty) ...[
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (p.phone.isNotEmpty)
                _LinkButton(
                  icon: Icons.call_outlined,
                  label: 'Call',
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: p.phone.replaceAll(' ', ''))),
                ),
              if (p.website.isNotEmpty)
                _LinkButton(icon: Icons.language, label: 'Website', onTap: () => _open(p.website)),
              if (p.mapsUri.isNotEmpty)
                _LinkButton(icon: Icons.map_outlined, label: 'Google Maps', onTap: () => _open(p.mapsUri)),
            ],
          ),
        ],
        if (!p.google) ...[
          const SizedBox(height: 22),
          const Text(
            "No Google listing matched this place, so there are no photos or hours yet.",
            style: TextStyle(color: C.muted, fontSize: 14),
          ),
        ],
        const SizedBox(height: 28),
        const Text('Photos and details from Google Maps.', style: TextStyle(color: C.muted, fontSize: 12)),
      ],
    );
  }
}

/// The photos, in black and white like the people's, with each photographer's credit under them.
class _PhotoStrip extends StatefulWidget {
  const _PhotoStrip({required this.photos, required this.onOpen});
  final List<PlacePhoto> photos;
  final void Function(String url) onOpen;

  @override
  State<_PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<_PhotoStrip> {
  int at = 0;

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[at];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 260,
            child: PageView.builder(
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => at = i),
              itemBuilder: (_, i) => ColorFiltered(
                colorFilter: grayscale,
                child: Image.network(
                  widget.photos[i].url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(color: C.soft),
                ),
              ),
            ),
          ),
        ),
        if (photo.author.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: photo.authorUri.isEmpty ? null : () => widget.onOpen(photo.authorUri),
            child: Text('Photo: ${photo.author}', style: const TextStyle(color: C.muted, fontSize: 12)),
          ),
        ],
      ],
    );
  }
}

/// Today's hours on the row, the rest behind a tap.
class _Hours extends StatelessWidget {
  const _Hours({required this.hours, required this.today});
  final List<String> hours;
  final int? today;

  @override
  Widget build(BuildContext context) {
    final now = today != null && today! < hours.length ? today : null;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: C.muted,
          collapsedIconColor: C.muted,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Text(now != null ? hours[now] : 'Opening hours', style: const TextStyle(fontSize: 15)),
          children: [
            for (var i = 0; i < hours.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  hours[i],
                  style: TextStyle(
                    fontSize: 15,
                    color: i == now ? C.ink : C.muted,
                    fontWeight: i == now ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 18, color: C.ink),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
    ),
  );
}
