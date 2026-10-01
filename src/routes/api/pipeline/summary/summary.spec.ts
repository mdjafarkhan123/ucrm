import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { requireOrganizationPermission, hasPermission } from '$lib/server/access/permission';
import { organizationFormatting } from '$lib/server/requests/timezone';
import { pipelinePresentation } from '$lib/server/pipeline/presentation';
import { enabledCustomStages } from '$lib/server/pipeline/stages';
import { DEFAULT_INACTIVITY_DAYS } from '$lib/pipeline/freshness';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));
vi.mock('$lib/server/requests/timezone', () => ({ organizationFormatting: vi.fn() }));
vi.mock('$lib/server/pipeline/presentation', () => ({ pipelinePresentation: vi.fn() }));
vi.mock('$lib/server/pipeline/stages', () => ({ enabledCustomStages: vi.fn() }));

const organizationId = '00000000-0000-4000-8000-0000000000aa';
const waiting = {
	id: '7b0c8f2e-0000-4000-8000-000000000001',
	section: 'quote',
	name: 'Waiting on customer',
	after_stage: 'quote_awaiting_response',
	requires_future_task: false,
	inactivity_days: 2
};
const empty = {
	id: '7b0c8f2e-0000-4000-8000-000000000002',
	section: 'request',
	name: 'Call back',
	after_stage: 'new_request',
	requires_future_task: false,
	inactivity_days: 2
};

function summaryEvent(rows: unknown[], query = '') {
	return {
		url: new URL(`http://localhost/api/pipeline/summary${query}`),
		locals: { supabase: { rpc: vi.fn().mockResolvedValue({ data: rows, error: null }) } }
	} as unknown as Parameters<typeof GET>[0];
}

// What `pipeline_stage_counts` answers: one row per column, a custom stage under its id. A card placed
// in a custom stage is in that row and not in its real stage's.
const rows = [
	{ stage_key: 'new_request', open_count: 3, value_total: null },
	{ stage_key: 'quote_draft', open_count: 2, value_total: 500 },
	{ stage_key: waiting.id, open_count: 4, value_total: 1250.5 },
	{ stage_key: empty.id, open_count: 0, value_total: null },
	// A stage this board was not told about is never given a number.
	{ stage_key: '7b0c8f2e-0000-4000-8000-000000000009', open_count: 9, value_total: 9 }
];

describe('board summary with custom follow-up columns', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(requireOrganizationPermission).mockResolvedValue({
			auth: { user: { id: 'user-1' }, organization: { id: organizationId } },
			access: {}
		} as never);
		vi.mocked(organizationFormatting).mockResolvedValue({
			ok: true,
			formatting: { currency_code: 'USD', locale: 'en-US', timezone: 'America/Chicago' }
		} as never);
		vi.mocked(pipelinePresentation).mockResolvedValue({
			ok: true,
			presentation: { detailed_assessment_stages: false, inactivity_days: DEFAULT_INACTIVITY_DAYS }
		} as never);
		vi.mocked(enabledCustomStages).mockResolvedValue({
			ok: true,
			stages: [waiting, empty]
		} as never);
	});

	it('gives each custom column its own count and money, and counts its cards on the board', async () => {
		vi.mocked(hasPermission).mockReturnValue(true);

		const body = await (await GET(summaryEvent(rows))).json();

		expect(body.custom_counts).toEqual({ [waiting.id]: 4, [empty.id]: 0 });
		expect(body.custom_value_totals).toEqual({ [waiting.id]: 1250.5, [empty.id]: null });
		expect(body.counts.quote_draft).toBe(2);
		expect(body.result_count).toBe(9);
	});

	it('leaves the money out entirely for a member who may not see it', async () => {
		vi.mocked(hasPermission).mockReturnValue(false);

		const body = await (await GET(summaryEvent(rows))).json();

		expect(body.custom_counts[waiting.id]).toBe(4);
		expect(body).not.toHaveProperty('custom_value_totals');
		expect(body).not.toHaveProperty('value_totals');
	});

	// The headings have to be counting the same cards the columns are showing.
	it('counts with the same search and lead source the columns page with', async () => {
		vi.mocked(hasPermission).mockReturnValue(true);
		const event = summaryEvent(rows, '?q=555-0102&source=Referral');

		expect((await GET(event)).status).toBe(200);

		const rpc = (event.locals as unknown as { supabase: { rpc: ReturnType<typeof vi.fn> } })
			.supabase.rpc;
		expect(rpc).toHaveBeenCalledWith(
			'pipeline_stage_counts',
			expect.objectContaining({
				search_like: '%555-0102%',
				search_digits: '5550102',
				lead_source_filter: 'Referral'
			})
		);
	});
});
