// A place's Google listing: photos, opening hours, phone, website and rating, from the Places API
// (New). The API key comes from SSM and is only ever sent to Google, never to the app.
//
// Google's rules, which this follows (see the Places API policies):
// - A place ID may be kept for good, so a place's match to its Google listing is remembered.
// - Other listing content is kept for a day at most (App caches it).
// - A photo name can't be cached, so photos are looked up again each time. The page credits each
//   photographer and links to the listing on Google Maps.
import { distanceM, type LatLng } from './geo';

const API = 'https://places.googleapis.com/v1';
const TIMEOUT_MS = 5000;

/** How close a Google listing must be to count as the place we were given. */
export const MATCH_RADIUS_M = 150;

const SEARCH_FIELDS = 'places.id,places.displayName,places.location,places.formattedAddress';
const PHOTO_FIELDS = 'id,photos';
const DETAILS_FIELDS = [
  'id',
  'displayName',
  'formattedAddress',
  'location',
  'googleMapsUri',
  'websiteUri',
  'internationalPhoneNumber',
  'regularOpeningHours.weekdayDescriptions',
  'utcOffsetMinutes',
  'rating',
  'userRatingCount',
].join(',');

export type GooglePlace = {
  id: string;
  name: string;
  address: string;
  lat: number;
  lng: number;
  phone: string;
  website: string;
  /** The listing on Google Maps. Every photo and the details link back to it. */
  mapsUri: string;
  rating: number | null;
  ratingCount: number;
  /** One line per day, Monday first, worded by Google. */
  hours: string[];
  /** The place's time zone as minutes from UTC, so "today" is the place's today. */
  utcOffsetMinutes: number | null;
};

export type GooglePhoto = { url: string; author: string; authorUri: string };

export interface GooglePlaces {
  /**
   * The listing that is this place: the nearest one with the same name within MATCH_RADIUS_M.
   * `{ id: null }` when Google has none, and null when the call failed (so nothing is remembered).
   */
  match(name: string, address: string, near: LatLng): Promise<{ id: string | null } | null>;
  /** null when the call failed or the listing has no position. */
  details(id: string): Promise<GooglePlace | null>;
  /** Up to `max` photos, fresh from Google. */
  photos(id: string, max: number): Promise<GooglePhoto[]>;
}

/** Google's field mask decides the price tier, so each call asks only for what the page shows. */
const headers = (key: string, fieldMask?: string) => ({
  'content-type': 'application/json',
  'x-goog-api-key': key,
  ...(fieldMask ? { 'x-goog-fieldmask': fieldMask } : {}),
});

const https = (v: unknown) => (typeof v === 'string' && /^https:\/\/\S+$/.test(v) && v.length <= 2000 ? v : '');

const norm = (s: string) =>
  s
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();

/** The same name, or one that is the other plus extra words: "Common Ground" and "Common Ground Bangsar". */
export function sameName(a: string, b: string): boolean {
  const x = norm(a);
  const y = norm(b);
  if (!x || !y) return false;
  if (x === y) return true;
  const [short, long] = x.length <= y.length ? [x, y] : [y, x];
  return short.length >= 5 && ` ${long} `.includes(` ${short} `);
}

/** Monday is 0 and Sunday is 6: the weekday at the place right now. Null without a time zone. */
export function placeWeekday(utcOffsetMinutes: number | null, nowMs: number): number | null {
  if (utcOffsetMinutes === null) return null;
  const sundayFirst = new Date(nowMs + utcOffsetMinutes * 60_000).getUTCDay();
  return (sundayFirst + 6) % 7;
}

