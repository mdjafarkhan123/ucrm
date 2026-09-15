import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { encodePaymentEventsCursor } from '$lib/server/reports/payment-events';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedHasPermission = vi.mocked(hasPermission);
const organizationId = '00000000-0000-4000-8000-0000000000aa';

function row(index = 1) {
	return {
		event_id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
		client_id: '00000000-0000-4000-8000-000000000001',
		client_display_name: 'Ada Client',
		client_company_name: null,
		event_type: 'received',
		original_event_type: null,
		event_date: '2026-09-14',
		amount_minor: 10000,
		cash_effect_minor: 10000,
		currency_code: 'USD',
		method: 'card',
		reference: 'receipt-1',
		note: null,
		original_event_id: null,
		original_deposit_event_id: null,
		actor_user_id: '00000000-0000-4000-8000-000000000002',
		created_at: '2026-09-14T12:00:00.000Z'
	};
}

const summary = {
	received_minor: 10000,
	refunded_minor: 0,
	reversed_receipt_minor: 0,
	reversed_refund_minor: 0,
	cash_effect_minor: 10000,
	event_count: 1
};

function event(url: string, rows: unknown[] = [], databaseError: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_payment_events_summary' ? [summary] : rows,
			error: databaseError
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial payment events report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires Invoice visibility', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await GET(
			event('http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01')
		);
		expect(response.status).toBe(403);
	});

	it('requires financial visibility before making the database call', async () => {
		mockedHasPermission.mockReturnValue(false);
		const request = event(
			'http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01'
		);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		const missing = await GET(event('http://localhost/api/reports/financial/payment-events'));
		const backwards = await GET(
			event('http://localhost/api/reports/financial/payment-events?from=2026-10-01&to=2026-09-01')
		);
		expect(missing.status).toBe(422);
		expect(backwards.status).toBe(422);
	});

	it('passes the tenant, range and one-extra-row limit to both RPCs', async () => {
		const request = event(
			'http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01&limit=25&direction=asc',
			[row()]
		);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_payment_events_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_event_date: undefined,
			cursor_event_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_payment_events_summary', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01'
		});
	});

	it('returns a direction-bound cursor from the last visible event', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01&limit=2',
				[row(1), row(2), row(3)]
			)
		);
		const body = await response.json();
		expect(body.payment_events).toHaveLength(2);
		expect(body.next_cursor).toBe(
			encodePaymentEventsCursor({
				direction: 'desc',
				eventDate: '2026-09-14',
				eventId: '00000000-0000-4000-8000-000000000002'
			})
		);
	});

	it('refuses malformed cursors and cursors from the other direction', async () => {
		const malformed = await GET(
			event(
				'http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01&cursor=nope'
			)
		);
		const cursor = encodePaymentEventsCursor({
			direction: 'desc',
			eventDate: '2026-09-14',
			eventId: '00000000-0000-4000-8000-000000000001'
		});
		const wrongDirection = await GET(
			event(
				`http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01&direction=asc&cursor=${cursor}`
			)
		);
		expect(malformed.status).toBe(422);
		expect(wrongDirection.status).toBe(422);
	});

	it('passes a valid cursor back as its two database values', async () => {
		const cursor = encodePaymentEventsCursor({
			direction: 'desc',
			eventDate: '2026-09-14',
			eventId: '00000000-0000-4000-8000-000000000001'
		});
		const request = event(
			`http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01&cursor=${cursor}`
		);
		await GET(request);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith(
			'financial_payment_events_page',
			expect.objectContaining({
				cursor_event_date: '2026-09-14',
				cursor_event_id: '00000000-0000-4000-8000-000000000001'
			})
		);
	});

	it('keeps the whole event, full totals and private cache header', async () => {
		const response = await GET(
			event('http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01', [
				row()
			])
		);
		const body = await response.json();
		expect(body.payment_events[0]).toMatchObject({
			event_type: 'received',
			amount_minor: 10000,
			cash_effect_minor: 10000
		});
		expect(body.summary).toEqual(summary);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('maps a database failure or missing summary to the generic safe response', async () => {
		const databaseFailure = await GET(
			event(
				'http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01',
				[],
				{ code: '08000' }
			)
		);
		expect(databaseFailure.status).toBe(500);

		const request = event(
			'http://localhost/api/reports/financial/payment-events?from=2026-09-01&to=2026-10-01'
		);
		vi.mocked(request.locals.supabase.rpc).mockResolvedValue({ data: [], error: null } as never);
		expect((await GET(request)).status).toBe(500);
	});
});
