// Schedule Part 7b-B: the real geocoder behind the `Geocoder` interface, wired in by `provider.ts` once a
// secret (sk.) Mapbox token is configured. Uses the same v6 forward endpoint and response shape as the
// display-only lookup in `$lib/schedule/geocode-client.ts`, but with `permanent=true` -- the tier that grants
// the right to store the coordinate on the property row, per docs/schedule-behavior-contract.md
// "Map/directions provider boundary".
//
// A hung provider call must not hold a worker slot until it becomes a stale claim, so every call is bounded
// by an explicit abort -- same convention as communications/brevo.ts's PROVIDER_SEND_TIMEOUT_MS.

import { buildForwardGeocodeUrl, parseForwardGeocode } from '$lib/schedule/geocode-client';
import {
	geocodeQuery,
	GeocodingProviderError,
	type GeocodeAddress,
	type GeocodeResult,
	type Geocoder
} from '$lib/server/geocoding/geocoder';

const PROVIDER_TIMEOUT_MS = 10_000;

// Same numeric(9,6) rounding the mock uses, so a stored coordinate never depends on floating-point noise past
// the column's precision.
function round6(value: number): number {
	return Math.round(value * 1_000_000) / 1_000_000;
}

export function createMapboxGeocoder(token: string): Geocoder {
	return {
		async geocode(address: GeocodeAddress): Promise<GeocodeResult> {
			const query = geocodeQuery(address);
			if (query === '') return { status: 'not_found' };

			let response: Response;
			try {
				response = await fetch(buildForwardGeocodeUrl(query, token, { permanent: true }), {
					signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS)
				});
			} catch {
				throw new GeocodingProviderError(
					'Mapbox did not return a response.',
					true,
					'mapbox_network_unknown'
				);
			}

			if (!response.ok) {
				const retryable =
					response.status === 408 || response.status === 429 || response.status >= 500;
				throw new GeocodingProviderError(
					`Mapbox rejected the request with status ${response.status}.`,
					retryable,
					`mapbox_http_${response.status}`
				);
			}

			const point = parseForwardGeocode(await response.json());
			if (!point) return { status: 'not_found' };
			return { status: 'found', latitude: round6(point.lat), longitude: round6(point.lng) };
		}
	};
}
