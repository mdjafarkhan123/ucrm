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
const base = 'http://localhost/api/reports/financial/sales-outcomes';

function row(sequence = 11, outcome: 'won' | 'lost' = 'won') {
	return {
		opportunity_id: `00000000-0000-4000-8000-${String(sequence).padStart(12, '0')}`,
		outcome,
		outcome_at: `2026-09-${String(sequence).padStart(2, '0')}T14:00:00+00:00`,
		outcome_on: `2026-09-${String(sequence).padStart(2, '0')}`,
		created_on: '2026-09-01',
		source_kind: 'quote',
		request_id: '00000000-0000-4000-8000-000000000003',
		quote_id: '00000000-0000-4000-8000-000000000004',
		quote_number: 7,
		title: 'Deck repair',
		client_id: '00000000-0000-4000-8000-000000000002',
		client_display_name: 'Ada Client',
		client_company_name: null,
		currency_code: 'USD',
		estimated_value_minor: 27500,
		lost_reason: outcome === 'lost' ? 'price_too_high' : null,
		outcome_event_id: '00000000-0000-4000-8000-000000000005'
	};
}

const summary = {
	won_count: 1,
	lost_count: 1,
	won_unvalued_count: 0,
	lost_unvalued_count: 1,
	won_value_minor: 27500,
	lost_value_minor: 0
};

function event(url: string, rows: unknown[] = [], error: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_sales_outcomes_summary' ? [summary] : rows,
			error
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial sales-outcomes report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires Pipeline access before querying outcomes', async () => {
		const denied = new Response(null, { status: 403 });
		mockedRequire.mockResolvedValue({ response: denied } as never);
		const request = event(`${base}?from=2026-09-01&to=2026-10-01`);
		const response = await GET(request);
		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(request, 'pipeline.view');
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		const response = await GET(event(base));
		expect(response.status).toBe(422);
	});

	it('passes the tenant, range and bounded page to both checked readers', async () => {
		const request = event(`${base}?from=2026-09-01&to=2026-10-01&limit=25&direction=asc`, [row()]);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_sales_outcomes_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_outcome_at: undefined,
			cursor_opportunity_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_sales_outcomes_summary', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01'
		});
	});

	it('returns traceable rows with values, the whole-range summary and a direction-bound cursor', async () => {
		const response = await GET(
			event(`${base}?from=2026-09-01&to=2026-10-01&limit=1&direction=desc`, [
				row(12, 'lost'),
				row(11)
			])
		);
		const body = await response.json();
		expect(body.values_visible).toBe(true);
		expect(body.outcomes).toHaveLength(1);
		expect(body.outcomes[0]).toMatchObject({
			outcome: 'lost',
			source_kind: 'quote',
			quote_number: 7,
			estimated_value_minor: 27500,
			lost_reason: 'price_too_high'
		});
		expect(body.summary).toEqual(summary);
		const cursor = JSON.parse(Buffer.from(body.next_cursor, 'base64url').toString('utf8'));
		expect(cursor).toEqual({
			direction: 'desc',
			outcomeAt: '2026-09-12T14:00:00+00:00',
			opportunityId: '00000000-0000-4000-8000-000000000012'
		});
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('omits every value column without pipeline.view_value, never substituting zero', async () => {
		mockedHasPermission.mockImplementation(
			(_access: unknown, key: string) => key !== 'pipeline.view_value'
		);
		const response = await GET(event(`${base}?from=2026-09-01&to=2026-10-01`, [row()]));
		const body = await response.json();
		expect(response.status).toBe(200);
		expect(body.values_visible).toBe(false);
		expect(body.outcomes[0]).toEqual({
			opportunity_id: '00000000-0000-4000-8000-000000000011',
			outcome: 'won',
			outcome_at: '2026-09-11T14:00:00+00:00',
			outcome_on: '2026-09-11',
			created_on: '2026-09-01',
			source_kind: 'quote',
			request_id: '00000000-0000-4000-8000-000000000003',
			quote_id: '00000000-0000-4000-8000-000000000004',
			quote_number: 7,
			title: 'Deck repair',
			client_id: '00000000-0000-4000-8000-000000000002',
			client_display_name: 'Ada Client',
			client_company_name: null,
			currency_code: 'USD',
			lost_reason: null,
			outcome_event_id: '00000000-0000-4000-8000-000000000005'
		});
		expect(body.summary).toEqual({
			won_count: 1,
			lost_count: 1,
			won_unvalued_count: 0,
			lost_unvalued_count: 1
		});
	});

	it('refuses a malformed cursor or one from the other direction', async () => {
		const malformed = await GET(event(`${base}?from=2026-09-01&to=2026-10-01&cursor=nope`));
		const wrongCursor = Buffer.from(
			JSON.stringify({
				direction: 'asc',
				outcomeAt: '2026-09-11T14:00:00+00:00',
				opportunityId: '00000000-0000-4000-8000-000000000011'
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
