// The one place the running app decides WHICH geocoder the background worker uses. 7b wires managed Mapbox here
// behind the same `Geocoder` interface; until then no real provider is configured.
//
// Deliberately NOT the mock: running the mock against real properties would fabricate plausible-but-wrong
// coordinates for every address and mark anything unpinned that it cannot resolve — corrupting real data. So the
// live worker route stays inert (503) until 7b provisions Mapbox tokens and verifies geocoding for real. The
// mock is injected directly in tests, never resolved here.

import type { Geocoder } from '$lib/server/geocoding/geocoder';

// True once a real geocoding provider is configured (7b). The worker route refuses to run while this is false.
export function isGeocodingConfigured(): boolean {
	return false;
}

// Resolve the configured live geocoder. Throws until 7b wires Mapbox — callers must gate on
// isGeocodingConfigured() first.
export function resolveGeocoder(): Geocoder {
	throw new Error(
		'No geocoding provider is configured. Managed Mapbox is wired in Schedule Part 7b; until then the ' +
			'background geocoding worker is inert.'
	);
}
