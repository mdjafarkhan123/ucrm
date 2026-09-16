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
		unit_kind: 'visit',
		unit_id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
		work_date: '2026-09-22',
		job_id: '00000000-0000-4000-8000-000000000010',
		job_number: 10,
		job_title: 'Weekly lawn care',
		price_basis: 'per_visit',
		client_id: '00000000-0000-4000-8000-000000000002',
		client_display_name: 'Ada Client',
		client_company_name: null,
		currency_code: 'USD',
		uninvoiced_minor: 5000,
		visit_id: `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
		reminder_id: null
	};
}

const summary = {
	uninvoiced_minor: 10000,
	unit_count: 2,
	visit_count: 2,
	period_count: 0,
	job_count: 0,
	distinct_job_count: 1
};

function event(url: string, rows: unknown[] = [], error: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_uninvoiced_work_summary' ? [summary] : rows,
			error
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial uninvoiced-work report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires Job and price visibility before querying uninvoiced work', async () => {
		mockedHasPermission.mockReturnValue(false);
		const request = event(
			'http://localhost/api/reports/financial/uninvoiced-work?from=2026-09-01&to=2026-10-01'
		);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(request, 'jobs.view');
		expect(mockedHasPermission).toHaveBeenCalledWith({}, 'jobs.view_price');
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		const response = await GET(event('http://localhost/api/reports/financial/uninvoiced-work'));
		expect(response.status).toBe(422);
	});

	it('passes the tenant, range and bounded page to both checked readers', async () => {
		const request = event(
			'http://localhost/api/reports/financial/uninvoiced-work?from=2026-09-01&to=2026-10-01&limit=25&direction=asc',
			[row()]
		);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_uninvoiced_work_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_work_date: undefined,
			cursor_unit_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_uninvoiced_work_summary', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01'
		});
	});

	it('returns traceable units, the whole-range summary and a direction-bound cursor', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/uninvoiced-work?from=2026-09-01&to=2026-10-01&limit=1',
				[row(1), row(2)]
			)
		);
		const body = await response.json();
		expect(body.units).toHaveLength(1);
		expect(body.units[0]).toMatchObject({
			unit_kind: 'visit',
			visit_id: '00000000-0000-4000-8000-000000000001',
			uninvoiced_minor: 5000
		});
		expect(body.summary).toEqual(summary);
		expect(body.next_cursor).toEqual(expect.any(String));
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('refuses a malformed cursor or one from the other direction', async () => {
		const malformed = await GET(
			event(
				'http://localhost/api/reports/financial/uninvoiced-work?from=2026-09-01&to=2026-10-01&cursor=nope'
			)
		);
		const wrongCursor = Buffer.from(
			JSON.stringify({
				direction: 'asc',
				workDate: '2026-09-01',
				unitId: '00000000-0000-4000-8000-000000000001'
			})
		).toString('base64url');
		const wrongDirection = await GET(
			event(
				`http://localhost/api/reports/financial/uninvoiced-work?from=2026-09-01&to=2026-10-01&cursor=${wrongCursor}`
			)
		);
		expect(malformed.status).toBe(422);
		expect(wrongDirection.status).toBe(422);
	});

	it('maps a database failure to a safe response', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/uninvoiced-work?from=2026-09-01&to=2026-10-01',
				[],
				{ code: '08000' }
			)
		);
		expect(response.status).toBe(500);
	});
});
