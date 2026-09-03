// The narrow boundary Schedule depends on to turn a property's address into coordinates. Everything above
// this line -- the on-save geocode path, the Map's stop list -- talks only to the `Geocoder` interface and
// the three result shapes below, never to a map provider directly. The managed Mapbox implementation (7b)
// plugs in behind it later without any caller changing; a deterministic mock stands in until real tokens
// verify geocoding, rate limits and errors. Provider boundary decision: docs/schedule-behavior-contract.md
// "Map/directions provider boundary".

/** A property address to geocode. The same fields the window read already carries for a Visit or Assessment. */
export type GeocodeAddress = {
	line1: string | null;
	city: string | null;
	state_region: string | null;
	postal_code: string | null;
};

// The outcome of a *successful* provider call. `found` carries coordinates ready to store on the property
// (matching the `properties.latitude`/`longitude` columns); `not_found` means the provider ran and the
// address simply does not resolve. `not_found` is a durable fact about the address -- it is recorded so the
// stop keeps its place in the route list with an explanation, never silently dropped. It is NOT a provider
// failure: a network error or rate-limit is a `GeocodingProviderError` (below) that should be retried, not
// mistaken for an unresolvable address.
export type GeocodeResult =
	{ status: 'found'; latitude: number; longitude: number } | { status: 'not_found' };

// The provider could not give an answer at all -- network, timeout, rate-limit, auth. Distinct from
// `not_found` so the caller retries later instead of marking a real address ungeocodable. `retryable` mirrors
// the send-path convention in communications/brevo.ts: a 429/5xx/timeout is worth another attempt; a 4xx auth
// or quota rejection is not.
export class GeocodingProviderError extends Error {
	constructor(
		message: string,
		public readonly retryable: boolean,
		public readonly code: string
	) {
		super(message);
		this.name = 'GeocodingProviderError';
	}
}

/** The one thing Schedule asks of a map provider: resolve an address to coordinates, or say it cannot. */
export interface Geocoder {
	geocode(address: GeocodeAddress): Promise<GeocodeResult>;
}

// The provider's single-string query for an address, and the key a fixture is looked up by. Joins the parts
// that are present, collapses whitespace and lowercases so the same address keys the same way however it was
// typed. An address with nothing to geocode returns an empty string, which the mock treats as `not_found`.
export function geocodeQuery(address: GeocodeAddress): string {
	return [address.line1, address.city, address.state_region, address.postal_code]
		.map((part) => part?.trim())
		.filter((part): part is string => !!part)
		.join(', ')
		.replace(/\s+/g, ' ')
		.toLowerCase();
}
