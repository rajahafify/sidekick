// Place search for the "Where" field and for check-ins, on Amazon Location Service (Places v2).
// Called with the Lambda's IAM role, so there is no key to leak.
import {
  SuggestCommand,
  GeoPlacesClient,
  GetPlaceCommand,
  SearchNearbyCommand,
} from '@aws-sdk/client-geo-places';

export type PlaceSuggestion = { placeId: string; name: string; address: string };
export type PlaceDetails = PlaceSuggestion & { lat: number; lng: number };

export interface Places {
  suggest(input: string, near?: { lat: number; lng: number }): Promise<PlaceSuggestion[]>;
  details(placeId: string): Promise<PlaceDetails | null>;
  nearby(lat: number, lng: number): Promise<PlaceDetails[]>;
}

const nameOf = (title?: string, label?: string) => (title || label?.split(',')[0] || '').trim();
const addressOf = (label: string | undefined, name: string) =>
  (label ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s && s !== name)
    .slice(0, 3)
    .join(', ');

// Place search needs a position to rank around. Without the user's own, use the country's main city.
const CAPITALS: Record<string, [number, number]> = {
  MYS: [101.6869, 3.139], // Kuala Lumpur
  SGP: [103.8198, 1.3521],
  IDN: [106.8456, -6.2088], // Jakarta
  THA: [100.5018, 13.7563], // Bangkok
  PHL: [120.9842, 14.5995], // Manila
  VNM: [106.6297, 10.8231], // Ho Chi Minh City
};

export function locationPlaces(region: string, countries: string[]): Places {
  const client = new GeoPlacesClient({ region });
  const filter = countries.length ? { IncludeCountries: countries } : undefined;
  const fallbackBias = CAPITALS[countries[0] ?? 'MYS'] ?? CAPITALS.MYS;
  return {
    // Suggest, not Autocomplete: Autocomplete isn't offered in ap-southeast-1 (GrabMaps data).
    async suggest(input, near) {
      const r = await client.send(
        new SuggestCommand({
          QueryText: input.slice(0, 200),
          MaxResults: 5,
          Filter: filter,
          BiasPosition: near ? [near.lng, near.lat] : fallbackBias,
        }),
      );
      return (r.ResultItems ?? [])
        .filter((i) => i.SuggestResultItemType === 'Place' && i.Place?.PlaceId)
        .map((i) => {
          const name = nameOf(i.Title, i.Place?.Address?.Label);
          return { placeId: i.Place!.PlaceId!, name, address: addressOf(i.Place?.Address?.Label, name) };
        });
    },
    async details(placeId) {
      const r = await client.send(new GetPlaceCommand({ PlaceId: placeId }));
      const [lng, lat] = r.Position ?? [];
      if (typeof lat !== 'number' || typeof lng !== 'number') return null;
      const name = nameOf(r.Title, r.Address?.Label);
      return { placeId, name, address: addressOf(r.Address?.Label, name), lat, lng };
    },
    async nearby(lat, lng) {
      const r = await client.send(
        new SearchNearbyCommand({ QueryPosition: [lng, lat], QueryRadius: 400, MaxResults: 12 }),
      );
      return (r.ResultItems ?? [])
        .filter((i) => i.PlaceId && i.Position)
        .map((i) => {
          const name = nameOf(i.Title, i.Address?.Label);
          return {
            placeId: i.PlaceId!,
            name,
            address: addressOf(i.Address?.Label, name),
            lng: i.Position![0],
            lat: i.Position![1],
          };
        });
    },
  };
}
