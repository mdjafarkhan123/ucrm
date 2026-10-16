import { describe, expect, it } from 'vitest';
import {
	conversionChange,
	followUpText,
	percentText,
	quoteStatusDetail,
	readQuoteListOverview,
	type QuoteRowFacts
} from './list-overview';

const day = (iso: string) => iso.slice(5, 10);
const base: QuoteRowFacts = {
	status: 'draft',
	sent_at: null,
	decision: null,
	decided_at: null,
	decision_method: null,
	archived_at: null,
	view_count: 0,
	changes_requested_at: null,
	job: null
};

describe('readQuoteListOverview', () => {
	it('fills every field and keeps withheld money as null', () => {
		const overview = readQuoteListOverview({ open_count: '6', sent_count: 2, follow_up_days: [3, 7] });
		expect(overview.open_count).toBe(6);
		expect(overview.open_minor).toBeNull();
		expect(overview.status_minor).toBeNull();
		expect(overview.rate_basis_points).toBeNull();
		expect(overview.follow_up_days).toEqual([3, 7]);
	});
	it('gives each open status a number when money is visible', () => {
		const overview = readQuoteListOverview({ status_minor: { draft: 2500 }, open_minor: 2500 });
		expect(overview.status_minor).toEqual({
			draft: 2500,
			awaiting_response: 0,
			changes_requested: 0,
			approved: 0
		});
	});
	it('reads no follow-up as off', () => {
		expect(readQuoteListOverview({ follow_up_days: null }).follow_up_days).toBeNull();
	});
});

describe('conversion wording', () => {
	it('writes whole percents', () => {
		expect(percentText(4166)).toBe('42%');
		expect(percentText(10000)).toBe('100%');
	});
	it('compares with the 30 days before', () => {
		expect(conversionChange(4200, 3600)).toEqual({ direction: 'up', text: 'Up from 36%' });
		expect(conversionChange(1428, 5000)).toEqual({ direction: 'down', text: 'Down from 50%' });
		expect(conversionChange(4210, 4190)).toEqual({ direction: 'same', text: 'Same as before' });
	});
	it('says nothing when either window had no quotes sent', () => {
		expect(conversionChange(null, 3600)).toBeNull();
		expect(conversionChange(4200, null)).toBeNull();
	});
});

describe('followUpText', () => {
	it('lists the send days', () => {
		expect(followUpText([3, 7])).toBe('Follow-up emails on, day 3 and day 7');
		expect(followUpText([2])).toBe('Follow-up emails on, day 2');
		expect(followUpText([1, 4, 9])).toBe('Follow-up emails on, day 1, day 4 and day 9');
	});
	it('says off when no follow-up is active', () => {
		expect(followUpText(null)).toBe('Follow-up emails off');
		expect(followUpText([])).toBe('Follow-up emails off');
	});
});

describe('quoteStatusDetail', () => {
	it('draft', () => {
		expect(quoteStatusDetail(base, day)?.text).toBe('Not sent yet');
		expect(quoteStatusDetail({ ...base, sent_at: '2026-10-01T10:00:00Z' }, day)?.text).toBe(
			'Revision not sent yet'
		);
	});
	it('awaiting response, opened and not', () => {
		const sent = { ...base, status: 'awaiting_response' as const, sent_at: '2026-10-13T10:00:00Z' };
		expect(quoteStatusDetail({ ...sent, view_count: 2 }, day)).toEqual({
			text: 'Sent 10-13 · opened 2×',
			unopened: false
		});
		expect(quoteStatusDetail(sent, day)).toEqual({ text: 'Sent 10-13 · not opened', unopened: true });
	});
	it('changes requested', () => {
		const asked = { ...base, status: 'changes_requested' as const };
		expect(quoteStatusDetail({ ...asked, changes_requested_at: '2026-10-13T09:00:00Z' }, day)?.text).toBe(
			'Client asked 10-13'
		);
		expect(quoteStatusDetail(asked, day)?.text).toBe('Client asked for edits');
	});
	it('approved names how, declined does not', () => {
		const decided = { ...base, decided_at: '2026-10-12T09:00:00Z' };
		expect(
			quoteStatusDetail({ ...decided, status: 'approved', decision_method: 'online' }, day)?.text
		).toBe('Approved online 10-12');
		expect(
			quoteStatusDetail({ ...decided, status: 'approved', decision_method: 'in_person' }, day)?.text
		).toBe('Approved in person 10-12');
		expect(
			quoteStatusDetail({ ...decided, status: 'declined', decision_method: 'online' }, day)?.text
		).toBe('Declined 10-12');
	});
	it('converted links the job only when it came back', () => {
		expect(
			quoteStatusDetail(
				{ ...base, status: 'converted', job: { id: 'j1', job_number: 1042 } },
				day
			)
		).toEqual({ text: 'Became', job: { id: 'j1', label: 'Job #1042' } });
		expect(quoteStatusDetail({ ...base, status: 'converted' }, day)?.text).toBe('Became a job');
	});
});
