import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/logic/geo_when.dart';
import 'package:sidekick/logic/sidekick.dart';
import 'package:sidekick/models.dart';

void main() {
  group('templatePick', () {
    const me = Card(uid: 'me', displayName: 'Fify R', lookingFor: ['Funding'], offering: ['Engineering help']);

    test('ranks a two-way fit highest', () {
      const both = Card(uid: 'a', displayName: 'Aisha', lookingFor: ['Engineering help'], offering: ['Funding']);
      const oneWay = Card(uid: 'b', displayName: 'Ben', offering: ['Funding']);
      const none = Card(uid: 'c', displayName: 'Cy', headline: 'Designer');
      final picks = templateScout(me, [none, oneWay, both]).picks;
      expect(picks.map((p) => p.uid), ['a', 'b', 'c']);
      expect(picks.first.reason, startsWith('Two-way fit: Aisha offers funding'));
      expect(picks.last.reason, 'Designer.');
    });

    test('matches tags case-insensitively', () {
      expect(overlap(['funding', 'Hiring'], ['FUNDING']), ['funding']);
    });

    test('caps the score at 100', () {
      const them = Card(
        uid: 't',
        displayName: 'T',
        lookingFor: ['Engineering help'],
        offering: ['Funding', 'Engineering help'],
        headline: 'fintech payments startup founder',
      );
      const me2 = Card(
        uid: 'm',
        displayName: 'M',
        lookingFor: ['Funding', 'Engineering help'],
        offering: ['Engineering help', 'Funding'],
        headline: 'fintech payments startup founder',
      );
      expect(templatePick(me2, them).score, 100);
    });
  });

  group('geo', () {
    const klcc = LatLng(3.1579, 101.7116);
    test('measures distance and formats it', () {
      expect((distanceM(klcc, const LatLng(3.1579, 101.7206)) / 10).round() * 10, 1000);
      expect(formatDistance(234), '230 m');
      expect(formatDistance(1345), '1.3 km');
      expect(formatDistance(25000), '25 km');
    });
    test('gives a fuzzy fix the benefit of the doubt', () {
      expect(insideFence(const Fix(3.16, 101.7116, 20), klcc), isTrue);
      expect(insideFence(const Fix(3.17, 101.7116, 20), klcc), isFalse);
      expect(insideFence(const Fix(3.17, 101.7116, 900), klcc), isTrue);
    });
  });

  group('event times', () {
    DateTime at(int h, [int d = 20]) => DateTime(2026, 11, d, h);
    test('knows if an event is upcoming, live or over', () {
      expect(eventPhase(at(18), at(21), at(17)), EventPhase.upcoming);
      expect(eventPhase(at(18), at(21), at(19)), EventPhase.live);
      expect(eventPhase(at(18), at(21), at(22)), EventPhase.ended);
      expect(eventPhase(at(18), null, at(23)), EventPhase.live);
      expect(eventPhase(at(18), null, at(1, 21)), EventPhase.ended);
      expect(eventPhase(null, null), EventPhase.unknown);
    });
    test('formats a range', () {
      expect(eventWhen(null, null), '');
      expect(eventWhen(at(18), at(21)), contains('–'));
      expect(eventWhen(at(18), at(9, 22)), 'Fri, 20 Nov – Sun, 22 Nov');
    });
  });

  group('models', () {
    test('read a room from the API', () {
      final r = Room.fromMap({
        'event': {'id': 'e1', 'name': 'Night', 'startsAt': '2026-11-20T10:00:00.000Z', 'kind': 'place', 'lat': 3, 'lng': 101},
        'guest': true,
        'me': {'uid': 'me', 'displayName': 'Me'},
        'count': 2,
        'people': [
          {'uid': 'a', 'displayName': 'A', 'lookingFor': ['Funding'], 'visible': true}
        ],
        'swipes': {'a': true},
        'matches': [
          {'uid': 'a'}
        ],
      });
      expect(r.event.isPlace, isTrue);
      expect(r.event.hasLocation, isTrue);
      expect(r.checkedIn, isTrue);
      expect(r.people.single.lookingFor, ['Funding']);
      expect(r.swipes['a'], isTrue);
      expect(r.matches, ['a']);
    });
    test('a room you are not in has no people', () {
      final r = Room.fromMap({'event': {'id': 'e', 'name': 'N'}, 'guest': false, 'me': null, 'count': 4});
      expect(r.checkedIn, isFalse);
      expect(r.people, isEmpty);
    });
  });
}
