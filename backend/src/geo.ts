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
            .replace(/[̀-ͯ]/g, '')
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
