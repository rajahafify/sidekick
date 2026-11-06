export type LatLng = { lat: number; lng: number };
export type Fix = LatLng & { accuracy: number };

/** How close you need to be to check in. Generous, because GPS is rough indoors. */
export const GEOFENCE_M = 500;

/** Great-circle distance in metres. */
export function distanceM(a: LatLng, b: LatLng): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

/** A fuzzy fix gets the benefit of the doubt up to 1 km of reported accuracy. */
export function insideFence(fix: Fix, place: LatLng, radius = GEOFENCE_M): boolean {
  return distanceM(fix, place) - Math.min(fix.accuracy || 0, 1000) <= radius;
}

export const formatDistance = (m: number) =>
  m < 1000 ? `${Math.round(m / 10) * 10} m` : `${(m / 1000).toFixed(m < 10000 ? 1 : 0)} km`;

/**
 * The id of a place's room for one day: everyone who checks in at the same place on the same
 * local day shares it. `day` is the person's local date as yyyymmdd.
 */
export function placeRoomId(placeId: string | null | undefined, text: string, day: string): string {
  const key =
    placeId
      ? `g-${hash(placeId)}`
      : `t-${
          text
            .split(',')[0]
            .toLowerCase()
            .normalize('NFKD')
            .replace(/[\u0300-\u036f]/g, '')
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/^-+|-+$/g, '')
            .slice(0, 60) || 'somewhere'
        }`;
  return `place-${key}-${day}`;
}

/** Small stable hash (FNV-1a), base 36. */
export function hash(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(36);
}
