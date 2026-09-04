// Display-only geocoding for the contextual Map (Schedule 7b, path A2).
//
// This turns a stop's address into coordinates *in the browser, for this session only*, so pins can be shown
// before server-side stored geocoding exists. Mapbox permits this "temporary" geocoding on a public token; it
// is the storing of coordinates that needs a secret token and the permanent endpoint. Nothing here is
// persisted -- the result lives in the TanStack Query cache for the session and is thrown away on reload.
//
// This is a bridge, not the destination. Once the geocoding worker stores coordinates on the property
// (`property_latitude`/`property_longitude`), those win in `stopGeocodeState`, the stop reads as `located`
// without ever reaching this code, and this lookup quietly stops running. Keep it small.
//
// The URL builder and the response parser are pure so they can be tested without the network; only
// `geocodeAddress` touches `fetch`.

const FORWARD_ENDPOINT = 'https://api.mapbox.com/search/geocode/v6/forward';

/** A resolved point, longitude first to match GeoJSON and Mapbox's own order. */
export type GeoPoint = { lng: number; lat: number };

/** Build the Mapbox v6 forward-geocoding URL for one address. `limit=1` -- the Map only needs the best hit. */
export function buildForwardGeocodeUrl(address: string, token: string): string {
	const params = new URLSearchParams({
		q: address,
		access_token: token,
		limit: '1'
	});
	return `${FORWARD_ENDPOINT}?${params.toString()}`;
}

/** Pull the first feature's coordinates out of a Mapbox v6 forward-geocoding response. Returns null when the
 *  address does not resolve or the payload is not the shape we expect, so a bad address never throws -- the
 *  stop simply stays unpinned, exactly as an un-geocoded one does. */
export function parseForwardGeocode(payload: unknown): GeoPoint | null {
	if (typeof payload !== 'object' || payload === null) return null;
	const features = (payload as { features?: unknown }).features;
	if (!Array.isArray(features) || features.length === 0) return null;
	const coordinates = (features[0] as { geometry?: { coordinates?: unknown } })?.geometry
		?.coordinates;
	if (!Array.isArray(coordinates) || coordinates.length < 2) return null;
	const [lng, lat] = coordinates;
	if (typeof lng !== 'number' || typeof lat !== 'number') return null;
	if (!Number.isFinite(lng) || !Number.isFinite(lat)) return null;
	return { lng, lat };
}

/** Geocode one address for display. Returns null on any failure -- an unresolved address is a normal outcome,
 *  not an error to surface. The caller passes an AbortSignal so an in-flight lookup is dropped when the Map
 *  closes. */
export async function geocodeAddress(
	address: string,
	token: string,
	signal?: AbortSignal
): Promise<GeoPoint | null> {
	try {
		const response = await fetch(buildForwardGeocodeUrl(address, token), { signal });
		if (!response.ok) return null;
		return parseForwardGeocode(await response.json());
	} catch {
		return null;
	}
}
