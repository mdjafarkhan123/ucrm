import { describe, expect, it } from 'vitest';
import {
	businessClock,
	historyHeadline,
	historyLines,
	spanMinutes,
	type HistoryEvent,
	type HistoryValues
} from './corrections';

const ANA = '11111111-1111-4111-8111-111111111111';
const BEN = '22222222-2222-4222-8222-222222222222';
const JOB = '33333333-3333-4333-8333-333333333333';
const TZ = 'America/New_York';

function values(overrides: Partial<HistoryValues> = {}): HistoryValues {
	return {
		kind: 'job',
		user_id: ANA,
		user_name: 'Ana Silva',
		job_id: JOB,
		job_number: 20,
		visit_id: null,
		visit_date: null,
		// 8:00 AM in New York on Oct 5.
		started_at: '2026-10-05T12:00:00Z',
		minutes: 240,
		notes: null,
		...overrides
	};
}

function event(overrides: Partial<HistoryEvent> = {}): HistoryEvent {
	return {
		id: 'e1',
		action: 'changed',
		at: '2026-10-06T14:00:00Z',
		actor_name: 'Sam Lee',
		is_me: false,
		prior: values(),
		new: values(),
		...overrides
	};
}

describe('spanMinutes', () => {
	it('counts minutes between two times on the same day', () => {
		expect(spanMinutes('08:00', '12:30')).toBe(270);
	});

	it('treats an end before the start as the next morning', () => {
		expect(spanMinutes('22:00', '06:00')).toBe(480);
	});

	it('treats an end equal to the start as a full day', () => {
		expect(spanMinutes('08:00', '08:00')).toBe(1440);
	});
});

describe('businessClock', () => {
	it('reads an instant on the business clock, not the device clock', () => {
		expect(businessClock('2026-10-05T03:30:00Z', TZ)).toEqual({ day: '2026-10-04', time: '23:30' });
	});

	it('uses a 24-hour clock with a leading zero', () => {
		expect(businessClock('2026-10-05T13:05:00Z', TZ)).toEqual({ day: '2026-10-05', time: '09:05' });
	});
});

describe('historyHeadline', () => {
	it('names who did it', () => {
		expect(historyHeadline(event({ action: 'added' }))).toBe('Added by Sam Lee');
	});

	it('says "you" for the reader', () => {
		expect(historyHeadline(event({ is_me: true }))).toBe('Changed by you');
	});

	it('covers someone who has left', () => {
		expect(historyHeadline(event({ action: 'deleted', actor_name: null }))).toBe(
			'Deleted by someone who has left'
		);
	});
});

describe('historyLines', () => {
	it('says what an approval means', () => {
		const approval = event({ action: 'approved', prior: null, new: null });
		expect(historyHeadline(approval)).toBe('Approved by Sam Lee');
		expect(historyLines(approval, TZ)).toEqual([
			'Locked for people who change only their own hours.'
		]);
	});

	it('lists what an added entry was', () => {
		const lines = historyLines(
			event({ action: 'added', prior: null, new: values({ notes: 'Fence posts' }) }),
			TZ
		);
		expect(lines).toEqual([
			'Person: Ana Silva',
			'For: Job #20',
			'Time: Oct 5, 8:00 AM – 12:00 PM',
			'Duration: 4h',
			'Notes: Fence posts'
		]);
	});

	it('shows a still-running start without an end', () => {
		const lines = historyLines(
			event({ action: 'added', prior: null, new: values({ kind: 'general', minutes: null }) }),
			TZ
		);
		expect(lines).toContain('For: General');
		expect(lines).toContain('Time: Oct 5, from 8:00 AM');
	});

	it('shows only the fields that changed, old and new', () => {
		const lines = historyLines(
			event({ new: values({ started_at: '2026-10-05T11:30:00Z', minutes: 270 }) }),
			TZ
		);
		expect(lines).toEqual(['Time: Oct 5, 8:00 AM – 12:00 PM → Oct 5, 7:30 AM – 12:00 PM']);
	});

	it('reports a person change and a move to General', () => {
		const lines = historyLines(
			event({
				new: values({
					user_id: BEN,
					user_name: 'Ben Ortiz',
					kind: 'general',
					job_id: null,
					job_number: null
				})
			}),
			TZ
		);
		expect(lines).toEqual(['Person: Ana Silva → Ben Ortiz', 'For: Job #20 → General']);
	});

	it('describes notes added, changed and removed', () => {
		expect(historyLines(event({ new: values({ notes: 'Gate' }) }), TZ)).toEqual([
			'Notes added: “Gate”'
		]);
		expect(
			historyLines(event({ prior: values({ notes: 'Gate' }), new: values({ notes: 'Fence' }) }), TZ)
		).toEqual(['Notes: “Gate” → “Fence”']);
		expect(historyLines(event({ prior: values({ notes: 'Gate' }) }), TZ)).toEqual([
			'Notes removed'
		]);
	});

	it('does not invent a notes change when the old notes were never kept', () => {
		const prior = values();
		delete prior.notes;
		expect(historyLines(event({ prior, new: values({ notes: 'Gate' }) }), TZ)).toEqual([]);
	});
});
