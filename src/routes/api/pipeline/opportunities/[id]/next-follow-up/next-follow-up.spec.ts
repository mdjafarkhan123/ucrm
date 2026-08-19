import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000033';

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(
			`http://localhost/api/pipeline/opportunities/${opportunityId}/next-follow-up`,
			{
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			}
		),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof PATCH>[0];
}

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;

describe('opportunity next-follow-up API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('returns the permission check response without touching the database', async () => {
		const denied = { response: new Response(null, { status: 403 }) } as never;
		mockedRequire.mockResolvedValue(denied);
		const rpc = vi.fn();

		const response = await PATCH(event({ next_follow_up_on: '2026-09-01' }, rpc));

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a date that is not ISO-shaped', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event({ next_follow_up_on: 'next tuesday' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('clears the date when it is null', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [{ id: opportunityId, next_follow_up_on: null }],
			error: null
		});

		const response = await PATCH(event({ next_follow_up_on: null }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_update_opportunity_details', {
			target_opportunity_id: opportunityId,
			set_next_follow_up: true,
			new_next_follow_up_on: null
		});
		expect(response.status).toBe(200);
	});

	it('saves a real date and returns it', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [{ id: opportunityId, next_follow_up_on: '2026-09-05' }],
			error: null
		});

		const response = await PATCH(event({ next_follow_up_on: '2026-09-05' }, rpc));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			id: opportunityId,
			next_follow_up_on: '2026-09-05'
		});
	});

	it('turns the database check-violation into a field error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'invalid date' }
		});

		const response = await PATCH(event({ next_follow_up_on: '2026-09-05' }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.next_follow_up_on).toBe('invalid date');
	});

	it('turns a refusal from the write function into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await PATCH(event({ next_follow_up_on: '2026-09-05' }, rpc));

		expect(response.status).toBe(404);
	});
});
