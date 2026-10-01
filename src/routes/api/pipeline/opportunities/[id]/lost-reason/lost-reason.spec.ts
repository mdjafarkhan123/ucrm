import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000031';

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(
			`http://localhost/api/pipeline/opportunities/${opportunityId}/lost-reason`,
			{
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: typeof body === 'string' ? body : JSON.stringify(body)
			}
		),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof PATCH>[0];
}

describe('set lost reason', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await PATCH(event({ reason: 'price_too_high' }, rpc));

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a reason outside the list before querying the database', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event({ reason: 'too_far_away' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('requires a note for "Other"', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event({ reason: 'other', note: '  ' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.note).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('saves the reason and note on the lost record', async () => {
		const saved = { event_id: 'event-1', reason: 'price_too_high', note: 'Over their budget' };
		const rpc = vi.fn().mockResolvedValue({ data: saved, error: null });

		const response = await PATCH(
			event({ reason: 'price_too_high', note: ' Over their budget ' }, rpc)
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual(saved);
		expect(rpc).toHaveBeenCalledWith('pipeline_set_lost_reason', {
			target_opportunity_id: opportunityId,
			reason: 'price_too_high',
			note: 'Over their budget'
		});
	});

	it('clears the reason when none is chosen', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: {}, error: null });

		await PATCH(event({ reason: null, note: null }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_set_lost_reason', {
			target_opportunity_id: opportunityId,
			reason: undefined,
			note: undefined
		});
	});

	it('answers a record that is not lost with the database sentence', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'Only a lost opportunity has a lost reason.' }
		});

		const response = await PATCH(event({ reason: 'no_response' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(
			'Only a lost opportunity has a lost reason.'
		);
	});
});
