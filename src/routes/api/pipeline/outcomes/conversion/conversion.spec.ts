import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { organizationFormatting } from '$lib/server/requests/timezone';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));
vi.mock('$lib/server/requests/timezone', () => ({ organizationFormatting: vi.fn() }));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedFormatting = vi.mocked(organizationFormatting);

const organizationId = '00000000-0000-4000-8000-0000000000aa';

function event(rpc = vi.fn(), search = '') {
	return {
		url: new URL(`http://localhost/api/pipeline/outcomes/conversion${search}`),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}

const numbers = { cards: 2, still_there: 1, median_days: 3, average_days: 4.5 };
const answer = {
	requests: { total: 14, quoted: 5, won: 2, lost: 2, closed: 2, open: 8, open_unquoted: 6 },
	quotes: { total: 10, won: 4, lost: 3, open: 2, abandoned: 1 },
	sources: [
		{ lead_source: 'Referral', total: 6, won: 3, lost: 1, closed: 0, open: 2, won_value: 900 },
		{ lead_source: null, total: 1, won: 0, lost: 0, closed: 0, open: 1, won_value: null }
	],
	stages: [
		{
			stage: null,
			custom_stage_id: 'custom-1',
			name: 'Waiting on customer',
			section: 'quote',
			after_stage: 'quote_awaiting_response',
			position: 0,
			disabled: false,
			...numbers
		},
		{
			stage: 'quote_awaiting_response',
			custom_stage_id: null,
			name: null,
			section: null,
			after_stage: null,
			position: null,
			disabled: false,
			...numbers
		},
		{
			stage: 'new_request',
			custom_stage_id: null,
			name: null,
			section: null,
			after_stage: null,
			position: null,
			disabled: false,
			...numbers
		}
	],
	can_view_sources: true,
	can_view_value: true
};

describe('conversion report', () => {
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
	});

	it('needs pipeline.view', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await GET(event(rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.view');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes the counts through and names the stages in board order', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: answer, error: null });

		const body = await (await GET(event(rpc))).json();

		expect(body.requests).toEqual(answer.requests);
		expect(body.quotes).toEqual(answer.quotes);
		expect(body.sources).toEqual(answer.sources);
		expect(body.stages.map((stage: { label: string }) => stage.label)).toEqual([
			'New requests',
			'Awaiting response',
			'Waiting on customer'
		]);
		expect(body.currency_code).toBe('CAD');
	});

	it('says so when the database withheld lead sources and money', async () => {
		const withheld = { ...answer, sources: [], can_view_sources: false, can_view_value: false };
		const rpc = vi.fn().mockResolvedValue({ data: withheld, error: null });

		const body = await (await GET(event(rpc))).json();

		expect(body.can_view_sources).toBe(false);
		expect(body.can_view_value).toBe(false);
		expect(body.sources).toEqual([]);
	});

	it('asks for the whole history with no window when no date is chosen', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: answer, error: null });

		await GET(event(rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_conversion_report', {
			target_organization_id: organizationId,
			report_from: undefined,
			report_to: undefined
		});
	});

	it('resolves a preset window in the organization timezone', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: answer, error: null });

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
