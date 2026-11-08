/// Shared vocabulary for "looking for" and "can offer", so the two sides line up.
const networkTags = <String>[
  'Funding',
  'Customers',
  'Cofounder',
  'Hiring',
  'A new role',
  'Partnerships',
  'Mentorship',
  'Advice',
  'Product feedback',
  'Engineering help',
  'Design help',
  'Go-to-market',
  'Intros',
  'Collaborators',
];

/// Most tags on each side (the API allows 6).
const maxTags = 6;

List<String> _strings(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
double? _num(Object? v) => v is num ? v.toDouble() : null;
Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

/// What's new with one match, for the Alerts and Messages tabs. One per match, kept up to date.
class Note {
  const Note({
    required this.eventId,
    required this.other,
    required this.name,
    this.photoURL = '',
    this.left = false,
    this.kind = 'match',
    this.at,
    this.preview = '',
    this.matchedAt,
    this.alertUnread = false,
    this.chatUnread = false,
  });

  final String eventId;
  final String other;
  final String name;
  final String photoURL;

  /// They've left the event. The match and the conversation still stand.
  final bool left;

  /// 'match', or 'message' when the latest thing is a message.
  final String kind;
  final DateTime? at;
  final String preview;
  final DateTime? matchedAt;
  final bool alertUnread;
  final bool chatUnread;

  bool get isMatch => kind == 'match';

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        eventId: '${m['eventId'] ?? ''}',
        other: '${m['other'] ?? ''}',
        name: '${m['name'] ?? ''}',
        photoURL: '${m['photoURL'] ?? ''}',
        left: m['left'] == true,
        kind: '${m['kind'] ?? 'match'}',
        at: _date(m['at']),
        preview: '${m['preview'] ?? ''}',
        matchedAt: _date(m['matchedAt']),
        alertUnread: m['alertUnread'] == true,
        chatUnread: m['chatUnread'] == true,
      );
}

/// The notes, newest first, and how many of them are unread.
class NoteList {
  const NoteList(this.items, this.unread);
  final List<Note> items;
  final int unread;

  factory NoteList.fromMap(Map<String, dynamic> m) => NoteList(
        ((m['items'] as List?) ?? const []).map((e) => Note.fromMap(_map(e))).toList(),
        (m['unread'] as num?)?.toInt() ?? 0,
      );
}

/// Someone I connected with, at this event or an earlier one. Their contact details are shown, since we matched.
class Connection {
  const Connection({
    required this.uid,
    required this.name,
    this.headline = '',
    this.photoURL = '',
    this.contact = const Contact(),
    required this.eventId,
    this.eventName = '',
    this.matchedAt,
  });

  final String uid;
  final String name;
  final String headline;
  final String photoURL;
  final Contact contact;

  /// The event where we last connected. Our chat is kept there.
  final String eventId;
  final String eventName;
  final DateTime? matchedAt;

  factory Connection.fromMap(Map<String, dynamic> m) => Connection(
        uid: '${m['uid'] ?? ''}',
        name: '${m['displayName'] ?? ''}',
        headline: '${m['headline'] ?? ''}',
        photoURL: '${m['photoURL'] ?? ''}',
        contact: Contact.fromMap(_map(m['contact'])),
        eventId: '${m['eventId'] ?? ''}',
        eventName: '${m['eventName'] ?? ''}',
        matchedAt: _date(m['matchedAt']),
      );
}

class ConnectionList {
  const ConnectionList({required this.items});
  final List<Connection> items;

  factory ConnectionList.fromMap(Map<String, dynamic> m) =>
      ConnectionList(items: ((m['items'] as List?) ?? const []).map((e) => Connection.fromMap(_map(e))).toList());
}

class ChatMessage {
  const ChatMessage({required this.id, required this.mine, required this.text, this.at});
  final String id;
  final bool mine;
  final String text;
  final DateTime? at;

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: '${m['id'] ?? ''}',
        mine: m['mine'] == true,
        text: '${m['text'] ?? ''}',
        at: _date(m['at']),
      );
}

/// A conversation with one match: who it's with, and the latest messages, oldest first.
class ChatThread {
  const ChatThread({
    required this.uid,
    required this.name,
    this.photoURL = '',
    this.left = false,
    this.messages = const [],
  });

  final String uid;
  final String name;
  final String photoURL;
  final bool left;
  final List<ChatMessage> messages;

  factory ChatThread.fromMap(Map<String, dynamic> m) {
    final p = _map(m['person']);
    return ChatThread(
      uid: '${p['uid'] ?? ''}',
      name: '${p['name'] ?? ''}',
      photoURL: '${p['photoURL'] ?? ''}',
      left: p['left'] == true,
      messages: ((m['messages'] as List?) ?? const []).map((e) => ChatMessage.fromMap(_map(e))).toList(),
    );
  }
}

class Contact {
  const Contact({this.linkedin = '', this.email = '', this.phone = ''});
  final String linkedin;
  final String email;
  final String phone;

