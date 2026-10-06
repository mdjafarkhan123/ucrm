import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const offerId = '323e4567-e89b-12d3-a456-426614174000';

function event(id = offerId) {
	return {
		params: { offerId: id },
		request: new Request(`http://localhost/api/jafar/package-offers/${id}`, { method: 'DELETE' }),
		cookies: {}
	} as Parameters<typeof DELETE>[0];
}

function client(result: { data: unknown; error: { code: string; message: string } | null }) {
	const rpc = vi.fn(() => Promise.resolve(result));
	mockedClient.mockReturnValue({ rpc } as never);
	return rpc;
}

describe('deleting an offer', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue({ email: 'owner@example.com', sessionId: 's' } as never);
	});

	it('refuses anyone who is not the platform owner', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const rpc = client({ data: null, error: null });
		const response = await DELETE(event());
		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('rejects an offer identifier that is not a UUID before touching the database', async () => {
		const rpc = client({ data: null, error: null });
		const response = await DELETE(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('deletes the offer as the signed-in owner', async () => {
		const rpc = client({ data: { deleted: true }, error: null });
		const response = await DELETE(event());
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ deleted: true });
		expect(rpc).toHaveBeenCalledWith('delete_package_offer', {
			offer_id: offerId,
			actor_owner_email: 'owner@example.com'
		});
	});

	it('passes the database reason through when a customer claimed the offer', async () => {
		client({
			data: null,
			error: {
				code: '23514',
				message: '1 customer has claimed this offer, so it stays on record. Archive it instead.'
			}
		});
		const response = await DELETE(event());
		expect(response.status).toBe(409);
		expect(await response.json()).toEqual({
			error: '1 customer has claimed this offer, so it stays on record. Archive it instead.'
		});
	});

	it('says so when the offer is already gone', async () => {
		client({ data: null, error: { code: '23503', message: 'That offer was not found.' } });
		const response = await DELETE(event());
		expect(response.status).toBe(404);
	});
});
