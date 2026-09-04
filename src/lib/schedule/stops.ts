import type { RouteStop } from '$lib/schedule/route-order';
import { clockLabel } from '$lib/schedule/labels';
import type { NavPlace } from '$lib/schedule/directions';

// How the Map's stop list reads and navigates to one stop, kind-neutrally. A stop is a Visit or an
// on-site Assessment; both carry the same property fields, so the list can describe and route to either one
// without caring which it is. This is pure string and coordinate work -- no markup, no network -- so it lives
// here where it can be tested, the same way route-order and directions do.

/** Where geocoding has reached for a stop's property, as the stop list needs to explain it:
 *  - `located`     — coordinates are stored; the Map can pin it and the route line can reach it.
 *  - `pending`     — the address is queued but not geocoded yet, so there is no pin to draw *yet*.
 *  - `failed`      — the geocoder ran and the address does not resolve; the stop stays in the list, explained.
 *  - `no-address`  — the property has no address at all, so there is nothing to geocode or navigate to.
 * A stop is never dropped for any of these; the list keeps it and says which one it is. */
export type StopGeocodeState = 'located' | 'pending' | 'failed' | 'no-address';

// Coordinates take precedence: once they are stored the stop is located whatever the status column says, so a
// row that has been geocoded reads as placeable even before a later re-queue flips its status. Without
// coordinates the status decides, and a stop with no address to geocode is called out separately from one that
// is merely waiting in the queue.
export function stopGeocodeState(stop: RouteStop): StopGeocodeState {
	if (stop.property_latitude !== null && stop.property_longitude !== null) return 'located';
	if (stop.property_geocode_status === 'failed') return 'failed';
	if (!hasAddress(stop)) return 'no-address';
	return 'pending';
}

function hasAddress(stop: RouteStop): boolean {
	return Boolean(
		stop.property_address_line1 ||
		stop.property_city ||
		stop.property_state_region ||
		stop.property_postal_code
	);
}

/** What the maps app is pointed at: stored coordinates when we have them, otherwise the address text for it to
 * resolve. Handed straight to the Directions builder, which turns it into a Google/Apple deep link. */
export function stopNavPlace(stop: RouteStop): NavPlace {
	return {
		lat: stop.property_latitude,
		lng: stop.property_longitude,
		address: stopAddressLabel(stop)
	};
}

/** The client names the stop. A reader without customers.view gets no name, and the row says so rather than
 * leaving a gap that reads like the stop has no client. */
export function stopClientLabel(stop: RouteStop): string {
	return stop.client_name ?? stop.client_company_name ?? 'Client hidden';
}

/** What the work is: a Visit reads under its own title, then the job's, then the job number; an Assessment
 * reads under its Request's title, then a plain "Assessment". */
export function stopWorkLabel(stop: RouteStop): string {
	if (stop.kind === 'assessment') return stop.request_title ?? 'Assessment';
	return stop.title ?? stop.job_title ?? `Job #${stop.job_number ?? ''}`.trim();
}

/** The one-line address a stop-list row and a Directions link use. Null when the reader may not see the
 * property or it has no address at all. */
export function stopAddressLabel(stop: RouteStop): string | null {
	const street = [stop.property_label, stop.property_address_line1].filter(Boolean).join(' · ');
	const region = [stop.property_city, stop.property_state_region].filter(Boolean).join(', ');
	const line = [street, region, stop.property_postal_code].filter(Boolean).join(' ');
	return line.length > 0 ? line : null;
}

/** The stop's time, as the list shows it: `9am – 11am`, `9am`, or `Anytime`. A stop with no clock time is
 * Anytime whatever its kind. */
export function stopTimeLabel(stop: RouteStop): string {
	const start = clockLabel(stop.start_time);
	if (!start) return 'Anytime';
	const end = clockLabel(stop.end_time);
	return end ? `${start} – ${end}` : start;
}

/** The property a stop sits at, so two stops at one address can share a stacked marker instead of hiding one
 * behind the other. Null when the reader may not see the property. */
export function stopPropertyId(stop: RouteStop): string | null {
	return stop.property_id;
}
