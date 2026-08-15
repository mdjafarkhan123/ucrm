import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';
const packageVersionId = '223e4567-e89b-12d3-a456-426614174000';

const validBody = {
	package_version_id: packageVersionId,
	reason: 'Prospect asked to switch to the Growth package before paying.'
};

function event(id: string, body: unknown = validBody) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/correct-package', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/correct-package'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', sessionId: 'session-id' };
}

function clientWith(rpcError: { message: string } | null = null) {
	const rpc = vi.fn().mockResolvedValue({ error: rpcError });
	return { rpc, __rpc: rpc };
}

describe('platform owner prospect package correction API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the request body before database access', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(event(prospectId, { ...validBody, package_version_id: 'nope' }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('requires a reason', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const response = await POST(event(prospectId, { ...validBody, reason: '  ' }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'The onboarding application does not exist.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects a change once the application is past review', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'This application can no longer be corrected.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('rejects a change once payment is already confirmed', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				message: 'The package can no longer be changed after payment is confirmed.'
			}) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('returns a field error when the selected package is not available', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'The selected package is not available.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(422);
		const result = await response.json();
		expect(result.field_errors.package_version_id).toBeDefined();
	});

	it('saves the package change on success', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith('correct_onboarding_application_package', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			new_package_version_id: packageVersionId,
			correction_reason: validBody.reason
		});
	});

	it('returns a safe server error when the change cannot be saved', async () => {
		mockedOwnerSession.mockResolvedValue(session());
		mockedClient.mockReturnValue(clientWith({ message: 'internal database details' }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The package could not be changed.' });
	});
});
