import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000032';

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(
			`http://localhost/api/pipeline/opportunities/${opportunityId}/expected-close`,
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

describe('opportunity expected-close API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('returns the permission check response without touching the database', async () => {
		const denied = { response: new Response(null, { status: 401 }) } as never;
		mockedRequire.mockResolvedValue(denied);
		const rpc = vi.fn();

		const response = await PATCH(event({ expected_close_on: '2026-09-01' }, rpc));

		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a date that is not ISO-shaped', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event({ expected_close_on: '09/01/2026' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('clears the date when it is null', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [{ id: opportunityId, expected_close_on: null }],
			error: null
		});

		const response = await PATCH(event({ expected_close_on: null }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_update_opportunity_details', {
			target_opportunity_id: opportunityId,
			set_expected_close: true,
			new_expected_close_on: null
		});
		expect(response.status).toBe(200);
	});

	it('saves a real date and returns it', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [{ id: opportunityId, expected_close_on: '2026-09-01' }],
			error: null
		});

		const response = await PATCH(event({ expected_close_on: '2026-09-01' }, rpc));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({
			id: opportunityId,
			expected_close_on: '2026-09-01'
		});
	});

	it('turns the database check-violation into a field error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'invalid date' }
		});

		const response = await PATCH(event({ expected_close_on: '2026-09-01' }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.expected_close_on).toBe('invalid date');
	});

	it('turns a refusal from the write function into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await PATCH(event({ expected_close_on: '2026-09-01' }, rpc));

		expect(response.status).toBe(404);
	});
});
