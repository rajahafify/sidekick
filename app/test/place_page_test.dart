import 'package:flutter_test/flutter_test.dart';
import 'package:sidekick/data/check_in.dart';
import 'package:sidekick/models.dart';

void main() {
  test('the check-in day is yyyymmdd on the phone’s own date', () {
    expect(dayKey(DateTime(2026, 11, 7, 23, 59)), '20261107');
    expect(dayKey(DateTime(2026, 1, 3)), '20260103');
  });

  test('a place page reads the answer with Google’s details, photos and today’s room', () {
    final page = PlacePage.fromMap({
      'place': {
        'placeId': 'AQAB-cafe',
        'name': 'Common Ground',
        'address': 'Bukit Bintang',
        'lat': 3.1468,
        'lng': 101.7102,
        'google': true,
        'phone': '+60 3-2148 0000',
        'website': 'https://commonground.example',
        'mapsUri': 'https://maps.google.com/?cid=1',
        'rating': 4.6,
        'ratingCount': 1204,
        'hours': ['Monday: 9:00 AM – 6:00 PM', 'Tuesday: Closed'],
        'today': 1,
        'photos': [
          {
            'url': 'https://lh3.googleusercontent.com/p1',
            'author': 'Mei',
            'authorUri': 'https://maps.google.com/contrib/1',
          },
        ],
      },
      'room': {'id': 'place-g-abc-20261107', 'count': 3, 'checkedIn': true},
    });

    expect(page.name, 'Common Ground');
    expect(page.google, isTrue);
    expect(page.rating, 4.6);
    expect(page.ratingCount, 1204);
    expect(page.today, 1);
    expect(page.hours, hasLength(2));
    expect(page.photos.single.author, 'Mei');
    expect(page.room!.count, 3);
    expect(page.room!.checkedIn, isTrue);
    expect(page.asPlace.label, 'Common Ground, Bukit Bintang');
  });

  test('a page without a Google listing or a room still reads', () {
    final page = PlacePage.fromMap({
      'place': {
        'placeId': 'AQAB-x',
        'name': 'Kopi Corner',
        'address': '',
        'lat': 3.1,
        'lng': 101.7,
        'google': false,
        'hours': [],
        'photos': [],
        'today': null,
      },
      'room': null,
    });

    expect(page.google, isFalse);
    expect(page.room, isNull);
    expect(page.today, isNull);
    expect(page.photos, isEmpty);
    expect(page.asPlace.label, 'Kopi Corner');
  });
}
