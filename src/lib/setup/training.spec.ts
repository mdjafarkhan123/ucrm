import { describe, expect, it } from 'vitest';
import {
	deliveredCardShowing,
	deliveryBlockers,
	momentToWallClock,
	wallClockToMoment,
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

describe('wallClockToMoment and momentToWallClock', () => {
	it('reads the typed time in the client’s time zone, summer and winter', () => {
		expect(wallClockToMoment('2026-10-20T10:00', 'Europe/London')).toBe('2026-10-20T09:00:00.000Z');
		expect(wallClockToMoment('2026-11-20T10:00', 'Europe/London')).toBe('2026-11-20T10:00:00.000Z');
		expect(wallClockToMoment('2026-10-20T10:00', 'Asia/Dhaka')).toBe('2026-10-20T04:00:00.000Z');
		expect(wallClockToMoment('2026-10-20T10:00', null)).toBe('2026-10-20T10:00:00.000Z');
	});

	it('refuses a half-typed time', () => {
		expect(wallClockToMoment('2026-10-20', 'Europe/London')).toBeNull();
		expect(wallClockToMoment('', 'Europe/London')).toBeNull();
	});

	it('turns a stored moment back into the client’s wall-clock time', () => {
		expect(momentToWallClock('2026-10-20T09:00:00Z', 'Europe/London')).toBe('2026-10-20T10:00');
		expect(momentToWallClock('2026-10-20T04:00:00+00:00', 'Asia/Dhaka')).toBe('2026-10-20T10:00');
	});
});

describe('deliveredCardShowing', () => {
	it('shows Project delivered for 14 days, then hides', () => {
		const delivered = '2026-10-01T12:00:00Z';
		expect(deliveredCardShowing(delivered, new Date('2026-10-01T12:00:00Z'))).toBe(true);
		expect(deliveredCardShowing(delivered, new Date('2026-10-15T11:59:00Z'))).toBe(true);
		expect(deliveredCardShowing(delivered, new Date('2026-10-15T12:00:00Z'))).toBe(false);
	});
});
