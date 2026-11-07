import { describe, expect, it } from 'vitest';
import { App, type Deps, type Identity } from '../src/app';
import { placeRoomId } from '../src/geo';
import type { GooglePlace, GooglePlaces } from '../src/googlePlaces';
import type { PlaceDetails, Places } from '../src/places';
import { MemoryStore } from '../src/store';

const DAY_MS = 24 * 3600_000;
const START = Date.parse('2026-11-20T10:00:00Z');
const day = '20261120';
const dayStart = '2026-11-19T16:00:00Z'; // midnight in Kuala Lumpur
const fix = { lat: 3.1469, lng: 101.7103, accuracy: 20 };
const who = (n: string): Identity => ({ id: `ap-southeast-1:${n}`, guest: false });
const alice = who('alice');
const bob = who('bob');
const guest: Identity = { id: 'ap-southeast-1:guest', guest: true };

const place: PlaceDetails = {
  placeId: 'AQAB-cafe',
  name: 'Common Ground',
  address: 'Bukit Bintang, Kuala Lumpur',
  lat: 3.1468,
  lng: 101.7102,
};
const listing: GooglePlace = {
  id: 'ChIJ-common-ground',
  name: 'Common Ground',
  address: 'Jalan Bukit Bintang, 55100 Kuala Lumpur',
  lat: 3.1468,
  lng: 101.7102,
  phone: '+60 3-2148 0000',
  website: 'https://commonground.example',
  mapsUri: 'https://maps.google.com/?cid=1',
  rating: 4.6,
  ratingCount: 1204,
  hours: [
    'Monday: 9:00 AM – 6:00 PM',
    'Tuesday: 9:00 AM – 6:00 PM',
    'Wednesday: 9:00 AM – 6:00 PM',
    'Thursday: 9:00 AM – 6:00 PM',
    'Friday: 9:00 AM – 10:00 PM',
    'Saturday: 10:00 AM – 10:00 PM',
    'Sunday: Closed',
  ],
  utcOffsetMinutes: 480,
};
const photo = { url: 'https://lh3.googleusercontent.com/p1', author: 'Mei', authorUri: 'https://maps.google.com/contrib/1' };
const profile = (name: string) => ({
  displayName: name,
  headline: '',
  lookingFor: [],
  offering: [],
  about: '',
  contact: { linkedin: `linkedin.com/in/${name}`, email: '', phone: '' },
});
const checkInBody = { place: 'Common Ground, Bukit Bintang', placeId: place.placeId, lat: place.lat, lng: place.lng, day, dayStart, fix };

/** Google's side, with counters for each kind of call. */
function fakeGoogle(over: Partial<GooglePlaces> = {}) {
  const calls = { match: 0, details: 0, photos: 0 };
  const g: GooglePlaces = {
    match: async () => {
      calls.match++;
      return { id: listing.id };
    },
    details: async () => {
      calls.details++;
      return listing;
    },
    photos: async () => {
      calls.photos++;
      return [photo];
    },
    ...over,
  };
  return { g, calls };
}

function setup(over: Partial<Deps> = {}) {
  let now = START;
  const store = new MemoryStore();
  const places: Places = {
    suggest: async () => [],
    nearby: async () => [],
    details: async (id) => (id.startsWith('AQAB') ? { ...place, placeId: id } : null),
  };
  const app = new App({ store, model: null, places, fetch, now: () => now, ...over });
  const call = async (w: Identity, method: string, path: string, body?: unknown) => {
    const r = await app.handle({ method, path, body, identity: w });
    return { status: r.status, body: r.body as any };
  };
  return { call, setNow: (t: number) => (now = t) };
}