  bool get isEmpty => linkedin.trim().isEmpty && email.trim().isEmpty && phone.trim().isEmpty;

  factory Contact.fromMap(Map<String, dynamic> m) =>
      Contact(linkedin: '${m['linkedin'] ?? ''}', email: '${m['email'] ?? ''}', phone: '${m['phone'] ?? ''}');

  Map<String, dynamic> toMap() => {'linkedin': linkedin.trim(), 'email': email.trim(), 'phone': phone.trim()};
}

/// Your private profile. Only you ever see it; events get a card made from it.
class Profile {
  const Profile({
    required this.displayName,
    this.photoURL = '',
    this.headline = '',
    this.lookingFor = const [],
    this.offering = const [],
    this.about = '',
    this.contact = const Contact(),
    this.onboarded = false,
  });

  final String displayName;
  final String photoURL;
  final String headline;
  final List<String> lookingFor;
  final List<String> offering;
  final String about;
  final Contact contact;
  final bool onboarded;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        displayName: '${m['displayName'] ?? ''}',
        photoURL: '${m['photoURL'] ?? ''}',
        headline: '${m['headline'] ?? ''}',
        lookingFor: _strings(m['lookingFor']),
        offering: _strings(m['offering']),
        about: '${m['about'] ?? ''}',
        contact: Contact.fromMap(_map(m['contact'])),
        onboarded: m['onboarded'] == true,
      );

  Map<String, dynamic> toMap() => {
        'displayName': displayName.trim(),
        'photoURL': photoURL,
        'headline': headline.trim(),
        'lookingFor': lookingFor,
        'offering': offering,
        'about': about.trim(),
        'contact': contact.toMap(),
      };

  Card card(String uid) => Card(
      uid: uid, displayName: displayName, headline: headline, lookingFor: lookingFor, offering: offering, about: about);
}

/// The public card fields. This is all the sidekick ever sees about a person.
class Card {
  const Card({
    required this.uid,
    required this.displayName,
    this.headline = '',
    this.lookingFor = const [],
    this.offering = const [],
    this.about = '',
  });

  final String uid;
  final String displayName;
  final String headline;
  final List<String> lookingFor;
  final List<String> offering;
  final String about;
}

/// Someone's card at an event.
class Attendee extends Card {
  const Attendee({
    required super.uid,
    required super.displayName,
    super.headline,
    super.lookingFor,
    super.offering,
    super.about,
    this.photoURL = '',
    this.visible = true,
  });

  final String photoURL;
  final bool visible;

  factory Attendee.fromMap(Map<String, dynamic> m) => Attendee(
        uid: '${m['uid'] ?? ''}',
        displayName: '${m['displayName'] ?? ''}',
        headline: '${m['headline'] ?? ''}',
        lookingFor: _strings(m['lookingFor']),
        offering: _strings(m['offering']),
        about: '${m['about'] ?? ''}',
        photoURL: '${m['photoURL'] ?? ''}',
        visible: m['visible'] != false,
      );

  /// What the sidekick reads, to know when to scout again.
  String get key => '$uid:$headline:${lookingFor.join(',')}:${offering.join(',')}:$about';
}

class EventDoc {
  const EventDoc({
    required this.id,
    required this.name,
    this.place = '',
    this.createdBy = '',
    this.startsAt,
    this.endsAt,
    this.lat,
    this.lng,
    this.sourceUrl,
    this.kind,
  });

  final String id;
  final String name;
  final String place;
  final String createdBy;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final double? lat;
  final double? lng;
  final String? sourceUrl;

  /// 'place' for a check-in room at a place (one per place per day); null for events.
  final String? kind;

  bool get isPlace => kind == 'place';
  bool get hasLocation => lat != null && lng != null;

  factory EventDoc.fromMap(Map<String, dynamic> m) => EventDoc(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        place: '${m['place'] ?? ''}',
        createdBy: '${m['createdBy'] ?? ''}',
        startsAt: _date(m['startsAt']),
        endsAt: _date(m['endsAt']),
        lat: _num(m['lat']),
        lng: _num(m['lng']),
        sourceUrl: m['sourceUrl'] as String?,
        kind: m['kind'] as String?,
      );
}

/// An event I've joined, for the home screen.
class MyEvent {
  const MyEvent({required this.id, required this.name, this.place = '', this.startsAt, this.endsAt, this.kind});
  final String id;
  final String name;
  final String place;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? kind;

  factory MyEvent.fromMap(Map<String, dynamic> m) => MyEvent(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        place: '${m['place'] ?? ''}',
        startsAt: _date(m['startsAt']),
        endsAt: _date(m['endsAt']),
        kind: m['kind'] as String?,
      );
}

/// An event from my side: who's there (if I'm checked in), my swipes and matches.
class Room {
  const Room({
    required this.event,
    required this.guest,
    this.me,
    this.count = 0,
    this.people = const [],
    this.connected = const [],
    this.connectedEvents = const {},
    this.swipes = const {},
    this.matches = const [],
  });

