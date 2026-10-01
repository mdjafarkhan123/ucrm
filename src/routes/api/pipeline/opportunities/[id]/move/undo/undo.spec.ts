import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({ requireOrganizationPermission: vi.fn() }));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000061';

function event(body: unknown, rpc: ReturnType<typeof vi.fn> = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/move/undo`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

const move = { from_stage: 'new_request', to_stage: 'assessment_unscheduled' };

describe('undo a move', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue({ auth: { user: { id: 'user-1' } }, access: {} } as never);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(event(move, rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON or names an unknown stage', async () => {
		const rpc = vi.fn();

		expect((await POST(event('not json', rpc))).status).toBe(422);
		expect((await POST(event({ ...move, to_stage: 'made_up' }, rpc))).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('asks the database to undo exactly the move it was told about', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: { stage: 'new_request', custom_stage_id: null },
			error: null
		});

		const response = await POST(event({ ...move, restore_new_request: true }, rpc));

		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('pipeline_undo_move', {
			target_opportunity_id: opportunityId,
			undone_from_stage: 'new_request',
			undone_to_stage: 'assessment_unscheduled',
			restore_new_request: true
		});
		expect(await response.json()).toEqual({
			id: opportunityId,
			stage: 'new_request',
			custom_stage_id: null
		});
	});

	it('does not restore New unless the move said it changed it', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: { stage: 'new_request' }, error: null });

		await POST(event(move, rpc));

		expect(rpc.mock.calls[0][1].restore_new_request).toBe(false);
	});

	it("passes on the database's own sentence when the card has changed since", async () => {
		const message = 'This move can no longer be undone because the card has changed since.';
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '23514', message } });

		const response = await POST(event(move, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(message);
	});

	it('hides a card the caller has no access to', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '42501', message: 'no' } });

		expect((await POST(event(move, rpc))).status).toBe(404);
	});
});
