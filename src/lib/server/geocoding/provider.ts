// The one place the running app decides WHICH geocoder the background worker uses. 7b-B wires managed Mapbox
// here behind the same `Geocoder` interface, gated on a secret (sk.) token existing.
//
// Deliberately NOT the mock: running the mock against real properties would fabricate plausible-but-wrong
// coordinates for every address and mark anything unpinned that it cannot resolve — corrupting real data. So the
// live worker route stays inert (503) until a real Mapbox token is configured. The mock is injected directly in
// tests, never resolved here.

import { getServerEnv } from '$lib/server/env';
import type { Geocoder } from '$lib/server/geocoding/geocoder';
import { createMapboxGeocoder } from '$lib/server/geocoding/mapbox-geocoder';

// True once a real geocoding provider is configured. The worker route refuses to run while this is false.
export function isGeocodingConfigured(): boolean {
	return !!getServerEnv().MAPBOX_ACCESS_TOKEN;
}

// Resolve the configured live geocoder. Throws until a token is configured — callers must gate on
// isGeocodingConfigured() first.
export function resolveGeocoder(): Geocoder {
	const token = getServerEnv().MAPBOX_ACCESS_TOKEN;
	if (!token) {
		throw new Error(
			'No geocoding provider is configured. Set MAPBOX_ACCESS_TOKEN (a secret sk. token) to enable the ' +
				'background geocoding worker.'
		);
	}
	return createMapboxGeocoder(token);
}