  final EventDoc event;
  final bool guest;
  final Attendee? me;
  final int count;
  final List<Attendee> people;

  /// People here I've already connected with. The deck skips them; they're listed apart.
  final List<Attendee> connected;

  /// The event where I last connected with each of them, so I can message them there.
  final Map<String, String> connectedEvents;
  final Map<String, bool> swipes;
  final List<String> matches;

  bool get checkedIn => me != null;

  factory Room.fromMap(Map<String, dynamic> m) => Room(
        event: EventDoc.fromMap(_map(m['event'])),
        guest: m['guest'] == true,
        me: m['me'] is Map ? Attendee.fromMap(_map(m['me'])) : null,
        count: (m['count'] as num?)?.toInt() ?? 0,
        people: ((m['people'] as List?) ?? []).map((p) => Attendee.fromMap(_map(p))).toList(),
        connected: ((m['connected'] as List?) ?? []).map((p) => Attendee.fromMap(_map(p))).toList(),
        connectedEvents: {
          for (final p in (m['connected'] as List?) ?? const []) '${_map(p)['uid']}': '${_map(p)['eventId']}',
        },
        swipes: _map(m['swipes']).map((k, v) => MapEntry(k, v == true)),
        matches: ((m['matches'] as List?) ?? []).map((x) => '${_map(x)['uid']}').toList(),
      );
}

/// The sidekick's verdict on one person, for the person it works for.
class ScoutPick {
  const ScoutPick({required this.uid, required this.score, required this.reason});
  final String uid;
  final int score;
  final String reason;

  factory ScoutPick.fromJson(Map<String, dynamic> j) => ScoutPick(
        uid: '${j['uid']}',
        score: ((j['score'] as num?)?.round() ?? 0).clamp(0, 100),
        reason: '${j['reason'] ?? ''}',
      );
}

class Scout {
  const Scout({required this.picks, required this.source});
  final List<ScoutPick> picks;
  final String source; // 'llm' | 'template'

  factory Scout.fromJson(Map<String, dynamic> j) => Scout(
        picks: ((j['picks'] as List?) ?? const []).map((p) => ScoutPick.fromJson(_map(p))).toList(),
        source: '${j['source'] ?? 'template'}',
      );
}

class Turn {
  const Turn(this.speaker, this.text);
  final String speaker;
  final String text;
}

/// For a match: the two sidekicks' short exchange, why to talk, and an opener.
class Exchange {
  const Exchange({required this.turns, required this.reason, required this.opener, required this.source});
  final List<Turn> turns;
  final String reason;
  final String opener;
  final String source;

  factory Exchange.fromJson(Map<String, dynamic> j) => Exchange(
        turns: ((j['turns'] as List?) ?? const []).map((t) => Turn('${_map(t)['speaker']}', '${_map(t)['text']}')).toList(),
        reason: '${j['reason'] ?? ''}',
        opener: '${j['opener'] ?? ''}',
        source: '${j['source'] ?? 'template'}',
      );
}

class MatchDetails {
  const MatchDetails({required this.person, required this.contact, required this.exchange});
  final Attendee person;
  final Contact contact;
  final Exchange exchange;

  factory MatchDetails.fromMap(Map<String, dynamic> m) => MatchDetails(
        person: Attendee.fromMap(_map(m['person'])),
        contact: Contact.fromMap(_map(m['contact'])),
        exchange: Exchange.fromJson(_map(m['exchange'])),
      );
}

/// What /import-event read from an event page.
class ImportedEvent {
  const ImportedEvent({required this.name, required this.place, this.startsAt, this.endsAt, required this.url});
  final String name;
  final String place;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String url;

  factory ImportedEvent.fromJson(Map<String, dynamic> j) => ImportedEvent(
        name: '${j['name'] ?? ''}',
        place: '${j['place'] ?? ''}',
        startsAt: _date(j['startsAt']),
        endsAt: _date(j['endsAt']),
        url: '${j['url'] ?? ''}',
      );
}

/// A place from Amazon Location.
class PlaceDetails {
  const PlaceDetails({required this.placeId, required this.name, required this.address, this.lat, this.lng});
  final String placeId;
  final String name;
  final String address;
  final double? lat;
  final double? lng;

  String get label => [name, address].where((s) => s.isNotEmpty).join(', ');

  factory PlaceDetails.fromJson(Map<String, dynamic> j) => PlaceDetails(
        placeId: '${j['placeId'] ?? ''}',
        name: '${j['name'] ?? ''}',
        address: '${j['address'] ?? ''}',
        lat: _num(j['lat']),
        lng: _num(j['lng']),
      );
}

/// How the app looks: follow the phone or browser, or always light or always dark. Each person can
/// pick their own; otherwise the admin's default applies.
enum ThemeChoice {
  system,
  light,
  dark;

  static ThemeChoice parse(Object? v, {ThemeChoice fallback = ThemeChoice.dark}) {
    for (final c in values) {
      if (c.name == v) return c;
    }
    return fallback;
  }
}
