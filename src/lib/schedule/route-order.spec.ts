import { describe, expect, it } from 'vitest';
import {
	applySavedOrder,
	defaultRouteOrder,
	enforceAnchorOrder,
	isAnchor,
	moveAnytimeStop,
	routeStops,
	serializeRouteOrder,
	type RouteStop
} from '$lib/schedule/route-order';
import type { ScheduleVisit } from '$lib/schedule/api';
import type { AssessmentItem, EventItem, VisitItem } from '$lib/schedule/items';

const TODAY = '2026-09-03';

function visit(overrides: Partial<ScheduleVisit> & { id: string }): VisitItem {
	return {
		kind: 'visit',
		job_id: 'job-1',
		visit_date: TODAY,
		start_time: '09:00:00',
		end_time: '10:00:00',
		all_day: false,
		title: null,
		completed_at: null,
		revision: 1,
		position: 0,
		assignee_ids: [],
		job_number: 1,
		job_title: 'Gutter clean',
		client_id: 'client-1',
		client_name: 'Dana Reed',
		client_company_name: null,
		property_id: 'property-1',
		property_label: null,
		property_address_line1: '4 Elm Street',
		property_city: 'Austin',
		property_state_region: 'TX',
		property_postal_code: '78701',
		...overrides
	};
}

function assessment(overrides: Partial<AssessmentItem> & { id: string }): AssessmentItem {
	return {
		kind: 'assessment',
		request_id: 'request-1',
		visit_date: TODAY,
		start_time: '08:00:00',
		end_time: '08:30:00',
		all_day: false,
		completed_at: null,
		assignee_ids: [],
		request_title: 'Roof look',
		request_status: 'assessment_scheduled',
		client_id: 'client-2',
		client_name: 'Sam Cole',
		client_company_name: null,
		property_id: 'property-2',
		property_label: null,
		property_address_line1: '9 Oak Road',
		property_city: 'Austin',
		property_state_region: 'TX',
		property_postal_code: '78702',
		...overrides
	};
}

function event(id: string): EventItem {
	return {
		kind: 'event',
		id,
		title: 'Team meeting',
		description: null,
		visit_date: TODAY,
		start_time: '07:00:00',
		end_time: '07:30:00',
		all_day: false,
		completed_at: null,
		assignee_ids: []
	};
}

describe('routeStops', () => {
	it('keeps Visits and Assessments but never Events', () => {
		const stops = routeStops([visit({ id: 'v' }), assessment({ id: 'a' }), event('e')]);
		expect(stops.map((s) => s.id)).toEqual(['v', 'a']);
	});

	it('drops an item with no date, which has no day to be routed on', () => {
		const stops = routeStops([visit({ id: 'v' }), visit({ id: 'undated', visit_date: null })]);
		expect(stops.map((s) => s.id)).toEqual(['v']);
	});
});

describe('isAnchor', () => {
	it('anchors a fixed-time Visit', () => {
		expect(isAnchor(visit({ id: 'v', start_time: '09:00:00' }))).toBe(true);
	});

	it('leaves an Anytime Visit movable', () => {
		expect(isAnchor(visit({ id: 'v', start_time: null }))).toBe(false);
	});

	it('anchors every Assessment, even a time-less one', () => {
		expect(isAnchor(assessment({ id: 'a', start_time: '08:00:00' }))).toBe(true);
		expect(isAnchor(assessment({ id: 'a', start_time: null, all_day: true }))).toBe(true);
	});
});

describe('defaultRouteOrder', () => {
	it('reads anchors in clock order, then Anytime work at the end', () => {
		const order = defaultRouteOrder([
			visit({ id: 'anytime', start_time: null }),
			visit({ id: 'noon', start_time: '12:00:00' }),
			assessment({ id: 'assess', start_time: '08:00:00' }),
			visit({ id: 'dawn', start_time: '07:00:00' })
		]);
		expect(order.map((s) => s.id)).toEqual(['dawn', 'assess', 'noon', 'anytime']);
	});

	it('sinks a time-less Assessment below the timed anchors', () => {
		const order = defaultRouteOrder([
			assessment({ id: 'timeless', start_time: null, all_day: true }),
			visit({ id: 'timed', start_time: '10:00:00' })
		]);
		expect(order.map((s) => s.id)).toEqual(['timed', 'timeless']);
	});

	it('orders Anytime work by the position the Job gave it, tiebroken by id', () => {
		const order = defaultRouteOrder([
			visit({ id: 'b', start_time: null, position: 2 }),
			visit({ id: 'a', start_time: null, position: 2 }),
			visit({ id: 'first', start_time: null, position: 1 })
		]);
		expect(order.map((s) => s.id)).toEqual(['first', 'a', 'b']);
	});
});

