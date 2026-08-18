import { describe, expect, it } from 'vitest';
import { deriveRequestStatus, organizationDayRange } from './status';

const NEW_YORK = 'America/New_York';

describe('deriveRequestStatus', () => {
	it('leaves a request without an assessment on its stored status', () => {
		expect(deriveRequestStatus('new', null, NEW_YORK, new Date('2026-08-18T15:00:00Z'))).toBe(
			'new'
		);
	});

	it('reads an assessment with no dates as unscheduled', () => {
		const assessment = { starts_at: null, completed_at: null };
		expect(deriveRequestStatus('new', assessment, NEW_YORK, new Date('2026-08-18T15:00:00Z'))).toBe(
			'unscheduled'
		);
	});

	it('says today for a visit booked earlier the same day', () => {
		const assessment = { starts_at: '2026-08-18T13:00:00Z', completed_at: null };
		// 9am New York, read at 5pm New York. Still today.
		expect(
			deriveRequestStatus('unscheduled', assessment, NEW_YORK, new Date('2026-08-18T21:00:00Z'))
		).toBe('today');
	});

	it('says overdue once the booked day has passed', () => {
		const assessment = { starts_at: '2026-08-17T13:00:00Z', completed_at: null };
		expect(
			deriveRequestStatus('unscheduled', assessment, NEW_YORK, new Date('2026-08-18T21:00:00Z'))
		).toBe('overdue');
	});

	it('says upcoming for a later day', () => {
		const assessment = { starts_at: '2026-08-20T13:00:00Z', completed_at: null };
		expect(
			deriveRequestStatus('unscheduled', assessment, NEW_YORK, new Date('2026-08-18T21:00:00Z'))
		).toBe('upcoming');
	});

	it('uses the contractor timezone, not UTC, at the day boundary', () => {
		// 8pm on the 18th in New York is already the 19th in UTC.
		const assessment = { starts_at: '2026-08-19T00:00:00Z', completed_at: null };
		expect(
			deriveRequestStatus('unscheduled', assessment, NEW_YORK, new Date('2026-08-18T23:00:00Z'))
		).toBe('today');
	});

	it('stops deriving once the assessment is complete', () => {
		const assessment = { starts_at: '2026-08-17T13:00:00Z', completed_at: '2026-08-17T15:00:00Z' };
		expect(
			deriveRequestStatus(
				'assessment_completed',
				assessment,
				NEW_YORK,
				new Date('2026-08-18T21:00:00Z')
			)
		).toBe('assessment_completed');
	});

	it('keeps a converted request converted even with an open assessment', () => {
		const assessment = { starts_at: '2026-08-17T13:00:00Z', completed_at: null };
		expect(
			deriveRequestStatus('converted', assessment, NEW_YORK, new Date('2026-08-18T21:00:00Z'))
		).toBe('converted');
	});
});

describe('organizationDayRange', () => {
	it('spans the contractor calendar day, not the UTC one', () => {
		// 9pm on the 18th in New York. The UTC clock already says the 19th.
		const range = organizationDayRange(NEW_YORK, new Date('2026-08-19T01:00:00Z'));
		expect(range.day_start).toBe('2026-08-18T04:00:00.000Z');
		expect(range.day_end).toBe('2026-08-19T04:00:00.000Z');
	});

	it('handles a timezone ahead of UTC', () => {
		const range = organizationDayRange('Asia/Kolkata', new Date('2026-08-18T02:00:00Z'));
		expect(range.day_start).toBe('2026-08-17T18:30:00.000Z');
		expect(range.day_end).toBe('2026-08-18T18:30:00.000Z');
	});

	it('rolls over the end of a month', () => {
		const range = organizationDayRange('UTC', new Date('2026-08-31T12:00:00Z'));
		expect(range.day_start).toBe('2026-08-31T00:00:00.000Z');
		expect(range.day_end).toBe('2026-09-01T00:00:00.000Z');
	});

	it('stays 25 hours long on the day the clocks go back', () => {
		// New York leaves daylight saving at 2am on 1 November 2026.
		const range = organizationDayRange(NEW_YORK, new Date('2026-11-01T16:00:00Z'));
		expect(range.day_start).toBe('2026-11-01T04:00:00.000Z');
		expect(range.day_end).toBe('2026-11-02T05:00:00.000Z');
	});
});
