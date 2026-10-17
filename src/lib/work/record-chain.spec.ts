import { describe, expect, it } from 'vitest';
import { buildRecordTrack, type RecordChain } from './record-chain';

const links = {
	request: (id: string) => `/requests/${id}`,
	quote: (id: string) => `/quotes/${id}`,
	job: (id: string) => `/jobs/${id}`,
	invoice: (id: string) => `/invoices/${id}`
};

const empty: RecordChain = { request: null, quote: null, job: null, invoices: null };

function build(chain: RecordChain, kind: 'request' | 'quote' | 'job' | 'invoice' = 'quote') {
	return buildRecordTrack(chain, { kind, links, clientName: 'David Lee' });
}

describe('buildRecordTrack', () => {
	it('always draws the five steps in order', () => {
		expect(build(empty).map((step) => step.label)).toEqual([
			'Request',
			'Quote',
			'Job',
			'Invoice',
			'Paid'
		]);
	});

	it('marks a sent quote as waiting on the client, and notes the quote began without a request', () => {
		const steps = build({
			...empty,
			quote: {
				id: 'q1',
				quote_number: 7,
				status: 'awaiting_response',
				sent_at: null,
				decided_at: null
			}
		});
		expect(steps[0]).toMatchObject({ state: 'todo', sub: 'Started as a quote' });
		expect(steps[1]).toMatchObject({ state: 'current', sub: 'Waiting on David', tone: 'critical' });
	});

	it('links the other steps but not the page its own record', () => {
		const steps = build({
			request: { id: 'r1', status: 'converted', created_at: '2026-08-17T06:00:00Z' },
			quote: {
				id: 'q1',
				quote_number: 1,
				status: 'approved',
				sent_at: null,
				decided_at: '2026-09-06T12:00:00Z'
			},
			job: null,
			invoices: null
		});
		expect(steps[0].href).toBe('/requests/r1');
		expect(steps[1].href).toBeUndefined();
		expect(steps[1]).toMatchObject({ state: 'done' });
	});

	it('says a request that has no quote yet is where the work currently stands', () => {
		const steps = build(
			{ ...empty, request: { id: 'r1', status: 'new', created_at: '2026-08-17T06:00:00Z' } },
			'request'
		);
		expect(steps[0]).toMatchObject({ state: 'current', sub: 'New' });
		expect(steps[1]).toMatchObject({ state: 'todo', sub: 'Not yet' });
	});

	it('counts paid invoices and adds how many more invoices there are', () => {
		const steps = build(
			{
				...empty,
				job: { id: 'j1', job_number: 14, status: 'closed', closed_at: '2026-09-26T04:00:00Z' },
				invoices: {
					count: 2,
					paid_count: 1,
					primary: {
						id: 'i1',
						invoice_number: 19,
						status: 'awaiting_payment',
						issued_at: null,
						due_date: null
					}
				}
			},
			'job'
		);
		expect(steps[2]).toMatchObject({ state: 'done' });
		expect(steps[2].href).toBeUndefined();
		expect(steps[3]).toMatchObject({ state: 'done', sub: '#19 +1 · sent', href: '/invoices/i1' });
		expect(steps[4]).toMatchObject({ state: 'current', sub: '1 of 2 paid' });
	});

	it('shows Paid in full only when every invoice is paid', () => {
		const steps = build(
			{
				...empty,
				invoices: {
					count: 1,
					paid_count: 1,
					primary: { id: 'i1', invoice_number: 27, status: 'paid', issued_at: null, due_date: null }
				}
			},
			'invoice'
		);
		expect(steps[4]).toMatchObject({ state: 'done', sub: 'Paid in full' });
	});

	it('gives a step the member cannot open without a link or detail', () => {
		const steps = build({ ...empty, quote: { restricted: true } }, 'job');
		expect(steps[1]).toMatchObject({ state: 'done', sub: 'Approved' });
		expect(steps[1].href).toBeUndefined();
	});
});
