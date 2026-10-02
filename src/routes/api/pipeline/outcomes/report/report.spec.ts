import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { loadLostReasons } from '$lib/server/pipeline/lost-reasons';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));
vi.mock('$lib/server/requests/timezone', () => ({ organizationFormatting: vi.fn() }));
vi.mock('$lib/server/pipeline/lost-reasons', async (importOriginal) => ({
	...(await importOriginal<typeof import('$lib/server/pipeline/lost-reasons')>()),
	loadLostReasons: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedFormatting = vi.mocked(organizationFormatting);
const mockedReasons = vi.mocked(loadLostReasons);

const organizationId = '00000000-0000-4000-8000-0000000000aa';

function event(rpc = vi.fn(), search = '') {
	return {
		url: new URL(`http://localhost/api/pipeline/outcomes/report${search}`),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}

const report = {
	won: { count: 3, unvalued_count: 1, value_total: 900 },
	lost: { count: 4, unvalued_count: 0, value_total: 400 },
	direct_job: { count: 2, unvalued_count: 2, value_total: null },
	days_to_win: { count: 3, median: 5, average: 6.5 },
	lost_reasons: [
		{ reason: 'price_too_high', count: 2 },
		{ reason: 'customer_declined', count: 1 },
		{ reason: null, count: 1 }
	]
};

describe('outcomes report', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		mockedFormatting.mockResolvedValue({
			ok: true,
			formatting: { timezone: 'America/Toronto', currency_code: 'CAD', locale: 'en-CA' }
		});
		mockedReasons.mockResolvedValue({
			ok: true,
			reasons: [
				{ key: 'price_too_high', label: 'Price too high', is_built_in: true, retired_at: null }
			]
		});
	});

	it('needs pipeline.view', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await GET(event(rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.view');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('names each reason, and keeps customer declines and no-reason as their own lines', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: report, error: null });

		const body = await (await GET(event(rpc))).json();

		expect(body.lost_reasons).toEqual([
			{ reason: 'price_too_high', label: 'Price too high', count: 2 },
			{ reason: 'customer_declined', label: 'Customer declined', count: 1 },
			{ reason: null, label: 'No reason given', count: 1 }
		]);
		expect(body.direct_job).toEqual({ count: 2, unvalued_count: 2, value_total: null });
		expect(body.days_to_win).toEqual({ count: 3, median: 5, average: 6.5 });
		expect(body.can_view_value).toBe(true);
	});

	it('reports that money is hidden when the database withheld it', async () => {
		const hidden = {
			...report,
			won: { count: 3, unvalued_count: 1 },
			lost: { count: 4, unvalued_count: 0 },
			direct_job: { count: 2, unvalued_count: 2 }
		};
		const rpc = vi.fn().mockResolvedValue({ data: hidden, error: null });

		const body = await (await GET(event(rpc))).json();

		expect(body.can_view_value).toBe(false);
		expect(body.won.value_total).toBeUndefined();
	});

	it('asks for the whole history with no window when no date is chosen', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: report, error: null });

		await GET(event(rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_outcomes_report', {
			target_organization_id: organizationId,
			report_from: undefined,
			report_to: undefined
		});
	});

	it('resolves a preset window in the organization timezone', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: report, error: null });

		await GET(event(rpc, '?date=last_30_days'));

		const call = rpc.mock.calls[0][1] as { report_from: string; report_to: string };
		expect(new Date(call.report_from).getTime()).toBeLessThan(new Date(call.report_to).getTime());
	});

	it('refuses a custom range with neither end', async () => {
		const rpc = vi.fn();

		const response = await GET(event(rpc, '?date=custom'));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('turns a database error into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '08000' } });

		expect((await GET(event(rpc))).status).toBe(500);
	});
});
