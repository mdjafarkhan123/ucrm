import { describe, expect, it } from 'vitest';
import { assessmentToItem, visitToItem } from '$lib/schedule/items';
import type { ScheduleAssessment, ScheduleVisit } from '$lib/schedule/api';

// Asia/Dhaka is UTC+6 with no daylight saving, so the expected wall-clock values are stable to assert.
const DHAKA = 'Asia/Dhaka';

function assessment(overrides: Partial<ScheduleAssessment> = {}): ScheduleAssessment {
	return {
		id: 'a-1',
		request_id: 'req-1',
		starts_at: '2026-09-03T04:00:00Z',
		ends_at: '2026-09-03T05:00:00Z',
		all_day: false,
		completed_at: null,
		instructions: null,
		assignee_ids: [],
		request_title: 'Fix the mount',
		request_status: 'unscheduled',
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

describe('visitToItem', () => {
	it('tags a visit as the visit kind and keeps its fields', () => {
		const item = visitToItem({ id: 'v-1', assignee_ids: ['u-1'] } as unknown as ScheduleVisit);
		expect(item.kind).toBe('visit');
		expect(item.id).toBe('v-1');
	});
});

describe('assessmentToItem', () => {
	it('places a timed assessment on the organization day and clock its instant falls in', () => {
		const item = assessmentToItem(assessment(), DHAKA);
		expect(item.kind).toBe('assessment');
		// 04:00Z is 10:00 in Dhaka, and its day there is the 3rd.
		expect(item.visit_date).toBe('2026-09-03');
		expect(item.start_time).toBe('10:00');
		expect(item.end_time).toBe('11:00');
		expect(item.all_day).toBe(false);
	});

	it('reads an Anytime assessment as a dated, timeless item so it lands in the Anytime lane', () => {
		// Anytime is stored as midnight-to-end-of-day in the booking clock; here the instant is the evening
		// before in UTC, which is the next day in Dhaka.
		const item = assessmentToItem(
			assessment({ starts_at: '2026-09-03T18:00:00Z', ends_at: '2026-09-04T17:59:00Z', all_day: true }),
			DHAKA
		);
		expect(item.visit_date).toBe('2026-09-04');
		expect(item.start_time).toBeNull();
		expect(item.end_time).toBeNull();
		expect(item.all_day).toBe(true);
	});

	it('carries the request, client and property labels through', () => {
		const item = assessmentToItem(assessment(), DHAKA);
		expect(item.request_title).toBe('Fix the mount');
		expect(item.client_name).toBe('Dana Reed');
		expect(item.property_address_line1).toBe('4 Elm Street');
		expect(item.request_id).toBe('req-1');
	});
});