function toPlace(p: any): GooglePlace | null {
  const lat = p?.location?.latitude;
  const lng = p?.location?.longitude;
  if (typeof p?.id !== 'string' || typeof lat !== 'number' || typeof lng !== 'number') return null;
  const hours = p.regularOpeningHours?.weekdayDescriptions;
  return {
    id: p.id,
    name: String(p.displayName?.text ?? ''),
    address: String(p.formattedAddress ?? ''),
    lat,
    lng,
    phone: typeof p.internationalPhoneNumber === 'string' ? p.internationalPhoneNumber : '',
    website: https(p.websiteUri),
    mapsUri: https(p.googleMapsUri),
    rating: typeof p.rating === 'number' ? p.rating : null,
    ratingCount: typeof p.userRatingCount === 'number' ? p.userRatingCount : 0,
    hours: Array.isArray(hours) ? hours.map(String).slice(0, 7) : [],
    utcOffsetMinutes: typeof p.utcOffsetMinutes === 'number' ? p.utcOffsetMinutes : null,
  };
}

/**
 * Google's Places API (New) over plain fetch. Every method returns null (or an empty list) when
 * there's no key or Google fails, so the place page just shows what Amazon Location knows.
 * Errors are logged without the key or the request URL, which carries the key for photos.
 */
export function googlePlaces(apiKey: () => Promise<string | null>, doFetch: typeof fetch = fetch): GooglePlaces {
  async function send(url: string, init: RequestInit, what: string): Promise<any | null> {
    try {
      const r = await doFetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
      if (r.ok) return await r.json();
      const message = await r.json().then(
        (j: any) => j?.error?.message,
        () => undefined,
      );
      console.error(`Google Places ${what} failed: HTTP ${r.status}${message ? `, ${String(message).slice(0, 160)}` : ''}`);
      return null;
    } catch (e: any) {
      console.error(`Google Places ${what} error: ${e?.name ?? 'error'}`);
      return null;
    }
  }

  return {
    async match(name, address, near) {
      const key = await apiKey();
      if (!key) return null;
      const data = await send(
        `${API}/places:searchText`,
        {
          method: 'POST',
          headers: headers(key, SEARCH_FIELDS),
          body: JSON.stringify({
            textQuery: `${name} ${address}`.trim().slice(0, 200),
            locationBias: { circle: { center: { latitude: near.lat, longitude: near.lng }, radius: 300 } },
            maxResultCount: 5,
            languageCode: 'en',
          }),
        },
        'search',
      );
      if (!data) return null;
      const hits: any[] = Array.isArray(data.places) ? data.places : [];
      const best = hits
        .filter((p) => typeof p?.id === 'string' && typeof p.location?.latitude === 'number')
        .filter((p) => sameName(String(p.displayName?.text ?? ''), name))
        .map((p) => ({
          id: p.id as string,
          metres: distanceM(near, { lat: p.location.latitude, lng: p.location.longitude }),
        }))
        .filter((c) => c.metres <= MATCH_RADIUS_M)
        .sort((a, b) => a.metres - b.metres)[0];
      return { id: best?.id ?? null };
    },

    async details(id) {
      const key = await apiKey();
      if (!key) return null;
      const data = await send(
        `${API}/places/${encodeURIComponent(id)}?languageCode=en`,
        { headers: headers(key, DETAILS_FIELDS) },
        'details',
      );
      return data ? toPlace(data) : null;
    },

    async photos(id, max) {
      const key = await apiKey();
      if (!key) return [];
      const listing = await send(
        `${API}/places/${encodeURIComponent(id)}`,
        { headers: headers(key, PHOTO_FIELDS) },
        'photos',
      );
      const refs: any[] = (Array.isArray(listing?.photos) ? listing.photos : [])
        .filter((p: any) => typeof p?.name === 'string' && /^places\/[^/\s]+\/photos\/[^/\s]+$/.test(p.name))
        .slice(0, max);
      // Three at most, at once: Google answers a burst of photo requests with 429.
      const out = await Promise.all(
        refs.map(async (p): Promise<GooglePhoto | null> => {
          const link = await send(
            `${API}/${p.name}/media?key=${encodeURIComponent(key)}&maxWidthPx=800&skipHttpRedirect=true`,
            {},
            'photo',
          );
          const url = https(link?.photoUri);
          if (!url) return null;
          const credit = p.authorAttributions?.[0];
          return { url, author: String(credit?.displayName ?? ''), authorUri: https(credit?.uri) };
        }),
      );
      return out.filter((p): p is GooglePhoto => p !== null);
    },
  };
}
