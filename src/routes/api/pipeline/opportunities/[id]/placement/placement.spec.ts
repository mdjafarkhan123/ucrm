import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000031';
const stageId = '7b0c8f2e-0000-4000-8000-000000000001';

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/placement`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof PATCH>[0];
}

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;

describe('opportunity placement API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('asks for permission to edit the pipeline and stops there when refused', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await PATCH(event({ custom_stage_id: stageId }, rpc));

		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a stage that is not an id, and a body that is not JSON, before the database', async () => {
		const rpc = vi.fn();

		expect((await PATCH(event({ custom_stage_id: 'waiting' }, rpc))).status).toBe(422);
		expect((await PATCH(event({}, rpc))).status).toBe(422);
		expect((await PATCH(event('not json', rpc))).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('places the card in the stage', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { applied: true, stage: 'quote_draft', custom_stage_id: stageId },
			error: null
		});

		const response = await PATCH(event({ custom_stage_id: stageId }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_place_opportunity', {
			target_opportunity_id: opportunityId,
			target_custom_stage_id: stageId
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			id: opportunityId,
			stage: 'quote_draft',
			custom_stage_id: stageId,
			applied: true
		});
	});

	it('puts the card back in its real stage when the stage is null', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { applied: true, stage: 'quote_draft', custom_stage_id: null },
			error: null
		});

		const response = await PATCH(event({ custom_stage_id: null }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_place_opportunity', {
			target_opportunity_id: opportunityId,
			target_custom_stage_id: null
		});
		expect((await response.json()).custom_stage_id).toBeNull();
	});

	it("passes on the database's own reason for a refused move", async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: {
				code: '23514',
				message:
					'This is a request, so it can only go into a Requests stage. Convert it to a quote first.'
			}
		});

		const response = await PATCH(event({ custom_stage_id: stageId }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toMatch(/only go into a Requests stage/);
	});

	it('answers not found for a card this member may not move', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501' } });

		expect((await PATCH(event({ custom_stage_id: stageId }, rpc))).status).toBe(404);
	});
});
