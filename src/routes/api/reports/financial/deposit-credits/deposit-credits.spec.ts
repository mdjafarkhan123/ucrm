import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';
import { encodeDepositCreditsCursor } from '$lib/server/reports/deposit-credits';

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
		quote_id: '00000000-0000-4000-8000-000000000010',
		quote_number: 41,
		quote_version_id: '00000000-0000-4000-8000-000000000011',
		client_id: '00000000-0000-4000-8000-000000000012',
		client_display_name: 'Ada Client',
		client_company_name: null,
		event_type: 'received',
		amount_minor: 10000,
		cash_effect_minor: 10000,
		currency_code: 'USD',
		method: 'cash',
		reference: null,
		note: null,
		reversed_event_id: null,
		refunded_minor: 2000,
		allocated_minor: 3000,
		available_credit_minor: 5000,
		actor_user_id: '00000000-0000-4000-8000-000000000013',
		activity_date: '2026-09-14',
		created_at: '2026-09-14T12:00:00.000Z'
	};
}

const summary = {
	received_minor: 10000,
	reversed_minor: 0,
	cash_effect_minor: 10000,
	refunded_minor: 2000,
	allocated_minor: 3000,
	available_credit_minor: 5000,
	event_count: 1
};

function event(url: string, rows: unknown[] = [], databaseError: unknown = null) {
	const rpc = vi.fn().mockImplementation((functionName: string) =>
		Promise.resolve({
			data: functionName === 'financial_deposit_credits_summary' ? [summary] : rows,
			error: databaseError
		})
	);
	return { url: new URL(url), locals: { supabase: { rpc } } } as unknown as Parameters<
		typeof GET
	>[0];
}

describe('financial deposit credits report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedHasPermission.mockReturnValue(true);
	});

	it('requires Invoice amount visibility before querying the database', async () => {
		mockedHasPermission.mockReturnValue(false);
		const request = event(
			'http://localhost/api/reports/financial/deposit-credits?from=2026-09-01&to=2026-10-01'
		);
		expect((await GET(request)).status).toBe(403);
		expect(request.locals.supabase.rpc).not.toHaveBeenCalled();
	});

	it('requires a valid inclusive-start, exclusive-end range', async () => {
		expect(
			(await GET(event('http://localhost/api/reports/financial/deposit-credits'))).status
		).toBe(422);
		expect(
			(
				await GET(
					event(
						'http://localhost/api/reports/financial/deposit-credits?from=2026-10-01&to=2026-09-01'
					)
				)
			).status
		).toBe(422);
	});

	it('passes the tenant, range and bounded page to both readers', async () => {
		const request = event(
			'http://localhost/api/reports/financial/deposit-credits?from=2026-09-01&to=2026-10-01&limit=25&direction=asc',
			[row()]
		);
		expect((await GET(request)).status).toBe(200);
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith('financial_deposit_credits_page', {
			target_organization_id: organizationId,
			report_from: '2026-09-01',
			report_to: '2026-10-01',
			cursor_created_at: undefined,
			cursor_event_id: undefined,
			page_limit: 26,
			sort_direction: 'asc'
		});
		expect(request.locals.supabase.rpc).toHaveBeenCalledWith(
			'financial_deposit_credits_summary',
			expect.objectContaining({ target_organization_id: organizationId })
		);
	});

	it('returns a direction-bound cursor from the last visible event', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/deposit-credits?from=2026-09-01&to=2026-10-01&limit=2',
				[row(1), row(2), row(3)]
			)
		);
		const body = await response.json();
		expect(body.deposits).toHaveLength(2);
		expect(body.next_cursor).toBe(
			encodeDepositCreditsCursor({
				direction: 'desc',
				createdAt: '2026-09-14T12:00:00.000Z',
				eventId: '00000000-0000-4000-8000-000000000002'
			})
		);
	});

	it('refuses malformed and wrong-direction cursors', async () => {
		const malformed = await GET(
			event(
				'http://localhost/api/reports/financial/deposit-credits?from=2026-09-01&to=2026-10-01&cursor=nope'
			)
		);
		const cursor = encodeDepositCreditsCursor({
			direction: 'desc',
			createdAt: '2026-09-14T12:00:00.000Z',
			eventId: '00000000-0000-4000-8000-000000000001'
		});
		const wrongDirection = await GET(
			event(
				`http://localhost/api/reports/financial/deposit-credits?from=2026-09-01&to=2026-10-01&direction=asc&cursor=${cursor}`
			)
		);
		expect(malformed.status).toBe(422);
		expect(wrongDirection.status).toBe(422);
	});

	it('keeps source relationships, current credit totals and private caching', async () => {
		const response = await GET(
			event(
				'http://localhost/api/reports/financial/deposit-credits?from=2026-09-01&to=2026-10-01',
				[row()]
			)
		);
		const body = await response.json();
		expect(body.deposits[0]).toMatchObject({
			quote_number: 41,
			refunded_minor: 2000,
			allocated_minor: 3000,
			available_credit_minor: 5000
		});
		expect(body.summary).toEqual(summary);
		expect(response.headers.get('cache-control')).toBe('private, no-cache');
	});

	it('maps database failures to the generic safe response', async () => {
		expect(
			(
				await GET(
					event(
						'http://localhost/api/reports/financial/deposit-credits?from=2026-09-01&to=2026-10-01',
						[],
						{ code: '08000' }
					)
				)
			).status
		).toBe(500);
	});
});
