import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000031';

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/value`, {
			method: 'PATCH',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof PATCH>[0];
}

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;

describe('opportunity value API', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('returns the permission check response without touching the database', async () => {
		const denied = { response: new Response(null, { status: 403 }) } as never;
		mockedRequire.mockResolvedValue(denied);
		const rpc = vi.fn();

		const response = await PATCH(event({ estimated_value: 100 }, rpc));

		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a negative value before querying the database', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event({ estimated_value: -5 }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.estimated_value).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a value that is not a number', async () => {
		const rpc = vi.fn();
		const response = await PATCH(event({ estimated_value: 'a lot' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON', async () => {
		const rpc = vi.fn();
		const badEvent = {
			params: { id: opportunityId },
			request: new Request('http://localhost/api/pipeline/opportunities/x/value', {
				method: 'PATCH',
				headers: { 'content-type': 'application/json' },
				body: 'not json'
			}),
			locals: { supabase: { rpc } }
		} as unknown as Parameters<typeof PATCH>[0];

		const response = await PATCH(badEvent);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('clears the estimate when the value is null', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [{ id: opportunityId, estimated_value: null }],
			error: null
		});

		const response = await PATCH(event({ estimated_value: null }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_update_opportunity_details', {
			target_opportunity_id: opportunityId,
			set_value: true,
			new_estimated_value: null
		});
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ id: opportunityId, estimated_value: null });
	});

	it('saves a real value and returns it', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: [{ id: opportunityId, estimated_value: 4200.5 }],
			error: null
		});

		const response = await PATCH(event({ estimated_value: 4200.5 }, rpc));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ id: opportunityId, estimated_value: 4200.5 });
	});

	it('turns the database check-violation into a field error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'estimated_value must be >= 0' }
		});

		const response = await PATCH(event({ estimated_value: 0 }, rpc));

		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.field_errors.estimated_value).toBe('estimated_value must be >= 0');
	});

	it('turns a refusal from the write function into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await PATCH(event({ estimated_value: 100 }, rpc));

		expect(response.status).toBe(404);
	});

	it('turns any other database error into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '08000', message: 'connection failure' }
		});

		const response = await PATCH(event({ estimated_value: 100 }, rpc));

		expect(response.status).toBe(500);
	});

	it('returns not-found when the function answers with no row', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: [], error: null });

		const response = await PATCH(event({ estimated_value: 100 }, rpc));

		expect(response.status).toBe(404);
	});
});
