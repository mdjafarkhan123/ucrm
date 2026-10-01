import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000062';
const stageId = '7b0c8f2e-0000-4000-8000-000000000002';

function event(body: unknown, rpc: ReturnType<typeof vi.fn> = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(
			`http://localhost/api/pipeline/opportunities/${opportunityId}/placement/undo`,
			{
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: typeof body === 'string' ? body : JSON.stringify(body)
			}
		),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('undo a placement', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({ auth: { user: { id: 'user-1' } }, access: {} } as never);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(event({ custom_stage_id: stageId }, rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON or names no placement', async () => {
		const rpc = vi.fn();

		expect((await POST(event('not json', rpc))).status).toBe(422);
		expect((await POST(event({}, rpc))).status).toBe(422);
		expect((await POST(event({ custom_stage_id: 'waiting' }, rpc))).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('asks the database to undo exactly the placement it was told about', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { stage: 'quote_draft', custom_stage_id: null },
			error: null
		});

		const response = await POST(event({ custom_stage_id: stageId }, rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('pipeline_undo_placement', {
			target_opportunity_id: opportunityId,
			undone_to_custom_stage_id: stageId
		});
		expect(await response.json()).toEqual({
			id: opportunityId,
			stage: 'quote_draft',
			custom_stage_id: null
		});
	});

	it('undoes taking a card out of a custom stage', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { stage: 'quote_draft', custom_stage_id: stageId },
			error: null
		});

		const response = await POST(event({ custom_stage_id: null }, rpc));

		expect(rpc.mock.calls[0][1].undone_to_custom_stage_id).toBeNull();
		expect((await response.json()).custom_stage_id).toBe(stageId);
	});

	it("passes on the database's own sentence when the card has changed since", async () => {
		const message = 'This move can no longer be undone because the card has changed since.';
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '23514', message } });

		const response = await POST(event({ custom_stage_id: stageId }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(message);
	});

	it('hides a card the caller has no access to', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501', message: 'no' } });

		expect((await POST(event({ custom_stage_id: stageId }, rpc))).status).toBe(404);
	});
});
