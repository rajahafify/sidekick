import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
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
      appBar: AppBar(
        automaticallyImplyLeading: !first,
        title: Text(first ? '' : 'Your profile'),
        actions: [
          if (first)
            TextButton(onPressed: session.signOut, child: Text('Cancel', style: TextStyle(color: C.muted))),
        ],
      ),
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
          ]),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            if (first) ...[
              Text('YOUR SIDEKICK', style: eyebrow),
              const SizedBox(height: 10),
              Text('Brief your sidekick', style: displayStyle(40)),
              const SizedBox(height: 10),
              Text(
                'It uses this to find the people worth your time, and to pitch you to theirs.',
                style: TextStyle(color: C.muted, fontSize: 16),
              ),
              const SizedBox(height: 24),
            ],
            Row(children: [
              Avatar(name: name.text, url: photo, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Your name', counterText: ''),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Add your name' : null,
                ),
              ),
            ]),
            const SizedBox(height: 14),
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
            const SizedBox(height: 22),
            Text('HOW TO REACH YOU', style: eyebrow),
            const SizedBox(height: 6),
            Text('Only shared with people you both connect with.', style: TextStyle(color: C.muted, fontSize: 14)),
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
            Text('${selected.length}/$maxTags', style: TextStyle(color: C.muted, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in networkTags)
                FilterChip(
                  label: Text(t),
                  selected: selected.contains(t),
                  labelStyle: TextStyle(color: selected.contains(t) ? C.go : C.ink, fontSize: 14),
                  side: BorderSide(color: selected.contains(t) ? C.go.withValues(alpha: 0.6) : C.line),
                  onSelected: (on) {
                    if (on && selected.length >= maxTags) return;
                    onChanged(on ? [...selected, t] : selected.where((x) => x != t).toList());
                  },
                ),
            ],
          ),
        ],
      );
}
