import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', () => ({
	requireOrganizationPermission: vi.fn()
}));

const mockedRequire = vi.mocked(requireOrganizationPermission);
const opportunityId = '00000000-0000-4000-8000-000000000031';
const idempotencyKey = '00000000-0000-4000-8000-0000000000ee';

const context = { auth: { user: { id: 'user-1' } }, access: {} } as never;

function commandResult(overrides: Record<string, unknown> = {}) {
	return {
		applied: true,
		event_id: '00000000-0000-4000-8000-000000000099',
		outcome: 'open',
		outcome_at: null,
		...overrides
	};
}

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/reopen`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('reopen opportunity', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: 'Client came back' }, rpc)
		);

		expect(response.status).toBe(403);
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'pipeline.edit');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a body that is not valid JSON', async () => {
		const rpc = vi.fn();
		const response = await POST(event('not json', rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a missing or malformed idempotency key before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(
			event({ idempotency_key: 'not-a-uuid', reopen_explanation: 'Client came back' }, rpc)
		);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.idempotency_key).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('requires an explanation before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(event({ idempotency_key: idempotencyKey }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.reopen_explanation).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a blank explanation before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: '   ' }, rpc)
		);

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends the explanation through to the write function', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: commandResult(), error: null });

		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: 'Client came back' }, rpc)
		);

		expect(rpc).toHaveBeenCalledWith('pipeline_reopen_opportunity', {
			target_opportunity_id: opportunityId,
			idempotency_key: idempotencyKey,
			reopen_explanation: 'Client came back'
		});
		expect(response.status).toBe(200);
	});

	it('returns the command result the RPC answers, including a retried command', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: commandResult({ applied: false }), error: null });

		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: 'Client came back' }, rpc)
		);

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual(commandResult({ applied: false }));
	});

	it('turns a refusal from the function into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: 'Client came back' }, rpc)
		);

		expect(response.status).toBe(404);
	});

	it('turns a database check-violation (not a lost opportunity, task ceiling) into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'Only a lost opportunity can be reopened.' }
		});

		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: 'Client came back' }, rpc)
		);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('lost opportunity');
	});

	it('turns any other database error into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '08000' } });
		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: 'Client came back' }, rpc)
		);
		expect(response.status).toBe(500);
	});

	it('keeps the response out of any shared cache', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: commandResult(), error: null });
		const response = await POST(
			event({ idempotency_key: idempotencyKey, reopen_explanation: 'Client came back' }, rpc)
		);
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});
