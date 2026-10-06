import { describe, expect, it } from 'vitest';
import {
	deliveryBlockers,
	trainingDetailsOpen,
	trainingStatus,
	type SetupHandover,
	type SetupTraining
} from './training';

const training: SetupTraining = {
	attendees: [{ name: 'Sam', role: 'Owner', email: 'sam@example.com' }],
	time_zone: 'Europe/London',
	preferred_times: 'Weekday mornings',
	needs: null,
	top_tasks: null,
	details_updated_at: '2026-10-20T09:00:00Z',
	details_updated_by_name: 'Sam',
	recording_consent: null,
	consent_changed_at: null,
	consent_changed_by_name: null,
	skipped_at: null,
	skipped_by_name: null,
	meeting_at: null,
	meeting_url: null,
	booked_at: null
};
const handover: SetupHandover = {
	live_at: '2026-10-24T09:00:00Z',
	live_version: 2,
	access_summary: 'You own the domain and the Google profile.',
	guides: [{ title: 'Quotes', url: 'https://example.com/quotes' }],
	updated_at: '2026-10-24T09:00:00Z',
	delivered_at: null
};
const booked = {
	...training,
	meeting_at: '2026-10-27T10:00:00Z',
	meeting_url: 'https://meet.google.com/abc-defg-hij',
	booked_at: '2026-10-24T10:00:00Z'
};

describe('training', () => {
	it('moves from details to booked, or is settled by an owner skip', () => {
		expect(trainingStatus(null)).toBe('not_started');
		expect(trainingStatus(training)).toBe('details_given');
		expect(trainingStatus(booked)).toBe('booked');
		expect(trainingStatus({ ...training, skipped_at: '2026-10-25T09:00:00Z' })).toBe('skipped');
	});

	it('lets the client change the details only until Uplift books or the owner says no', () => {
		expect(trainingDetailsOpen(null)).toBe(true);
		expect(trainingDetailsOpen(training)).toBe(true);
		expect(trainingDetailsOpen(booked)).toBe(false);
		expect(trainingDetailsOpen({ ...training, skipped_at: '2026-10-25T09:00:00Z' })).toBe(false);
	});
});

describe('deliveryBlockers', () => {
	it('needs Live, training booked or skipped, the access summary and a guide', () => {
		expect(deliveryBlockers(null, null)).toEqual([
			'not_live',
			'training',
			'access_summary',
			'guides'
		]);
		expect(deliveryBlockers(handover, training)).toEqual(['training']);
		expect(deliveryBlockers(handover, booked)).toEqual([]);
		expect(deliveryBlockers(handover, { ...training, skipped_at: '2026-10-25T09:00:00Z' })).toEqual(
			[]
		);
		expect(deliveryBlockers({ ...handover, guides: [] }, booked)).toEqual(['guides']);
	});

	it('is blocked again when a booking is cancelled before delivery', () => {
		expect(deliveryBlockers(handover, { ...booked, meeting_at: null })).toEqual(['training']);
	});
});
