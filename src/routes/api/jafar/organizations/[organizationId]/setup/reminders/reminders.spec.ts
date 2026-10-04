import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PATCH } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Client onboarding C2: Jafar pauses or resumes one client's setup reminder emails.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();

function call(body: unknown, organizationId = ORGANIZATION_ID) {
	return PATCH({
		params: { organizationId },
		request: new Request('http://localhost/api', {
			method: 'PATCH',
			body: typeof body === 'string' ? body : JSON.stringify(body)
		})
	} as never);
}

describe('setup reminders PATCH', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
		rpc.mockResolvedValue({
			data: { paused_at: '2026-10-04T10:00:00Z', next_due_at: null, reminders_sent: 1 },
			error: null
		});
	});

	it('needs the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		expect((await call({ paused: true })).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a body that does not say paused or not', async () => {
		expect((await call({ paused: 'yes' })).status).toBe(422);
		expect((await call({ paused: true, extra: 1 })).status).toBe(422);
		expect((await call('not json')).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('pauses through the audited command, naming Jafar', async () => {
		const response = await call({ paused: true });
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_set_setup_reminders_paused', {
			target_organization_id: ORGANIZATION_ID,
			actor_email: 'owner@example.com',
			pause: true
		});
		expect(await response.json()).toMatchObject({ paused_at: '2026-10-04T10:00:00Z' });
	});

	it('reads a business without a reminder timer as missing', async () => {
		rpc.mockResolvedValue({ data: null, error: { code: 'P0002', message: 'none' } });
		expect((await call({ paused: false })).status).toBe(404);
		expect((await call({ paused: false }, 'not-a-uuid')).status).toBe(404);
	});
});
