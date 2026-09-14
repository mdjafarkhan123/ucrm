import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedHasPermission = vi.mocked(hasPermission);
const organizationId = '00000000-0000-4000-8000-0000000000aa';

function row(index = 1) {
	return {
		invoice_id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
		invoice_number: index,
		root_invoice_id: '00000000-0000-4000-8000-000000000001',
		predecessor_invoice_id: null,
		client_id: '00000000-0000-4000-8000-000000000002',
		client_display_name: 'Ada Client',
		client_company_name: null,
		subject: `Invoice ${index}`,
		sale_date: '2026-09-01',
		recognition_basis: 'issued',
		currency_code: 'USD',
		net_sales_minor: 9000,
		tax_minor: 1000,
		total_minor: 10000,
		written_off_at: null,
		has_unsettled_legacy_closure: false,
		created_at: '2026-09-01T12:00:00.000Z'
	};
}

const summary = {
	net_sales_minor: 9000,
	tax_minor: 1000,
	billed_total_minor: 10000,
	write_off_count: 0,
	historical_status_only_closure_count: 0
};

function event(url: string, rows: unknown[] = [], databaseError: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_invoice_sales_summary' ? [summary] : rows,
			error: databaseError
		})
	);
	return {
		url: new URL(url),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}

describe('financial Invoice sales report', () => {
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
			event('http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01')
		);
		expect(response.status).toBe(403);
	});

	it('requires financial visibility before making the database call', async () => {
		mockedHasPermission.mockReturnValue(false);
		const request = event(
			'http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01'
		);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		const missing = await GET(event('http://localhost/api/reports/financial/invoice-sales'));
		const backwards = await GET(
			event('http://localhost/api/reports/financial/invoice-sales?from=2026-10-01&to=2026-09-01')
		);
		expect(missing.status).toBe(422);
		expect(backwards.status).toBe(422);
	});

	it('passes the tenant, range and one-extra-row limit to the checked RPC', async () => {
		const request = event(
			'http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01&limit=25&direction=asc',
			[row(1)]
		);
		const response = await GET(request);
		expect(response.status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_invoice_sales_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_sale_date: undefined,
			cursor_invoice_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_invoice_sales_summary', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01'
		});
	});

	it('returns a direction-bound cursor from the last visible row', async () => {
		const rows = Array.from({ length: 3 }, (_, index) => row(index + 1));
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01&limit=2',
				rows
			)
		);
		const body = await response.json();
		expect(body.sales).toHaveLength(2);
		expect(body.next_cursor).toBe('desc:2026-09-01|00000000-0000-4000-8000-000000000002');
	});

	it('refuses a malformed cursor or one from the other direction', async () => {
		const malformed = await GET(
			event(
				'http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01&cursor=nope'
			)
		);
		const wrongDirection = await GET(
			event(
				'http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01&direction=asc&cursor=desc%3A2026-09-01%7C00000000-0000-4000-8000-000000000001'
			)
		);
		expect(malformed.status).toBe(422);
		expect(wrongDirection.status).toBe(422);
	});

	it('passes a valid cursor back as its two database values', async () => {
		const request = event(
			'http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01&cursor=desc%3A2026-09-01%7C00000000-0000-4000-8000-000000000001'
		);
		await GET(request);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith(
			'financial_invoice_sales_page',
			expect.objectContaining({
				cursor_sale_date: '2026-09-01',
				cursor_invoice_id: '00000000-0000-4000-8000-000000000001'
			})
		);
	});

	it('keeps the whole financial row and private cache header', async () => {
		const response = await GET(
			event('http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01', [
				row(1)
			])
		);
		const body = await response.json();
		expect(body.sales[0]).toMatchObject({
			net_sales_minor: 9000,
			tax_minor: 1000,
			total_minor: 10000
		});
		expect(body.summary).toEqual(summary);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('maps a database failure to the generic safe response', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/invoice-sales?from=2026-09-01&to=2026-10-01',
				[],
				{ code: '08000' }
			)
		);
		expect(response.status).toBe(500);
	});
});
