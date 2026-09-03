// Building external navigation links. The product never draws turn-by-turn directions itself; it hands the
// dispatcher or crew off to Google or Apple Maps for the actual driving. That hand-off is pure string work --
// no network, no SDK -- so it lives here where it can be tested. It is also independent of the map provider
// (Mapbox), which only draws the route line and markers inside the app; navigation always leaves the product.

export type NavProvider = 'google' | 'apple';

// Somewhere to navigate to. Stored coordinates are used once a property has been geocoded; until then the raw
// address string is handed to the maps app to resolve. A stop with neither cannot be navigated to -- it stays
// in the list with an explanation rather than being silently dropped.
export type NavPlace = {
	lat: number | null;
	lng: number | null;
	address: string | null;
};

export type DirectionsLink =
	| { ok: true; url: string }
	| { ok: false; reason: 'no-destination' }
	| { ok: false; reason: 'too-many-stops'; limit: number };

// How many stops one whole-route link may carry. Google Maps' universal URL accepts up to nine intermediate
// waypoints, which with the final destination is ten stops; Apple's scheme is documented for far fewer, so a
// route link there stays conservative. Neither number is contractual -- re-verify before relying on it. A
// route past the cap still lets every single stop be navigated to on its own.
export const MAX_ROUTE_STOPS: Record<NavProvider, number> = { google: 10, apple: 4 };

// What the maps app is asked to route to: exact coordinates when we have them, otherwise the address text.
// `null` means the stop has no usable location at all.
function placeQuery(place: NavPlace): string | null {
	if (place.lat !== null && place.lng !== null) return `${place.lat},${place.lng}`;
	const address = place.address?.trim();
	return address ? address : null;
}

function singleUrl(provider: NavProvider, query: string): string {
	const q = encodeURIComponent(query);
	return provider === 'google'
		? `https://www.google.com/maps/dir/?api=1&destination=${q}`
		: `https://maps.apple.com/?daddr=${q}`;
}

/** A directions link for one stop. Origin is left to the maps app so it starts from the device's location. */
export function singleStopDirections(place: NavPlace, provider: NavProvider): DirectionsLink {
	const query = placeQuery(place);
	if (query === null) return { ok: false, reason: 'no-destination' };
	return { ok: true, url: singleUrl(provider, query) };
}

// A directions link for the whole route in order. Stops with no usable location are left out of the link
// (they keep their own explanation in the list); the crew drives from the device's location to each in turn.
export function routeDirections(places: NavPlace[], provider: NavProvider): DirectionsLink {
	const queries = places.map(placeQuery).filter((query): query is string => query !== null);
	if (queries.length === 0) return { ok: false, reason: 'no-destination' };
	if (queries.length === 1) return { ok: true, url: singleUrl(provider, queries[0]) };

	const limit = MAX_ROUTE_STOPS[provider];
	if (queries.length > limit) return { ok: false, reason: 'too-many-stops', limit };

	if (provider === 'apple') {
		const daddr = queries.map(encodeURIComponent).join('+to:');
		return { ok: true, url: `https://maps.apple.com/?daddr=${daddr}` };
	}

	const destination = encodeURIComponent(queries[queries.length - 1]);
	const waypoints = queries.slice(0, -1).map(encodeURIComponent).join('%7C');
	return {
		ok: true,
		url: `https://www.google.com/maps/dir/?api=1&destination=${destination}&waypoints=${waypoints}`
	};
}
