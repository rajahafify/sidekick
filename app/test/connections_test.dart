import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/models.dart';

void main() {
  test('a connection carries the person, their contact details and where we met', () {
    final c = Connection.fromMap({
      'uid': 'ap-southeast-1:bob',
      'displayName': 'Bob',
      'headline': 'Builds things',
      'photoURL': '',
      'contact': {'linkedin': 'linkedin.com/in/bob', 'email': 'bob@example.com', 'phone': ''},
      'eventId': 'e1',
      'eventName': 'Founders night',
      'matchedAt': '2026-11-20T10:00:00.000Z',
    });
    expect(c.name, 'Bob');
    expect(c.contact.email, 'bob@example.com');
    expect(c.contact.isEmpty, isFalse);
    expect(c.eventId, 'e1');
    expect(c.eventName, 'Founders night');
    expect(c.matchedAt?.toUtc(), DateTime.utc(2026, 11, 20, 10));
  });

  test('the connections list reads every item, and copes with none', () {
    expect(ConnectionList.fromMap({'items': []}).items, isEmpty);
    expect(ConnectionList.fromMap({}).items, isEmpty);
    final list = ConnectionList.fromMap({
      'items': [
        {'uid': 'a', 'displayName': 'Ana', 'eventId': 'e1'},
        {'uid': 'b', 'displayName': 'Ben', 'eventId': 'e2'},
      ],
    });
    expect(list.items.map((c) => c.uid), ['a', 'b']);
    expect(list.items.first.contact.isEmpty, isTrue);
  });

  test('a room says who is here that I already connected with, and the event we met at', () {
    final room = Room.fromMap({
      'event': {'id': 'e2', 'name': 'Coffee'},
      'guest': false,
      'me': {'uid': 'me', 'displayName': 'Me'},
      'people': [
        {'uid': 'b', 'displayName': 'Ben'},
        {'uid': 'c', 'displayName': 'Cat'},
      ],
      'connected': [
        {'uid': 'b', 'displayName': 'Ben', 'eventId': 'e1'},
      ],
    });
    expect(room.connected.map((p) => p.uid), ['b']);
    expect(room.connectedEvents, {'b': 'e1'});
    expect(Room.fromMap({'event': {'id': 'e2', 'name': 'Coffee'}, 'guest': false}).connected, isEmpty);
  });
}