describe('enforceAnchorOrder', () => {
	it('keeps movable stops in place but re-settles anchors chronologically', () => {
		// A hand-built list that puts the anchors out of clock order.
		const order: RouteStop[] = [
			visit({ id: 'late', start_time: '15:00:00' }),
			visit({ id: 'anytime', start_time: null }),
			visit({ id: 'early', start_time: '08:00:00' })
		];
		expect(enforceAnchorOrder(order).map((s) => s.id)).toEqual(['early', 'anytime', 'late']);
	});
});

describe('applySavedOrder', () => {
	const stops = [
		visit({ id: 'anytime1', start_time: null }),
		visit({ id: 'anytime2', start_time: null }),
		visit({ id: 'nine', start_time: '09:00:00' }),
		visit({ id: 'noon', start_time: '12:00:00' })
	];

	it('restores a saved arrangement of the Anytime stops around the anchors', () => {
		const saved = ['anytime2', 'nine', 'anytime1', 'noon'];
		expect(applySavedOrder(stops, saved).map((s) => s.id)).toEqual([
			'anytime2',
			'nine',
			'anytime1',
			'noon'
		]);
	});

	it('never lets a saved order reorder the anchors out of clock time', () => {
		// The saved order tries to put noon before nine; the anchors must still read nine, then noon.
		const saved = ['noon', 'anytime1', 'nine'];
		const order = applySavedOrder(stops, saved);
		const anchorIds = order.filter((s) => isAnchor(s)).map((s) => s.id);
		expect(anchorIds).toEqual(['nine', 'noon']);
	});

	it('ignores ids that are no longer present', () => {
		const saved = ['gone', 'nine', 'anytime1'];
		const order = applySavedOrder(stops, saved);
		expect(order.map((s) => s.id)).not.toContain('gone');
		expect(order).toHaveLength(stops.length);
	});

	it('drops a new Anytime stop at the end and slots a new anchor into clock order', () => {
		const saved = ['anytime1', 'nine']; // anytime2 and noon are new since the save
		const withNew = [...stops, visit({ id: 'dawn', start_time: '06:00:00' })];
		const order = applySavedOrder(withNew, saved);
		const anchorIds = order.filter((s) => isAnchor(s)).map((s) => s.id);
		expect(anchorIds).toEqual(['dawn', 'nine', 'noon']);
		// The Anytime stop never ranked waits at the very end.
		expect(order[order.length - 1].id).toBe('anytime2');
	});
});

describe('moveAnytimeStop', () => {
	const order: RouteStop[] = [
		visit({ id: 'nine', start_time: '09:00:00' }),
		visit({ id: 'anytime', start_time: null }),
		visit({ id: 'noon', start_time: '12:00:00' })
	];

	it('moves an Anytime stop to a new slot', () => {
		expect(moveAnytimeStop(order, 'anytime', 0).map((s) => s.id)).toEqual([
			'anytime',
			'nine',
			'noon'
		]);
	});

	it('refuses to move an anchor', () => {
		expect(moveAnytimeStop(order, 'nine', 2)).toBe(order);
	});

	it('keeps the anchors in clock order after a move', () => {
		const moved = moveAnytimeStop(order, 'anytime', 3);
		expect(moved.filter((s) => isAnchor(s)).map((s) => s.id)).toEqual(['nine', 'noon']);
	});

	it('is a no-op for an unknown id', () => {
		expect(moveAnytimeStop(order, 'ghost', 0)).toBe(order);
	});
});

describe('serializeRouteOrder', () => {
	it('gives the ids in their current order', () => {
		const order: RouteStop[] = [visit({ id: 'a' }), visit({ id: 'b' })];
		expect(serializeRouteOrder(order)).toEqual(['a', 'b']);
	});
});
