import { beforeEach, describe, expect, it, vi } from 'vitest';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { deleteObject, putObject } from '$lib/server/storage/r2';
import { processProfilePhoto } from '$lib/server/profile/photo';
import { DELETE, POST } from './+server';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', () => ({
	checkRateLimit: vi.fn(),
	rateLimitedResponse: vi.fn(() => new Response(null, { status: 429 }))
}));
vi.mock('$lib/server/storage/r2', () => ({
	putObject: vi.fn(),
	deleteObject: vi.fn(),
	getObjectStream: vi.fn()
}));
vi.mock('$lib/server/profile/photo', async (original) => ({
	...(await original<typeof import('$lib/server/profile/photo')>()),
	processProfilePhoto: vi.fn()
}));

const memberId = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();

function session(member: string | null) {
	return {
		email: member ? 'sam@example.com' : 'jafar@example.com',
		sessionId: 'session-id',
		role: member ? ('sales' as const) : null,
		access: null,
		memberId: member,
		name: null
	};
}

function upload() {
	const body = new FormData();
	body.append('photo', new File([new Uint8Array([1, 2, 3])], 'me.jpg', { type: 'image/jpeg' }));
	return { request: new Request('http://test/api/jafar/account/photo', { method: 'POST', body }) };
}

function removal() {
	return { request: new Request('http://test/api/jafar/account/photo', { method: 'DELETE' }) };
}

type Event = Parameters<typeof POST>[0];

beforeEach(() => {
	vi.clearAllMocks();
	vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
	vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	vi.mocked(processProfilePhoto).mockResolvedValue(new Uint8Array([9]));
	rpc.mockResolvedValue({ data: null, error: null });
});

describe('a Jafar Panel person’s own photo', () => {
	it('refuses anyone without a panel session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await POST(upload() as Event);
		expect(response.status).toBe(401);
		expect(putObject).not.toHaveBeenCalled();
	});

	it('saves a teammate’s photo on their own record', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(session(memberId));
		const response = await POST(upload() as Event);
		const body = await response.json();

		expect(response.status).toBe(200);
		const [key] = vi.mocked(putObject).mock.calls[0];
		expect(key).toMatch(new RegExp(`^platform-photos/${memberId}/[0-9a-f-]{36}\\.webp$`));
		expect(rpc).toHaveBeenCalledWith('set_platform_team_member_photo', {
			target_member_id: memberId,
			new_photo_id: expect.any(String)
		});
		expect(body.avatar_url).toMatch(new RegExp(`^/api/jafar/photos/${memberId}\\?v=`));
	});

	it('saves Jafar’s photo on the owner settings, never on a teammate', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(session(null));
		const response = await POST(upload() as Event);
		const body = await response.json();

		expect(rpc).toHaveBeenCalledWith('set_platform_owner_photo', {
			new_photo_id: expect.any(String)
		});
		expect(body.avatar_url).toMatch(/^\/api\/jafar\/photos\/owner\?v=/);
	});

	it('deletes the replaced photo once the record points at the new one', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(session(memberId));
		rpc.mockResolvedValue({ data: `platform-photos/${memberId}/old.webp`, error: null });
		await POST(upload() as Event);
		expect(deleteObject).toHaveBeenCalledWith(`platform-photos/${memberId}/old.webp`);
	});

	it('removes the just-stored bytes when the record cannot be saved', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(session(memberId));
		rpc.mockResolvedValue({ data: null, error: { message: 'down' } });
		const response = await POST(upload() as Event);
		expect(response.status).toBe(500);
		const [stored] = vi.mocked(putObject).mock.calls[0];
		expect(deleteObject).toHaveBeenCalledWith(stored);
	});

	it('removes a teammate’s photo', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(session(memberId));
		rpc.mockResolvedValue({ data: `platform-photos/${memberId}/old.webp`, error: null });
		const response = await DELETE(removal() as Event);

		expect(await response.json()).toEqual({ avatar_url: null });
		expect(rpc).toHaveBeenCalledWith('set_platform_team_member_photo', {
			target_member_id: memberId
		});
		expect(deleteObject).toHaveBeenCalledWith(`platform-photos/${memberId}/old.webp`);
	});
});
