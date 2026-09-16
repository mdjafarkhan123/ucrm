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
const base = 'http://localhost/api/reports/financial/time-entries';

function row(sequence = 11, unrated = false) {
	return {
		entry_id: `00000000-0000-4000-8000-${String(sequence).padStart(12, '0')}`,
		started_at: `2026-09-${String(sequence).padStart(2, '0')}T09:00:00+00:00`,
		started_on: `2026-09-${String(sequence).padStart(2, '0')}`,
		minutes: 90,
		user_id: '00000000-0000-4000-8000-000000000001',
		user_name: 'Crew Member',
		job_id: '00000000-0000-4000-8000-000000000002',
		job_number: 42,
		job_title: 'Deck repair',
		client_id: '00000000-0000-4000-8000-000000000003',
		client_display_name: 'Ada Client',
		client_company_name: null,
		visit_id: '00000000-0000-4000-8000-000000000004',
		visit_date: `2026-09-${String(sequence).padStart(2, '0')}`,
		currency_code: 'USD',
		is_unrated: unrated,
		cost_per_hour_minor: unrated ? null : 4000,
		cost_total_minor: unrated ? null : 6000
	};
}

const summary = {
	entry_count: 2,
	member_count: 1,
	job_count: 1,
	minutes: 180,
	rated_minutes: 90,
	unrated_count: 1,
	unrated_minutes: 90,
	cost_total_minor: 6000
};

function event(url: string, rows: unknown[] = [], error: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_time_entries_summary' ? [summary] : rows,
			error
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial time-entries report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires Job access before querying entries', async () => {
		const denied = new Response(null, { status: 403 });
		mockedRequire.mockResolvedValue({ response: denied } as never);
		const request = event(`${base}?from=2026-09-01&to=2026-10-01`);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(request, 'jobs.view');
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('refuses a member who may track neither their own nor the team hours', async () => {
		mockedHasPermission.mockImplementation((_access: unknown, key: string) =>
			key.startsWith('time.') ? false : true
		);
		const request = event(`${base}?from=2026-09-01&to=2026-10-01`);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		const response = await GET(event(base));
		expect(response.status).toBe(422);
	});

	it('passes the tenant, range and bounded page to both checked readers', async () => {
		const request = event(`${base}?from=2026-09-01&to=2026-10-01&limit=25&direction=asc`, [row()]);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_time_entries_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_started_at: undefined,
			cursor_entry_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_time_entries_summary', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01'
		});
	});

	it('returns traceable rows with cost, the whole-range summary and a direction-bound cursor', async () => {
		const response = await GET(
			event(`${base}?from=2026-09-01&to=2026-10-01&limit=1&direction=desc`, [
				row(12, true),
				row(11)
			])
		);
		const body = await response.json();
		expect(body.team_visible).toBe(true);
		expect(body.cost_visible).toBe(true);
		expect(body.entries).toHaveLength(1);
		expect(body.entries[0]).toMatchObject({
			job_number: 42,
			minutes: 90,
			is_unrated: true,
			cost_per_hour_minor: null,
			cost_total_minor: null
		});
		expect(body.summary).toEqual(summary);
		const cursor = JSON.parse(Buffer.from(body.next_cursor, 'base64url').toString('utf8'));
		expect(cursor).toEqual({
			direction: 'desc',
			startedAt: '2026-09-12T09:00:00+00:00',
			entryId: '00000000-0000-4000-8000-000000000012'
		});
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('omits every cost column without jobs.view_cost, never substituting zero', async () => {
		mockedHasPermission.mockImplementation(
			(_access: unknown, key: string) => key !== 'jobs.view_cost' && key !== 'time.track_team'
		);
		const response = await GET(event(`${base}?from=2026-09-01&to=2026-10-01`, [row()]));
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.team_visible).toBe(false);
		expect(body.cost_visible).toBe(false);
		expect(body.entries[0]).toEqual({
			entry_id: '00000000-0000-4000-8000-000000000011',
			started_at: '2026-09-11T09:00:00+00:00',
			started_on: '2026-09-11',
			minutes: 90,
			user_id: '00000000-0000-4000-8000-000000000001',
			user_name: 'Crew Member',
			job_id: '00000000-0000-4000-8000-000000000002',
			job_number: 42,
			job_title: 'Deck repair',
			client_id: '00000000-0000-4000-8000-000000000003',
			client_display_name: 'Ada Client',
			client_company_name: null,
			visit_id: '00000000-0000-4000-8000-000000000004',
			visit_date: '2026-09-11',
			currency_code: 'USD',
			is_unrated: false
		});
		expect(body.summary).toEqual({
			entry_count: 2,
			member_count: 1,
			job_count: 1,
			minutes: 180,
			rated_minutes: 90,
			unrated_count: 1,
			unrated_minutes: 90
		});
	});

	it('refuses a malformed cursor or one from the other direction', async () => {
		const malformed = await GET(event(`${base}?from=2026-09-01&to=2026-10-01&cursor=nope`));
		const wrongCursor = Buffer.from(
			JSON.stringify({
				direction: 'asc',
				startedAt: '2026-09-11T09:00:00+00:00',
				entryId: '00000000-0000-4000-8000-000000000011'
			})
		).toString('base64url');
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
