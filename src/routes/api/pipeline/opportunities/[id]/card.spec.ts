import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { hasPermission, requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn(),
	hasPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedHas = vi.mocked(hasPermission);
const opportunityId = '00000000-0000-4000-8000-000000000041';

function event(id: string, rpc = vi.fn()) {
	return {
		params: { id },
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof GET>[0];
}

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;

const row = {
	id: opportunityId,
	title: 'Roof repair',
	stage: 'quote_draft',
	stage_entered_at: '2026-10-01T09:00:00Z',
	outcome: 'open',
	created_at: '2026-09-30T09:00:00Z',
	request_id: 'request-1',
	request_status: 'converted',
	client_id: 'client-1',
	client_display_name: 'Ada Lane',
	client_company_name: null,
	property_id: null,
	property_label: null,
	property_address_line1: null,
	property_city: null,
	property_state_region: null,
	property_postal_code: null,
	owner_user_id: null,
	owner_full_name: null,
	owner_avatar_url: null,
	estimated_value: 1200,
	expected_close_on: null,
	next_task_due_on: '2026-10-09',
	task_id: 'task-1',
	task_title: 'Call back',
	task_due_on: '2026-10-09',
	quote_id: null,
	quote_status: null,
	assessment_starts_at: null,
	assessment_ends_at: null,
	custom_stage_id: null,
	quote_delivery_failed_at: null,
	quote_delivery_failed_email: null,
	quote_delivery_failure: null,
	progress_at: '2026-10-01T09:00:00Z',
	client_lead_source: null
};

describe('single opportunity card API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
		mockedHas.mockReturnValue(false);
	});

	it('returns the permission check response without touching the database', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await GET(event(opportunityId, rpc));

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('answers not found for an id that is not a uuid, without asking the database', async () => {
		const rpc = vi.fn();
		const response = await GET(event('not-a-card', rpc));

		expect(response.status).toBe(404);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('answers not found when the card is no longer on the board', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });
		const response = await GET(event(opportunityId, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_opportunity_card', {
			target_opportunity_id: opportunityId
		});
		expect(response.status).toBe(404);
	});

	it('returns the card shaped like a board card, without money for a member who may not see it', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [row], error: null });
		const response = await GET(event(opportunityId, rpc));
		const card = await response.json();

		expect(response.status).toBe(200);
		expect(card.id).toBe(opportunityId);
		expect(card.client).toEqual({
			id: 'client-1',
			display_name: 'Ada Lane',
			company_name: null,
			lead_source: null
		});
		expect(card.task).toEqual({ id: 'task-1', title: 'Call back', due_on: '2026-10-09' });
		expect(card).not.toHaveProperty('estimated_value');
	});

	it('includes money for a member who may see it', async () => {
		mockedHas.mockReturnValue(true);
		const rpc = vi.fn().mockResolvedValue({ data: [row], error: null });
		const card = await (await GET(event(opportunityId, rpc))).json();

		expect(card.estimated_value).toBe(1200);
	});
});
