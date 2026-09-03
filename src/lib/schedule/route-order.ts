import type { AssessmentItem, ScheduleItem, VisitItem } from '$lib/schedule/items';
import { clockMinutes } from '$lib/schedule/layout';

// The order one employee's stops read in on the Map for a chosen day, and the rules for changing it.
//
// This is arithmetic on a list, not markup, so it lives here where it can be tested on its own. A route stop
// is one place a crew has to be that day: a job Visit or a Request-owned on-site Assessment. A Schedule Event
// is a whole-team block with no location and no crew, so it is never a stop.
//
// Two kinds of stop behave differently. A fixed-time Visit and *every* Assessment are anchors: their place in
// the day is set by a clock time -- or, for an Assessment, by the Request that owns it -- and the dispatcher
// cannot reorder them here. Only an Anytime Visit (a dated Visit with no clock time) is draggable, moving
// before, between or after the anchors. Whatever the dispatcher saves, the anchor subsequence always reads in
// chronological order; the saved order only ever records where the Anytime stops sit around them.

/** A place on the route: a Visit or an Assessment. Events are excluded upstream, so they never appear here. */
export type RouteStop = VisitItem | AssessmentItem;

// Only Visits and Assessments with a date can be routed. Events have no location, and an undated item has no
// day to be routed on -- the window read never returns one, but the guard keeps this honest if it ever does.
export function routeStops(items: ScheduleItem[]): RouteStop[] {
	return items.filter(
		(item): item is RouteStop => item.kind !== 'event' && item.visit_date !== null
	);
}

// An anchor is a stop the dispatcher may not reorder: every Assessment (its order is Request-owned and
// read-only until Requests exposes a route action) and any Visit that has a clock time. An Anytime Visit has
// no clock time and is the only draggable stop.
export function isAnchor(stop: RouteStop): boolean {
	if (stop.kind === 'assessment') return true;
	return clockMinutes(stop.start_time) !== null;
}

// Anchors read in start-time order. A time-less anchor -- an Anytime Assessment -- has no place on the clock,
// so it sinks below the timed anchors in a stable, id-tiebroken order rather than jumping around on a refetch.
function byChronology(a: RouteStop, b: RouteStop): number {
	const am = clockMinutes(a.start_time);
	const bm = clockMinutes(b.start_time);
	if (am === null && bm === null) return a.id.localeCompare(b.id);
	if (am === null) return 1;
	if (bm === null) return -1;
	return am - bm || a.id.localeCompare(b.id);
}

// Anytime Visits keep the position the Job gave them until a dispatcher drags one, tiebroken by id so a clash
// is stable. Only Visits are ever movable, so `position` is always present here; the guard is for the types.
function byPosition(a: RouteStop, b: RouteStop): number {
	const ap = 'position' in a ? a.position : 0;
	const bp = 'position' in b ? b.position : 0;
	return ap - bp || a.id.localeCompare(b.id);
}

// The order a route reads in before anyone has saved one: anchors in clock order first, then the Anytime work
// waiting at the end for the dispatcher to slot in. A clear, predictable starting point, not a guess at the
// best route -- automatic optimization is a later release.
export function defaultRouteOrder(stops: RouteStop[]): RouteStop[] {
	const anchors = stops.filter(isAnchor).sort(byChronology);
	const movable = stops.filter((stop) => !isAnchor(stop)).sort(byPosition);
	return [...anchors, ...movable];
}

// Keep the movable stops exactly where they sit, but force the anchors to read chronologically among
// themselves. A saved order or a drag can put an Anytime Visit anywhere; it can never reorder the anchors,
// because a fixed time -- and an Assessment's Request-owned order -- is not the dispatcher's to change here.
export function enforceAnchorOrder(order: RouteStop[]): RouteStop[] {
	const anchors = order.filter(isAnchor).sort(byChronology);
	let next = 0;
	return order.map((stop) => (isAnchor(stop) ? anchors[next++] : stop));
}

// Rebuild the route from a saved id order against the stops actually in hand. Ids that have since gone are
// dropped; stops added since the save were never ranked, so they fall in at the default -- a new Anytime Visit
// waits at the end while a new anchor still lands in clock order once anchors are enforced.
export function applySavedOrder(stops: RouteStop[], savedOrder: string[]): RouteStop[] {
	const byId = new Map(stops.map((stop) => [stop.id, stop]));
	const placed: RouteStop[] = [];
	const seen = new Set<string>();
	for (const id of savedOrder) {
		const stop = byId.get(id);
		if (stop && !seen.has(id)) {
			placed.push(stop);
			seen.add(id);
		}
	}
	const news = stops.filter((stop) => !seen.has(stop.id));
	return enforceAnchorOrder([...placed, ...defaultRouteOrder(news)]);
}

// Move one Anytime Visit to a new slot. An anchor never moves -- a drag on one is a no-op -- and after the
// move the anchors are re-settled into clock order so the invariant holds however the stop was dropped.
export function moveAnytimeStop(
	order: RouteStop[],
	stopId: string,
	targetIndex: number
): RouteStop[] {
	const from = order.findIndex((stop) => stop.id === stopId);
	if (from === -1 || isAnchor(order[from])) return order;
	const next = [...order];
	const [moved] = next.splice(from, 1);
	const clamped = Math.max(0, Math.min(targetIndex, next.length));
	next.splice(clamped, 0, moved);
	return enforceAnchorOrder(next);
}

/** The ids in their current order, ready to persist when the dispatcher hits Save Route Order. */
export function serializeRouteOrder(order: RouteStop[]): string[] {
	return order.map((stop) => stop.id);
}
