import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const organizationId = '123e4567-e89b-12d3-a456-426614174000';
const exceptionId = '223e4567-e89b-12d3-a456-426614174000';
const idempotencyKey = '423e4567-e89b-12d3-a456-426614174000';
const exceptions = [{ id: exceptionId, status: 'active' }];
const entitlements = { capabilities: [], allowances: [{ key: 'employee_seats', in_use: 6 }] };

function event(body?: unknown) {
	return {
		params: { organizationId },
		request: new Request(`http://localhost/api/jafar/organizations/${organizationId}/exceptions`, {
			method: body === undefined ? 'GET' : 'POST',
			headers: { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function client(command: { data: unknown; error: { code: string; message: string } | null }) {
	const rpc = vi.fn((name: string) =>
		Promise.resolve(
			name === 'owner_organization_package_exceptions'
				? { data: exceptions, error: null }
				: name === 'owner_organization_entitlements'
					? { data: entitlements, error: null }
					: command
		)
	);
	const builder = {
		select: () => builder,
		eq: () => builder,
		maybeSingle: () => Promise.resolve({ data: { id: organizationId }, error: null })
	};
	return { from: () => builder, rpc };
}

const addSeats = {
	action: 'add',
	idempotency_key: idempotencyKey,
	target: 'allowance',
	key: 'employee_seats',
	allowance_state: 'numeric',
	allowance_value: 12,
	starts_at: '2026-10-01T00:00:00.000Z',
	ends_at: '2026-11-01T00:00:00.000Z',
	reason: 'Seasonal crew for October'
};

describe('package exceptions', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);

		expect((await GET(event())).status).toBe(401);
		expect((await POST(event(addSeats))).status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('lists every exception with the features and limits as they stand', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);
		mockedClient.mockReturnValue(client({ data: null, error: null }) as never);

		const response = await GET(event());

		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ exceptions, entitlements });
	});

	it('adds a limit exception, sending the feature side as null', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);
		const mock = client({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue(mock as never);

		const response = await POST(event(addSeats));

		expect(response.status).toBe(200);
		expect(mock.rpc).toHaveBeenCalledWith('add_organization_package_exception', {
			target_organization_id: organizationId,
			actor_owner_email: 'owner@example.com',
			idempotency_key: idempotencyKey,
			reason: 'Seasonal crew for October',
			capability_key: null,
			capability_state: null,
			allowance_key: 'employee_seats',
			allowance_state: 'numeric',
			allowance_value: 12,
			starts_at: addSeats.starts_at,
			ends_at: addSeats.ends_at
		});
		expect(await response.json()).toMatchObject({ exceptions, entitlements });
	});

	it('refuses an exception with no end, or ending before it starts', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);

		const noEnd = await POST(event({ ...addSeats, ends_at: undefined }));
		const backwards = await POST(event({ ...addSeats, ends_at: '2026-09-01T00:00:00.000Z' }));

		expect(noEnd.status).toBe(422);
		expect(backwards.status).toBe(422);
		expect((await backwards.json()).field_errors.ends_at).toBeTruthy();
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('refuses a feature exception without on or off', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);

		const response = await POST(
			event({ ...addSeats, target: 'capability', key: 'website_chat', allowance_state: null })
		);

		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.capability_state).toBeTruthy();
	});

	it('ends an exception early', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);
		const mock = client({ data: { applied: true }, error: null });
		mockedClient.mockReturnValue(mock as never);

		const response = await POST(
			event({
				action: 'end',
				idempotency_key: idempotencyKey,
				exception_id: exceptionId,
				reason: 'Crew left early'
			})
		);

		expect(response.status).toBe(200);
		expect(mock.rpc).toHaveBeenCalledWith('end_organization_package_exception', {
			target_organization_id: organizationId,
			actor_owner_email: 'owner@example.com',
			idempotency_key: idempotencyKey,
			reason: 'Crew left early',
			exception_id: exceptionId
		});
	});

	it('shows the database refusal in plain words', async () => {
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com' } as never);
		mockedClient.mockReturnValue(
			client({
				data: null,
				error: {
					code: '23514',
					message: '6 seats are in use now, so the limit cannot be lower than that.'
				}
			}) as never
		);

		const response = await POST(event({ ...addSeats, allowance_value: 3 }));

		expect(response.status).toBe(409);
		expect((await response.json()).error).toContain('6 seats are in use');
	});
});
