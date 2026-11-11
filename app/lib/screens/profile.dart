import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/api.dart';
import '../logic/image.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/mark.dart';
import '../widgets/ui.dart';

/// Your profile: what your sidekick tells other sidekicks, and your contact details, which are
/// only shared when you both connect. Guests fill this in too.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.next});
  final String? next;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, headline, about, linkedin, email, phone;
  late List<String> lookingFor, offering;
  late String photo;
  bool saving = false;
  bool uploading = false;
  String? error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = SessionScope.of(context);
    final p = s.profile;
    name = TextEditingController(text: p?.displayName.isNotEmpty == true ? p!.displayName : s.googleName);
    headline = TextEditingController(text: p?.headline ?? '');
    about = TextEditingController(text: p?.about ?? '');
    linkedin = TextEditingController(text: p?.contact.linkedin ?? '');
    // Google already knows your email: start from it, so nobody has to type it.
    email = TextEditingController(text: p?.contact.email.isNotEmpty == true ? p!.contact.email : s.googleEmail);
    phone = TextEditingController(text: p?.contact.phone ?? '');
    lookingFor = [...?p?.lookingFor];
    offering = [...?p?.offering];
    photo = p?.photoURL.isNotEmpty == true ? p!.photoURL : s.googlePhoto;
  }

  @override
  void dispose() {
    for (final c in [name, headline, about, linkedin, email, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Picks a photo, uploads it, and makes it the one Save keeps. The server only keeps an upload
  /// while the link it's sent with is the one it gave out, so `photo` has to follow the upload.
  Future<void> _changePhoto() async {
    final session = SessionScope.of(context);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final type = imageType(bytes);
    if (type == null) {
      if (mounted) toast(context, 'Choose a JPEG, PNG or WebP photo.');
      return;
    }
    setState(() => uploading = true);
    try {
      final url = await session.api.uploadPhoto(bytes, type);
      if (!mounted) return;
      setState(() => photo = url);
      await session.reloadProfile();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final contact = Contact(linkedin: linkedin.text, email: email.text, phone: phone.text);
    if (contact.isEmpty) {
      setState(() => error = 'Add at least one way to reach you. Only people you match with see it.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final session = SessionScope.of(context);
    try {
      await session.api.saveProfile(Profile(
        displayName: name.text,
        photoURL: photo,
        headline: headline.text,
        lookingFor: lookingFor,
        offering: offering,
        about: about.text,
        contact: contact,
      ));
      await session.reloadProfile();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(widget.next ?? '/');
      }
    } on ApiError catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final first = session.profile?.onboarded != true;
    return Scaffold(
      appBar: first
          ? AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 60,
              title: const Wordmark(size: 22),
              actions: [
                TextButton(onPressed: session.signOut, child: Text('Cancel', style: TextStyle(color: C.muted))),
                const SizedBox(width: 8),
              ],
            )
          : const BackBar(title: Padding(padding: EdgeInsets.only(left: 12), child: Text('Your profile'))),
      // The main button stays in view, so the form never needs scrolling to reach it.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ErrorNote(error),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: saving ? null : _save,
              child: saving ? const ButtonProgress() : Text(first ? 'Done' : 'Save'),
            ),
            if (first) ...[
              const SizedBox(height: 8),
              Text(
                'Only people you match with see your contact details.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted, fontSize: 12.5),
              ),
            ],
          ]),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (first) ...[
              Row(children: [
                const SidekickMark(size: 14, mood: BuddyMood.wink),
                const SizedBox(width: 8),
                Text('YOUR SIDEKICK', style: eyebrow),
              ]),
              const SizedBox(height: 12),
              const PageTitle(
                'Brief your sidekick',
                text: 'It uses this to find the people worth your time, and to pitch you to theirs.',
              ),
              const SizedBox(height: 26),
            ],
            Center(
              child: Semantics(
                button: true,
                label: 'Change photo',
                child: GestureDetector(
                  onTap: uploading ? null : _changePhoto,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Opacity(opacity: uploading ? 0.5 : 1, child: Avatar(name: name.text, url: photo, size: 104)),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: C.brand,
                          shape: BoxShape.circle,
                          border: Border.all(color: C.paper, width: 3),
                        ),
                        child: uploading
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: CircularProgressIndicator(strokeWidth: 2, color: C.onBrand),
                              )
                            : Icon(Icons.photo_camera_outlined, size: 16, color: C.onBrand),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: uploading ? null : _changePhoto,
                child: Text(
                  uploading ? 'Uploading…' : (photo.isEmpty ? 'Add a photo' : 'Change photo'),
                  style: TextStyle(color: C.muted, fontSize: 14.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Your name', counterText: ''),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Add your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: headline,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'What you do', hintText: 'Founder at a fintech startup', counterText: ''),
            ),
            const SizedBox(height: 26),
            _TagPicker(
              title: "You're looking for",
              selected: lookingFor,
              onChanged: (v) => setState(() => lookingFor = v),
            ),
            const SizedBox(height: 22),
            _TagPicker(title: 'You can offer', selected: offering, onChanged: (v) => setState(() => offering = v)),
            const SizedBox(height: 22),
            TextFormField(
              controller: about,
              maxLength: 200,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Anything else your sidekick should know',
                hintText: 'Raising a seed round, looking for a technical cofounder…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 30),
            Text('HOW TO REACH YOU', style: caps),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: C.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Hidden until you both connect. Add at least one.', style: TextStyle(color: C.muted, fontSize: 14)),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: linkedin,
              maxLength: 200,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'LinkedIn', hintText: 'linkedin.com/in/you', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: email,
              maxLength: 120,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                helperText: session.googleEmail.isEmpty ? null : 'From your Google account',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phone,
              maxLength: 40,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone or WhatsApp', counterText: ''),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagPicker extends StatelessWidget {
  const _TagPicker({required this.title, required this.selected, required this.onChanged});
  final String title;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            Text(
              selected.isEmpty ? 'Pick up to $maxTags' : '${selected.length} of $maxTags',
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in networkTags)
                _Choice(
                  label: t,
                  on: selected.contains(t),
                  // At the limit, the rest fade: one has to come off before another goes on.
                  enabled: selected.contains(t) || selected.length < maxTags,
                  onTap: () {
                    final on = !selected.contains(t);
                    if (on && selected.length >= maxTags) return;
                    HapticFeedback.selectionClick();
                    onChanged(on ? [...selected, t] : selected.where((x) => x != t).toList());
                  },
                ),
            ],
          ),
        ],
      );
}

/// One tag in a picker: filled with the main colour when picked.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.on, required this.enabled, required this.onTap});
  final String label;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: on ? C.brand : C.surface, borderRadius: BorderRadius.circular(99)),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.1,
                fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                color: on ? C.onBrand : (enabled ? C.ink : C.muted.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
      );
}
