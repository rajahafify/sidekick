import { afterEach, describe, expect, it, vi } from 'vitest';
import { googlePlaces, placeWeekday, sameName } from '../src/googlePlaces';

const KEY = 'test-key-123';
const near = { lat: 3.1468, lng: 101.7102 };

/** A fetch that answers from a table of routes, and keeps every request it was asked. */
function fakeFetch(route: (url: string, init: RequestInit) => { status?: number; body: unknown }) {
  const asked: { url: string; init: RequestInit }[] = [];
  const doFetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    asked.push({ url: String(url), init: init ?? {} });
    const r = route(String(url), init ?? {});
    return new Response(JSON.stringify(r.body), {
      status: r.status ?? 200,
      headers: { 'content-type': 'application/json' },
    });
  });
  return { doFetch: doFetch as unknown as typeof fetch, asked };
}

const withKey = async () => KEY;
const headerOf = (init: RequestInit, name: string) => (init.headers as Record<string, string>)[name];

afterEach(() => vi.restoreAllMocks());

describe('sameName', () => {
  it('accepts the same name, or one with extra words, ignoring accents and case', () => {
    expect(sameName('Common Ground', 'Common Ground Bangsar')).toBe(true);
    expect(sameName('Café Común', 'cafe comun')).toBe(true);
    expect(sameName('咖啡馆', '咖啡馆')).toBe(true);
  });

  it('rejects other names, short names, and words that only look alike', () => {
    expect(sameName('Common Ground', 'Kopi Corner')).toBe(false);
    expect(sameName('Cafe', 'Cafe Bangsar')).toBe(false);
    expect(sameName('Cafeteria', 'Cafe Bangsar')).toBe(false);
    expect(sameName('', 'Common Ground')).toBe(false);
  });
});

describe('placeWeekday', () => {
  // 20 Nov 2026 is a Friday. At 10:00 UTC it is 18:00 in Kuala Lumpur (UTC+8).
  const friday = Date.parse('2026-11-20T10:00:00Z');

  it('counts Monday as 0 and uses the place’s own clock', () => {
    expect(placeWeekday(480, friday)).toBe(4);
    expect(placeWeekday(0, Date.parse('2026-11-16T12:00:00Z'))).toBe(0); // Monday
    expect(placeWeekday(0, Date.parse('2026-11-22T12:00:00Z'))).toBe(6); // Sunday
    // Late on Sunday in UTC, but already Monday in a place one hour ahead.
    expect(placeWeekday(60, Date.parse('2026-11-15T23:30:00Z'))).toBe(0);
  });

  it('has no answer without a time zone', () => {
    expect(placeWeekday(null, friday)).toBeNull();
  });
});

describe('match', () => {
  it('picks the nearest listing with the same name, and never a far or differently named one', async () => {
    const { doFetch, asked } = fakeFetch(() => ({
      body: {
        places: [
          { id: 'far', displayName: { text: 'Common Ground' }, location: { latitude: 3.2, longitude: 101.7 } },
          { id: 'kopi', displayName: { text: 'Kopi Corner' }, location: { latitude: 3.1469, longitude: 101.7103 } },
          { id: 'near', displayName: { text: 'Common Ground Bangsar' }, location: { latitude: 3.147, longitude: 101.7104 } },
        ],
      },
    }));
    const g = googlePlaces(withKey, doFetch);
    expect(await g.match('Common Ground', 'Bukit Bintang, Kuala Lumpur', near)).toEqual({ id: 'near' });

    const [req] = asked;
    expect(req.url).toBe('https://places.googleapis.com/v1/places:searchText');
    expect(req.init.method).toBe('POST');
    expect(headerOf(req.init, 'x-goog-api-key')).toBe(KEY);
    expect(headerOf(req.init, 'x-goog-fieldmask')).toContain('places.displayName');
    expect(JSON.parse(String(req.init.body)).textQuery).toBe('Common Ground Bukit Bintang, Kuala Lumpur');
  });

  it('says there is no listing when none is close and named the same', async () => {
    const { doFetch } = fakeFetch(() => ({
      body: { places: [{ id: 'two-km', displayName: { text: 'Common Ground' }, location: { latitude: 3.165, longitude: 101.7102 } }] },
    }));
    expect(await googlePlaces(withKey, doFetch).match('Common Ground', 'KL', near)).toEqual({ id: null });
  });

  it('gives no answer when Google fails, so nothing is remembered', async () => {
    const { doFetch } = fakeFetch(() => ({ status: 500, body: { error: { message: 'Backend Error' } } }));
    expect(await googlePlaces(withKey, doFetch).match('Common Ground', 'KL', near)).toBeNull();
  });

  it('says whether there is a key, without calling Google', async () => {
    const { doFetch, asked } = fakeFetch(() => ({ body: {} }));
    expect(await googlePlaces(withKey, doFetch).hasKey()).toBe(true);
    expect(await googlePlaces(async () => null, doFetch).hasKey()).toBe(false);
    expect(asked).toHaveLength(0);
  });

  it('makes no call at all without a key', async () => {
    const { doFetch, asked } = fakeFetch(() => ({ body: {} }));
    expect(await googlePlaces(async () => null, doFetch).match('Common Ground', 'KL', near)).toBeNull();
    expect(asked).toHaveLength(0);
  });
});

