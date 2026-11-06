// The sidekick's template: a port of web/shared/sidekick.ts, used when the server is unreachable,
// when no model is configured, and for people who joined after the last scout.
import '../models.dart';

String _norm(String s) => s.trim().toLowerCase();

/// Tags in [wants] that [has] offers, case-insensitive, in the order of [wants].
List<String> overlap(List<String> wants, List<String> has) {
  final set = has.map(_norm).toSet();
  return wants.where((w) => set.contains(_norm(w))).toList();
}

final _stop = 'about after also and are but can for from have into just like more our out that the their them they this was what when with work working your'
    .split(' ')
    .toSet();

Set<String> _words(Card c) => '${c.headline} ${c.about}'
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9+#]+'))
    .where((w) => w.length > 3 && !_stop.contains(w))
    .toSet();

String firstName(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  return parts.first.isEmpty ? 'They' : parts.first;
}

/// Deterministic relevance of [them] to [me], 0 to 100, with a one-line reason.
ScoutPick templatePick(Card me, Card them) {
  final theyHelpMe = overlap(me.lookingFor, them.offering);
  final iHelpThem = overlap(them.lookingFor, me.offering);
  final mine = _words(me);
  final shared = _words(them).where(mine.contains).toList();
  final sameGoals = overlap(me.lookingFor, them.lookingFor);
  final score =
      (10 + theyHelpMe.length * 30 + iHelpThem.length * 20 + shared.length * 8 + sameGoals.length * 5).clamp(0, 100);
  final name = firstName(them.displayName);
  String reason;
  if (theyHelpMe.isNotEmpty && iHelpThem.isNotEmpty) {
    reason =
        'Two-way fit: $name offers ${theyHelpMe.first.toLowerCase()} and is looking for ${iHelpThem.first.toLowerCase()}.';
  } else if (theyHelpMe.isNotEmpty) {
    reason = "$name offers ${theyHelpMe.join(', ').toLowerCase()}, which you're looking for.";
  } else if (iHelpThem.isNotEmpty) {
    reason = '$name is looking for ${iHelpThem.join(', ').toLowerCase()}, which you offer.';
  } else if (shared.isNotEmpty) {
    reason = 'You both mention ${shared.take(2).join(' and ')}.';
  } else if (sameGoals.isNotEmpty) {
    reason = "You're both looking for ${sameGoals.first.toLowerCase()}. Compare notes.";
  } else {
    reason = them.headline.isNotEmpty ? '${them.headline}.' : '$name is here too.';
  }
  return ScoutPick(uid: them.uid, score: score, reason: reason);
}

Scout templateScout(Card me, List<Card> others) {
  final picks = others.where((o) => o.uid != me.uid).map((o) => templatePick(me, o)).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return Scout(picks: picks, source: 'template');
}

Exchange templateExchange(Card one, Card two) {
  final ordered = one.uid.compareTo(two.uid) < 0 ? [one, two] : [two, one];
  final a = ordered[0], b = ordered[1];
  final an = firstName(a.displayName), bn = firstName(b.displayName);
  final aGets = overlap(a.lookingFor, b.offering);
  final bGets = overlap(b.lookingFor, a.offering);
  final reason = aGets.isNotEmpty || bGets.isNotEmpty
      ? '${[
          if (aGets.isNotEmpty) '$bn can help $an with ${aGets.first.toLowerCase()}',
          if (bGets.isNotEmpty) '$an can help $bn with ${bGets.first.toLowerCase()}',
        ].join(', and ')}.'
      : '$an and $bn both wanted to connect.';
  final opener = aGets.isNotEmpty
      ? 'What are you looking for in ${aGets.first.toLowerCase()} right now?'
      : bGets.isNotEmpty
          ? 'What are you looking for in ${bGets.first.toLowerCase()} right now?'
          : (b.about.isNotEmpty || a.about.isNotEmpty)
              ? 'What are you working on at the moment?'
              : 'What brought you to this event?';
  String intro(Card c) => '${firstName(c.displayName)}${c.headline.isNotEmpty ? ', ${c.headline}' : ''}';
  return Exchange(
    source: 'template',
    reason: reason,
    opener: opener,
    turns: [
      Turn(a.uid,
          "I'm with ${intro(a)}.${a.lookingFor.isNotEmpty ? ' Looking for ${a.lookingFor.join(', ').toLowerCase()}.' : ''}"),
      Turn(b.uid,
          "I'm with ${intro(b)}.${b.offering.isNotEmpty ? ' Can offer ${b.offering.join(', ').toLowerCase()}.' : ''}"),
      Turn(a.uid, aGets.isNotEmpty ? "That's a fit for $an." : '$an would value the conversation.'),
      Turn(b.uid, "Then let's swap contacts. Try: \"$opener\""),
    ],
  );
}

/// Stable id for a match between two people: smaller uid first.
String matchId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';
