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
		client_id: '00000000-0000-4000-8000-000000000002',
		client_display_name: 'Ada Client',
		client_company_name: null,
		subject: `Invoice ${index}`,
		tax_date: '2026-09-01',
		recognition_basis: 'issued',
		currency_code: 'USD',
		tax_source: 'saved_rate',
		tax_name: 'Sales tax',
		tax_rate_basis_points: 1000,
		net_sales_minor: 9000,
		tax_minor: 1000,
		total_minor: 10000,
		created_at: '2026-09-01T12:00:00.000Z'
	};
}

const summary = {
	net_sales_minor: 9000,
	tax_minor: 1000,
	billed_total_minor: 10000,
	invoice_count: 1,
	taxed_invoice_count: 1
};

function event(url: string, rows: unknown[] = [], error: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_invoice_tax_summary' ? [summary] : rows,
			error
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial Invoice tax report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires Invoice and price visibility before querying tax', async () => {
		mockedHasPermission.mockReturnValue(false);
		const request = event(
			'http://localhost/api/reports/financial/invoice-tax?from=2026-09-01&to=2026-10-01'
		);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		const response = await GET(event('http://localhost/api/reports/financial/invoice-tax'));
		expect(response.status).toBe(422);
	});

	it('passes the tenant, range and bounded page to both checked readers', async () => {
		const request = event(
			'http://localhost/api/reports/financial/invoice-tax?from=2026-09-01&to=2026-10-01&limit=25&direction=asc',
			[row()]
		);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_invoice_tax_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_tax_date: undefined,
			cursor_invoice_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_invoice_tax_summary', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01'
		});
	});

	it('returns frozen tax facts, the whole-range summary and a direction-bound cursor', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/invoice-tax?from=2026-09-01&to=2026-10-01&limit=1',
				[row(1), row(2)]
			)
		);
		const body = await response.json();
		expect(body.invoices).toHaveLength(1);
		expect(body.invoices[0]).toMatchObject({
			tax_source: 'saved_rate',
			tax_rate_basis_points: 1000,
			tax_minor: 1000
		});
		expect(body.summary).toEqual(summary);
		expect(body.next_cursor).toEqual(expect.any(String));
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('refuses a malformed cursor or one from the other direction', async () => {
		const malformed = await GET(
			event(
				'http://localhost/api/reports/financial/invoice-tax?from=2026-09-01&to=2026-10-01&cursor=nope'
			)
		);
		const wrongCursor = Buffer.from(
			JSON.stringify({
				direction: 'asc',
				taxDate: '2026-09-01',
				invoiceId: '00000000-0000-4000-8000-000000000001'
			})
		).toString('base64url');
		const wrongDirection = await GET(
			event(
				`http://localhost/api/reports/financial/invoice-tax?from=2026-09-01&to=2026-10-01&cursor=${wrongCursor}`
			)
		);
		expect(malformed.status).toBe(422);
		expect(wrongDirection.status).toBe(422);
	});

	it('maps a database failure to a safe response', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/invoice-tax?from=2026-09-01&to=2026-10-01',
				[],
				{ code: '08000' }
			)
		);
		expect(response.status).toBe(500);
	});
});
