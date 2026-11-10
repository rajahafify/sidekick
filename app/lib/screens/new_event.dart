import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../logic/geo_when.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/dots.dart';
import '../widgets/place_field.dart';
import '../widgets/ui.dart';

/// Add an event: paste its page (Meetup, Eventbrite...) to fill it in, or type it.
class NewEventScreen extends StatefulWidget {
  const NewEventScreen({super.key});
  @override
  State<NewEventScreen> createState() => _NewEventScreenState();
}

class _NewEventScreenState extends State<NewEventScreen> {
  final link = TextEditingController();
  final name = TextEditingController();
  final place = TextEditingController();
  PlaceDetails? picked;
  DateTime? start;
  DateTime? end;
  String? sourceUrl;
  bool importing = false;
  bool saving = false;
  String? importError;
  String? error;

  @override
  void dispose() {
    link.dispose();
    name.dispose();
    place.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final url = link.text.trim();
    if (url.isEmpty) return;
    setState(() {
      importing = true;
      importError = null;
    });
    try {
      final e = await SessionScope.of(context).api.importEvent(url.startsWith('http') ? url : 'https://$url');
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      toast(context, 'Filled in from the link. Check it, then add it.');
      setState(() {
        name.text = e.name;
        if (e.place.isNotEmpty) place.text = e.place.length > 140 ? e.place.substring(0, 140) : e.place;
        start = e.startsAt;
        end = e.endsAt;
        sourceUrl = e.url;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => importError = e.message);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final base = initial ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Give the event a name.');
      return;
    }
    if (start != null && end != null && !end!.isAfter(start!)) {
      setState(() => error = 'The end must be after the start.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await SessionScope.of(context).api.createEvent({
        'name': name.text.trim(),
        'place': place.text.trim(),
        if (picked != null) 'placeId': picked!.placeId,
        if (picked?.lat != null && picked?.lng != null) ...{'lat': picked!.lat, 'lng': picked!.lng},
        'startsAt': start?.toUtc().toIso8601String(),
        'endsAt': end?.toUtc().toIso8601String(),
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
      });
      if (mounted) context.pushReplacement('/e/$id?share=1');
    } on ApiError catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const BackBar(),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
          children: [
            const PageTitle(
              'Add an event',
              text: 'Add it once. Everyone who opens its link or scans its code lands in the same room.',
            ),
            const SizedBox(height: 24),
            SurfaceCard(
              color: C.goSoft,
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const SidekickMark(size: 14, mood: BuddyMood.wink),
                  const SizedBox(width: 8),
                  Text('HAVE A LINK?', style: eyebrow.copyWith(fontSize: 11)),
                ]),
                const SizedBox(height: 8),
                const Text('Let your sidekick fill this in', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextField(
                      controller: link,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(hintText: 'Paste the event link', fillColor: C.paper),
                      onSubmitted: (_) => _import(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(92, 54)),
                      onPressed: importing ? null : _import,
                      child: importing ? const ButtonProgress() : const Text('Import'),
                    ),
                  ),
                ]),
                if (importError != null) ErrorNote(importError),
                const SizedBox(height: 10),
                Text('Works with Luma, Meetup, Eventbrite and most event pages.',
                    style: TextStyle(color: C.muted, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 26),
            const SectionLabel('Or fill it in'),
            TextField(
              controller: name,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Event name', counterText: ''),
            ),
            const SizedBox(height: 12),
            PlaceField(controller: place, onPicked: (p) => setState(() => picked = p)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _WhenButton(
                  label: 'Starts',
                  value: start,
                  onTap: () async {
                    final d = await _pickDateTime(start);
                    if (d != null) setState(() => start = d);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WhenButton(
                  label: 'Ends',
                  value: end,
                  onTap: () async {
                    final d = await _pickDateTime(end ?? start?.add(const Duration(hours: 3)));
                    if (d != null) setState(() => end = d);
                  },
                ),
              ),
            ]),
            if (start == null)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 4),
                child: Text(
                  'Add a start time so people know when the room opens.',
                  style: TextStyle(color: C.muted, fontSize: 13),
                ),
              ),
            ErrorNote(error),
            const SizedBox(height: 24),
            FilledButton(onPressed: saving ? null : _save, child: saving ? const ButtonProgress() : const Text('Add event')),
          ],
        ),
      );
}

class _WhenButton extends StatelessWidget {
  const _WhenButton({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            value == null ? 'Set a time' : eventWhen(value, null),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: value == null ? C.muted : C.ink),
          ),
        ]),
      );
}
