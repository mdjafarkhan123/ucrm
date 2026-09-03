import {
	geocodeQuery,
	type GeocodeAddress,
	type GeocodeResult,
	type Geocoder
} from '$lib/server/geocoding/geocoder';

// A stand-in geocoder with no network, so 7a's on-save path, stop list and Map workspace can be built and
// tested before Mapbox tokens exist. It is deliberately deterministic: the same address always resolves to the
// same coordinates, so a spec, a seeded row and a hand-typed dev address stay stable across runs.
//
// Two behaviours matter for the callers it feeds:
//   - an address with nothing to geocode (all parts blank) resolves to `not_found`, exercising the
//     "kept in the stop list with an explanation" path;
//   - an explicit fixture wins over the derived coordinate, so a test can pin one address to exact
//     coordinates or force a real-looking address to `not_found`.
// It never throws GeocodingProviderError -- a test that needs the provider-down path builds its own throwing
// Geocoder against the interface. This mock only ever answers `found` or `not_found`.

// A plausible continental-US bounding box, so a derived coordinate reads like a real place on the map rather
// than landing in the ocean at (0,0). Not contractual -- only the mock cares about these bounds.
const LAT_MIN = 24;
const LAT_MAX = 49;
const LNG_MIN = -125;
const LNG_MAX = -66;

// FNV-1a: a small, stable string hash. Two independent 32-bit streams (the query, and the query with a salt)
// give latitude and longitude that vary together per address without correlating to each other.
function fnv1a(input: string): number {
	let hash = 0x811c9dc5;
	for (let i = 0; i < input.length; i++) {
		hash ^= input.charCodeAt(i);
		hash = Math.imul(hash, 0x01000193);
	}
	return hash >>> 0;
}

// Map a 32-bit hash onto [min, max], rounded to 6 decimals to fit properties.latitude/longitude numeric(9,6).
function scale(hash: number, min: number, max: number): number {
	const fraction = hash / 0xffffffff;
	return Math.round((min + fraction * (max - min)) * 1_000_000) / 1_000_000;
}

/**
 * A deterministic, network-free geocoder for development and tests. Pass `fixtures` (keyed by
 * `geocodeQuery(address)`) to pin specific addresses; anything unpinned resolves to a stable derived
 * coordinate, and an address with nothing to geocode resolves to `not_found`.
 */
export function createMockGeocoder(fixtures: Record<string, GeocodeResult> = {}): Geocoder {
	return {
		async geocode(address: GeocodeAddress): Promise<GeocodeResult> {
			const query = geocodeQuery(address);
			if (query in fixtures) return fixtures[query];
			if (query === '') return { status: 'not_found' };
			return {
				status: 'found',
				latitude: scale(fnv1a(query), LAT_MIN, LAT_MAX),
				longitude: scale(fnv1a(`lng:${query}`), LNG_MIN, LNG_MAX)
			};
		}
	};
}
