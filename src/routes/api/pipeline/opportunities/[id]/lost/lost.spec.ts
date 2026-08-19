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
		outcome: 'lost',
		outcome_at: '2026-08-19T00:00:00Z',
		...overrides
	};
}

function event(body: unknown, rpc = vi.fn()) {
	return {
		params: { id: opportunityId },
		request: new Request(`http://localhost/api/pipeline/opportunities/${opportunityId}/lost`, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: typeof body === 'string' ? body : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } }
	} as unknown as Parameters<typeof POST>[0];
}

describe('mark opportunity lost', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context);
	});

	it('needs pipeline.edit', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const rpc = vi.fn();

		const response = await POST(event({ idempotency_key: idempotencyKey }, rpc));

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
		const response = await POST(event({ idempotency_key: 'not-a-uuid' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.idempotency_key).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects a reason outside the fixed vocabulary before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(event({ idempotency_key: idempotencyKey, reason: 'because' }, rpc));

		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('requires a note when the reason is Other, before querying the database', async () => {
		const rpc = vi.fn();
		const response = await POST(event({ idempotency_key: idempotencyKey, reason: 'other' }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.note).toBeDefined();
		expect(rpc).not.toHaveBeenCalled();
	});

	it('accepts Other with a note and sends the reason and note through', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: commandResult(), error: null });

		const response = await POST(
			event({ idempotency_key: idempotencyKey, reason: 'other', note: 'Client went silent' }, rpc)
		);

		expect(rpc).toHaveBeenCalledWith('pipeline_mark_opportunity_lost', {
			target_opportunity_id: opportunityId,
			idempotency_key: idempotencyKey,
			reason: 'other',
			note: 'Client went silent'
		});
		expect(response.status).toBe(200);
	});

	it('leaves reason and note null when neither is sent', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: commandResult(), error: null });

		await POST(event({ idempotency_key: idempotencyKey }, rpc));

		expect(rpc).toHaveBeenCalledWith('pipeline_mark_opportunity_lost', {
			target_opportunity_id: opportunityId,
			idempotency_key: idempotencyKey,
			reason: null,
			note: null
		});
	});

	it('returns the command result the RPC answers, including a retried command', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: commandResult({ applied: false }), error: null });

		const response = await POST(event({ idempotency_key: idempotencyKey }, rpc));

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual(commandResult({ applied: false }));
	});

	it('turns a refusal from the function into a generic not-found', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '42501', message: 'insufficient_privilege' }
		});

		const response = await POST(event({ idempotency_key: idempotencyKey }, rpc));

		expect(response.status).toBe(404);
	});

	it('turns a database check-violation (already closed, wrong state) into a form error', async () => {
		const rpc = vi.fn().mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'Only an open opportunity can be marked lost.' }
		});

		const response = await POST(event({ idempotency_key: idempotencyKey }, rpc));

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('open opportunity');
	});

	it('turns any other database error into a generic failure', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '08000' } });
		const response = await POST(event({ idempotency_key: idempotencyKey }, rpc));
		expect(response.status).toBe(500);
	});

	it('keeps the response out of any shared cache', async () => {
		const rpc = vi.fn().mockResolvedValue({ data: commandResult(), error: null });
		const response = await POST(event({ idempotency_key: idempotencyKey }, rpc));
		expect(response.headers.get('cache-control')).toBe('no-store');
	});
});
