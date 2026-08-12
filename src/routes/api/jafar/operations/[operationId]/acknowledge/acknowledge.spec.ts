import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const operationId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string) {
	return {
		params: { operationId: id },
		url: new URL('http://localhost/api/jafar/operations/' + id + '/acknowledge'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function clientWith(options: {
	selectData?: unknown;
	selectError?: { message: string } | null;
	updateError?: { message: string } | null;
}) {
	const { selectData = null, selectError = null, updateError = null } = options;
	const updateEq = vi.fn().mockResolvedValue({ error: updateError });
	const update = vi.fn(() => ({ eq: updateEq }));
	const maybeSingle = vi.fn().mockResolvedValue({ data: selectData, error: selectError });
	const select = vi.fn(() => ({ eq: () => ({ maybeSingle }) }));
	return { from: vi.fn(() => ({ select, update })), __update: update, __updateEq: updateEq };
}

describe('platform owner operation acknowledge API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(operationId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid operation identifier', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the operation does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ selectData: null }) as never);

		const response = await POST(event(operationId));
		expect(response.status).toBe(404);
	});

	it('rejects acknowledging an already-closed operation', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ selectData: { status: 'succeeded' } }) as never);

		const response = await POST(event(operationId));
		expect(response.status).toBe(409);
	});

	it('acknowledges an open operation as the calling owner', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith({ selectData: { status: 'retrying' } });
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(operationId));
		expect(response.status).toBe(200);
		expect(client.__update).toHaveBeenCalledWith(
			expect.objectContaining({
				status: 'acknowledged',
				acknowledged_by_owner_email: 'owner@example.com'
			})
		);
		expect(client.__updateEq).toHaveBeenCalledWith('id', operationId);
	});

	it('returns a safe server error when the update fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				selectData: { status: 'pending' },
				updateError: { message: 'internal database details' }
			}) as never
		);

		const response = await POST(event(operationId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The operation could not be acknowledged.' });
	});
});
