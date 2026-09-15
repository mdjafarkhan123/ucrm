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

const summary = {
	outstanding_minor: 10000,
	not_due_minor: 0,
	overdue_1_30_minor: 10000,
	overdue_31_60_minor: 0,
	overdue_61_90_minor: 0,
	overdue_91_plus_minor: 0,
	available_credit_minor: 2000,
	client_balance_minor: 8000,
	client_count: 1,
	open_invoice_count: 1
};

function row(index = 1) {
	return {
		client_id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
		client_display_name: `Client ${index}`,
		client_company_name: null,
		sort_name: `client ${index}`,
		currency_code: 'USD',
		...summary
	};
}

function event(url: string, rows: unknown[] = [], databaseError: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_client_aging_summary' ? [summary] : rows,
			error: databaseError
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial Client aging report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires financial visibility before database access', async () => {
		mockedHasPermission.mockReturnValue(false);
		const request = event('http://localhost/api/reports/financial/client-aging?as_of=2026-09-14');
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid organization business date', async () => {
		expect((await GET(event('http://localhost/api/reports/financial/client-aging'))).status).toBe(
			422
		);
	});

	it('gets one extra row and whole-result totals in parallel', async () => {
		const request = event(
			'http://localhost/api/reports/financial/client-aging?as_of=2026-09-14&limit=25',
			[row()]
		);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_client_aging_page', {
			target_organization_id: organizationId,
			report_as_of: '2026-09-14',
			cursor_sort_name: undefined,
			cursor_client_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_client_aging_summary', {
			target_organization_id: organizationId,
			report_as_of: '2026-09-14'
		});
	});

	it('returns a cursor from the last visible Client and keeps full totals', async () => {
		const response = await GET(
			event('http://localhost/api/reports/financial/client-aging?as_of=2026-09-14&limit=2', [
				row(1),
				row(2),
				row(3)
			])
		);
		const body = await response.json();
		expect(body.clients).toHaveLength(2);
		expect(body.summary).toEqual(summary);
		expect(body.next_cursor).toEqual(expect.any(String));
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('refuses malformed cursors and hides database failures', async () => {
		expect(
			(
				await GET(
					event('http://localhost/api/reports/financial/client-aging?as_of=2026-09-14&cursor=nope')
				)
			).status
		).toBe(422);
		expect(
			(
				await GET(
					event('http://localhost/api/reports/financial/client-aging?as_of=2026-09-14', [], {
						code: '08000'
					})
				)
			).status
		).toBe(500);
	});
});