describe('place pages', () => {
  it('shows the Google listing next to what Amazon knows, and who is checked in on that day', async () => {
    const g = fakeGoogle();
    const s = setup({ googlePlaces: g.g });
    await s.call(alice, 'PUT', '/me', profile('alice'));
    await s.call(bob, 'PUT', '/me', profile('bob'));
    await s.call(alice, 'POST', '/checkin', checkInBody);
    await s.call(bob, 'POST', '/checkin', checkInBody);

    const page = await s.call(guest, 'POST', '/places/page', { placeId: place.placeId, day });
    expect(page.status).toBe(200);
    expect(page.body.place).toMatchObject({
      placeId: place.placeId,
      name: 'Common Ground',
      address: listing.address,
      google: true,
      phone: listing.phone,
      website: listing.website,
      mapsUri: listing.mapsUri,
      rating: 4.6,
      ratingCount: 1204,
      today: 4, // Friday, on the place's clock
      photos: [photo],
    });
    expect(page.body.place.hours).toHaveLength(7);
    // A guest sees the count, but isn't checked in.
    expect(page.body.room).toEqual({ id: placeRoomId(place.placeId, '', day), count: 2, checkedIn: false });
    const mine = await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day });
    expect(mine.body.room).toEqual({ id: placeRoomId(place.placeId, '', day), count: 2, checkedIn: true });
  });

  it('remembers the match for a year and the details for a day, but looks for photos every time', async () => {
    const g = fakeGoogle();
    const s = setup({ googlePlaces: g.g });
    await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day });
    await s.call(bob, 'POST', '/places/page', { placeId: place.placeId, day });
    expect(g.calls).toEqual({ match: 1, details: 1, photos: 2 });

    s.setNow(START + 2 * DAY_MS);
    await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day: '20261122' });
    expect(g.calls).toEqual({ match: 1, details: 2, photos: 3 });
  });

  it('does not remember a failed match, and remembers "no listing" only for a week', async () => {
    let answer: { id: string | null } | null = null;
    let matches = 0;
    const g = fakeGoogle({
      match: async () => {
        matches++;
        return answer;
      },
    });
    const s = setup({ googlePlaces: g.g });

    answer = null; // Google failed
    const failed = await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day });
    expect(failed.body.place).toMatchObject({ google: false, name: 'Common Ground' });

    answer = { id: null }; // Google has no listing for it
    await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day });
    await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day });
    expect(matches).toBe(2);

    s.setNow(START + 8 * DAY_MS);
    answer = { id: listing.id };
    const later = await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day });
    expect(matches).toBe(3);
    expect(later.body.place.google).toBe(true);
  });

  it('stops calling Google once the day’s billed calls are used up, and still answers from Amazon', async () => {
    const g = fakeGoogle();
    const s = setup({ googlePlaces: g.g });
    // The first place costs two billed calls (its match and its details). Each later place costs one
    // match, since the listing's details are kept for the day. So 199 places use up all 200.
    for (let i = 0; i < 199; i++) {
      const r = await s.call(who(`p${i}`), 'POST', '/places/page', { placeId: `AQAB-${i}` });
      expect(r.status).toBe(200);
      expect(r.body.place.google).toBe(true);
    }
    expect(g.calls).toEqual({ match: 199, details: 1, photos: 199 });

    const over = await s.call(who('late'), 'POST', '/places/page', { placeId: 'AQAB-late' });
    expect(over.status).toBe(200);
    expect(over.body.place).toMatchObject({ google: false, name: 'Common Ground', photos: [], hours: [] });
    expect(g.calls.match).toBe(199);
  });

  it('works from Amazon’s details alone when there is no Google key', async () => {
    const s = setup({ googlePlaces: null });
    const r = await s.call(alice, 'POST', '/places/page', { placeId: place.placeId });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({
      place: {
        placeId: place.placeId,
        name: place.name,
        address: place.address,
        lat: place.lat,
        lng: place.lng,
        google: false,
        phone: '',
        website: '',
        mapsUri: '',
        rating: null,
        ratingCount: 0,
        hours: [],
        today: null,
        photos: [],
      },
      room: null,
    });
  });

  it('rejects a bad day, a missing place, and a place it cannot find', async () => {
    const s = setup({ googlePlaces: fakeGoogle().g });
    expect((await s.call(alice, 'POST', '/places/page', {})).status).toBe(400);
    expect((await s.call(alice, 'POST', '/places/page', { placeId: place.placeId, day: '2026-11-20' })).status).toBe(400);
    expect((await s.call(alice, 'POST', '/places/page', { placeId: 'nope' })).status).toBe(404);
  });

  it('limits how many places one person can look at a day', async () => {
    const s = setup({ googlePlaces: fakeGoogle().g });
    for (let i = 0; i < 60; i++) expect((await s.call(alice, 'POST', '/places/page', { placeId: place.placeId })).status).toBe(200);
    expect((await s.call(alice, 'POST', '/places/page', { placeId: place.placeId })).status).toBe(429);
  });
});
