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
const base = 'http://localhost/api/reports/financial/job-profitability';

function row(jobNumber = 11) {
	return {
		job_id: `00000000-0000-4000-8000-${String(jobNumber).padStart(12, '0')}`,
		job_number: jobNumber,
		job_title: 'Deck repair',
		job_type: 'one_off',
		price_basis: 'job_total',
		job_status: 'closed',
		closed_on: '2026-09-06',
		client_id: '00000000-0000-4000-8000-000000000002',
		client_display_name: 'Ada Client',
		client_company_name: null,
		currency_code: 'USD',
		unit_count: null,
		revenue_minor: 27500,
		item_cost_minor: 0,
		labor_cost_minor: 3000,
		expense_cost_minor: 1250,
		total_cost_minor: 4250,
		profit_minor: 23250,
		margin_basis_points: 8455,
		labor_minutes: 150,
		unrated_labor_count: 1,
		unrated_labor_minutes: 60
	};
}

const summary = {
	job_count: 1,
	one_off_count: 1,
	per_visit_count: 0,
	fixed_per_period_count: 0,
	unpriced_job_count: 0,
	revenue_minor: 27500,
	item_cost_minor: 0,
	labor_cost_minor: 3000,
	expense_cost_minor: 1250,
	total_cost_minor: 4250,
	profit_minor: 23250,
	unpriced_cost_minor: 0,
	labor_minutes: 150,
	unrated_labor_count: 1,
	unrated_labor_minutes: 60
};

function event(url: string, rows: unknown[] = [], error: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_job_profitability_summary' ? [summary] : rows,
			error
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial job-profitability report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires Job and price visibility before querying profitability', async () => {
		mockedHasPermission.mockReturnValue(false);
		const request = event(`${base}?from=2026-09-01&to=2026-10-01`);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(request, 'jobs.view');
		expect(mockedHasPermission).toHaveBeenCalledWith({}, 'jobs.view_price');
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		const response = await GET(event(base));
		expect(response.status).toBe(422);
	});

	it('passes the tenant, range and bounded page to both checked readers', async () => {
		const request = event(`${base}?from=2026-09-01&to=2026-10-01&limit=25&direction=asc`, [row()]);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_job_profitability_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_job_number: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith(
			'financial_job_profitability_summary',
			{
				target_organization_id: organizationId,
				report_from: '2026-09-01',
				report_to: '2026-10-01'
			}
		);
	});

	it('returns traceable rows with costs, the whole-range summary and a direction-bound cursor', async () => {
		const response = await GET(
			event(`${base}?from=2026-09-01&to=2026-10-01&limit=1`, [row(11), row(12)])
		);
		const body = await response.json();
		expect(body.costs_visible).toBe(true);
		expect(body.jobs).toHaveLength(1);
		expect(body.jobs[0]).toMatchObject({
			job_number: 11,
			revenue_minor: 27500,
			profit_minor: 23250,
			unrated_labor_count: 1
		});
		expect(body.summary).toEqual(summary);
		expect(body.next_cursor).toEqual(expect.any(String));
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('omits every cost, profit and labor column without jobs.view_cost, never substituting zero', async () => {
		mockedHasPermission.mockImplementation(
			(_access: unknown, key: string) => key !== 'jobs.view_cost'
		);
		const response = await GET(event(`${base}?from=2026-09-01&to=2026-10-01`, [row()]));
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.costs_visible).toBe(false);
		expect(body.jobs[0]).toEqual({
			job_id: '00000000-0000-4000-8000-000000000011',
			job_number: 11,
			job_title: 'Deck repair',
			job_type: 'one_off',
			price_basis: 'job_total',
			job_status: 'closed',
			closed_on: '2026-09-06',
			client_id: '00000000-0000-4000-8000-000000000002',
			client_display_name: 'Ada Client',
			client_company_name: null,
			currency_code: 'USD',
			unit_count: null,
			revenue_minor: 27500
		});
		expect(body.summary).toEqual({
			job_count: 1,
			one_off_count: 1,
			per_visit_count: 0,
			fixed_per_period_count: 0,
			unpriced_job_count: 0,
			revenue_minor: 27500
		});
	});

	it('refuses a malformed cursor or one from the other direction', async () => {
		const malformed = await GET(event(`${base}?from=2026-09-01&to=2026-10-01&cursor=nope`));
		const wrongCursor = Buffer.from(JSON.stringify({ direction: 'asc', jobNumber: 11 })).toString(
			'base64url'
		);
		const wrongDirection = await GET(
			event(`${base}?from=2026-09-01&to=2026-10-01&cursor=${wrongCursor}`)
		);
		expect(malformed.status).toBe(422);
		expect(wrongDirection.status).toBe(422);
	});

	it('maps a database failure to a safe response', async () => {
		const response = await GET(
			event(`${base}?from=2026-09-01&to=2026-10-01`, [], { code: '08000' })
		);
		expect(response.status).toBe(500);
	});
});
