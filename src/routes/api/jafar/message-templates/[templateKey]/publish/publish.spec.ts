import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

function single(data: unknown, error: null | { message: string } = null) {
	return { maybeSingle: () => Promise.resolve({ data, error }) };
}

function event(templateKey = 'password_setup') {
	return {
		params: { templateKey },
		url: new URL('http://localhost/api/jafar/message-templates/' + templateKey + '/publish'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function clientWith(readResult: { data: unknown; error: null | { message: string } }, rpc?: ReturnType<typeof vi.fn>) {
	return {
		from: () => ({ select: () => ({ eq: () => single(readResult.data, readResult.error) }) }),
		rpc: rpc ?? vi.fn()
	};
}

describe('platform owner message template publish API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event());
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('rejects an unknown template key', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not_a_real_key'));
		expect(response.status).toBe(404);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the template row does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ data: null, error: null }) as never);

		const response = await POST(event());
		expect(response.status).toBe(404);
	});

	it('rejects publishing empty content', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ data: { subject_draft: null, body_draft: '   ' }, error: null }) as never
		);

		const response = await POST(event());
		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.error).toMatch(/content/i);
	});

	it('rejects publishing when a required tag was removed from the draft', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({
				data: { subject_draft: 'Hello {{business_name}}', body_draft: 'No link here.' },
				error: null
			}) as never
		);

		const response = await POST(event());
		expect(response.status).toBe(422);
		const body = await response.json();
		expect(body.missing_placeholders).toEqual(['setup_link']);
	});

	it('publishes when every required tag is present', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: { template_key: 'password_setup' }, error: null });
		mockedClient.mockReturnValue(
			clientWith(
				{
					data: { subject_draft: 'Hello {{business_name}}', body_draft: 'Click {{setup_link}}.' },
					error: null
				},
				rpc
			) as never
		);

		const response = await POST(event());
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('publish_message_template', {
			target_template_key: 'password_setup',
			actor_email: 'owner@example.com'
		});
	});

	it('returns a safe server error when the publish RPC fails', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const rpc = vi.fn().mockResolvedValue({ data: null, error: { message: 'internal database details' } });
		mockedClient.mockReturnValue(
			clientWith(
				{ data: { subject_draft: null, body_draft: 'Click {{setup_link}}.' }, error: null },
				rpc
			) as never
		);

		const response = await POST(event());
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The message template could not be published.' });
	});
});