describe('details', () => {
  const listing = {
    id: 'abc',
    displayName: { text: 'Common Ground' },
    formattedAddress: 'Jalan Bukit Bintang, Kuala Lumpur',
    location: { latitude: 3.1468, longitude: 101.7102 },
    googleMapsUri: 'https://maps.google.com/?cid=1',
    websiteUri: 'javascript:alert(1)',
    internationalPhoneNumber: '+60 3-2148 0000',
    regularOpeningHours: { weekdayDescriptions: ['Monday: 9:00 AM – 6:00 PM'] },
    utcOffsetMinutes: 480,
    rating: 4.6,
    userRatingCount: 1204,
  };

  it('maps the listing, drops anything that is not an https link, and asks for no photos', async () => {
    const { doFetch, asked } = fakeFetch(() => ({ body: listing }));
    const p = await googlePlaces(withKey, doFetch).details('abc');
    expect(p).toMatchObject({
      id: 'abc',
      name: 'Common Ground',
      lat: 3.1468,
      lng: 101.7102,
      phone: '+60 3-2148 0000',
      website: '',
      mapsUri: 'https://maps.google.com/?cid=1',
      rating: 4.6,
      ratingCount: 1204,
      hours: ['Monday: 9:00 AM – 6:00 PM'],
      utcOffsetMinutes: 480,
    });
    const [req] = asked;
    expect(req.url).toBe('https://places.googleapis.com/v1/places/abc?languageCode=en');
    expect(headerOf(req.init, 'x-goog-fieldmask')).toContain('regularOpeningHours.weekdayDescriptions');
    expect(headerOf(req.init, 'x-goog-fieldmask')).not.toContain('photos');
  });

  it('has no answer for a listing without a position, or one that is missing', async () => {
    const noPosition = fakeFetch(() => ({ body: { id: 'abc' } }));
    expect(await googlePlaces(withKey, noPosition.doFetch).details('abc')).toBeNull();
    const missing = fakeFetch(() => ({ status: 404, body: { error: { message: 'Not found' } } }));
    expect(await googlePlaces(withKey, missing.doFetch).details('abc')).toBeNull();
  });
});

describe('photos', () => {
  it('looks up each photo fresh, credits its photographer, and skips names it does not recognise', async () => {
    const { doFetch, asked } = fakeFetch((url) => {
      if (url.endsWith('/places/abc')) {
        return {
          body: {
            photos: [
              { name: 'places/abc/photos/p1', authorAttributions: [{ displayName: 'Mei', uri: 'https://maps.google.com/contrib/1' }] },
              { name: '../../etc', authorAttributions: [] },
              { name: 'places/abc/photos/p2', authorAttributions: [] },
            ],
          },
        };
      }
      if (url.includes('/photos/p1/media')) return { body: { photoUri: 'https://lh3.googleusercontent.com/p1' } };
      if (url.includes('/photos/p2/media')) return { body: { photoUri: 'https://lh3.googleusercontent.com/p2' } };
      return { status: 404, body: {} };
    });
    const photos = await googlePlaces(withKey, doFetch).photos('abc', 3);
    expect(photos).toEqual([
      { url: 'https://lh3.googleusercontent.com/p1', author: 'Mei', authorUri: 'https://maps.google.com/contrib/1' },
      { url: 'https://lh3.googleusercontent.com/p2', author: '', authorUri: '' },
    ]);

    // The first request asks for photo names only; the media requests carry the key and skip the redirect.
    expect(headerOf(asked[0].init, 'x-goog-fieldmask')).toBe('id,photos');
    const media = asked.slice(1).map((a) => a.url);
    expect(media).toHaveLength(2);
    for (const u of media) {
      expect(u).toContain(`key=${KEY}`);
      expect(u).toContain('skipHttpRedirect=true');
    }
    // The key goes to Google and nowhere else: not in what we return.
    expect(JSON.stringify(photos)).not.toContain(KEY);
  });

  it('keeps the key out of the logs when a photo call fails', async () => {
    const logged: string[] = [];
    vi.spyOn(console, 'error').mockImplementation((...a: unknown[]) => void logged.push(a.join(' ')));
    const { doFetch } = fakeFetch((url) =>
      url.endsWith('/places/abc')
        ? { body: { photos: [{ name: 'places/abc/photos/p1', authorAttributions: [] }] } }
        : { status: 403, body: { error: { message: 'Quota exceeded' } } },
    );
    expect(await googlePlaces(withKey, doFetch).photos('abc', 3)).toEqual([]);
    expect(logged.join('\n')).toContain('Quota exceeded');
    expect(logged.join('\n')).not.toContain(KEY);
  });
});
