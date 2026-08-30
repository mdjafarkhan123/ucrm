import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/access/owner', () => ({
	ownerUnauthorized: () => new Response('unauthorized', { status: 401 })
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

function requestEvent() {
	return {
		request: new Request('https://app.example.com/api/jafar/communications/email-health')
	} as Parameters<typeof GET>[0];
}

describe('Platform Owner email-health route', () => {
	beforeEach(() => vi.clearAllMocks());

	it('refuses a request without an owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null as never);

		const response = await GET(requestEvent());

		expect(response.status).toBe(401);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('returns the sending, return-path callback, and worker health side by side', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({ email: 'owner@example.com' } as never);
		const rpc = vi.fn((name: string) =>
			Promise.resolve({
				data:
					name === 'get_communication_email_sending_health'
						? { platform_pause: null, queued_email_count: 3 }
						: name === 'get_communication_provider_callback_health'
							? { unprocessed_count: 0, last_success_at: '2026-08-29T00:00:00Z' }
							: { job: null, due_count: 0, oldest_due_age_seconds: null },
				error: null
			})
		);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);

		const response = await GET(requestEvent());

		expect(response.status).toBe(200);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(rpc).toHaveBeenCalledWith('get_communication_email_sending_health');
		expect(rpc).toHaveBeenCalledWith('get_communication_provider_callback_health');
		expect(rpc).toHaveBeenCalledWith('get_communication_email_worker_health');
		expect(await response.json()).toEqual({
			health: { platform_pause: null, queued_email_count: 3 },
			callback_health: { unprocessed_count: 0, last_success_at: '2026-08-29T00:00:00Z' },
			worker_health: { job: null, due_count: 0, oldest_due_age_seconds: null }
		});
	});

	it('surfaces a 500 when a health read fails', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue({ email: 'owner@example.com' } as never);
		const rpc = vi.fn((name: string) =>
			Promise.resolve(
				name === 'get_communication_provider_callback_health'
					? { data: null, error: { message: 'boom' } }
					: { data: {}, error: null }
			)
		);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);

		const response = await GET(requestEvent());

		expect(response.status).toBe(500);
	});
});
