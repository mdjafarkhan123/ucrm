import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE, POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readClientSetupView } from '$lib/server/setup/client-page';
import type { ClientSetupView } from '$lib/setup/client-page';

// Client onboarding C4: Jafar records Ready for Uplift on a client's newest send, or takes it back with a reason.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/setup/client-page', () => ({ readClientSetupView: vi.fn() }));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();

function view(overrides: Partial<ClientSetupView> = {}): ClientSetupView {
	return {
		sends: [
			{
				number: 2,
				submitted_at: '2026-10-05T08:00:00Z',
				submitted_by_name: 'Sam',
				submitted_by_email: 'sam@example.com'
			}
		],
		send: null,
		reviews: {},
		help: [],
		help_units: { country: null, currency: null },
		unsent_changes: 0,
		reminders: null,
		ready: null,
		ready_blockers: [],
		time_zone: 'Europe/London',
		settings_copies: [],
		...overrides
	};
}

function call(handler: typeof POST, body: unknown, organizationId = ORGANIZATION_ID) {
	return handler({
		params: { organizationId },
		request: new Request('http://localhost/api', {
			method: handler === POST ? 'POST' : 'DELETE',
			body: typeof body === 'string' ? body : JSON.stringify(body)
		})
	} as never);
}

describe('setup Ready for Uplift', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
		vi.mocked(readClientSetupView).mockResolvedValue(view());
		rpc.mockResolvedValue({
			data: { status: 'saved', target_from: '2026-10-14', target_to: '2026-10-19' },
			error: null
		});
	});

	it('needs the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		expect((await call(POST, { send: 2 })).status).toBe(401);
		expect((await call(DELETE, { reason: 'Mistake' })).status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses Ready while a blocker remains, and names it', async () => {
		const blockers = [
			{ kind: 'task', section_key: 'brand', section_title: 'Brand', state: 'to_review' }
		] as const;
		vi.mocked(readClientSetupView).mockResolvedValue(view({ ready_blockers: [...blockers] }));
		const response = await call(POST, { send: 2 });
		expect(response.status).toBe(409);
		expect((await response.json()).blockers).toEqual(blockers);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses Ready on a send that is no longer the newest', async () => {
		const response = await call(POST, { send: 1 });
		expect(response.status).toBe(409);
		expect((await response.json()).latest_number).toBe(2);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('records Ready on the newest send once nothing blocks it', async () => {
		const response = await call(POST, { send: 2 });
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_mark_setup_ready', {
			target_organization_id: ORGANIZATION_ID,
			seen_number: 2,
			actor_email: 'owner@example.com'
		});
	});

	it('passes on what the database refuses in its own words', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '23514', message: 'A task is sent back and waiting for the client.' }
		});
		const response = await call(POST, { send: 2 });
		expect(response.status).toBe(409);
		expect((await response.json()).error).toBe('A task is sent back and waiting for the client.');
	});

	it('takes Ready back only with a reason', async () => {
		const empty = await call(DELETE, { reason: '  ' });
		expect(empty.status).toBe(422);
		expect((await empty.json()).field_errors.reason).toBe('Say why you are taking it back.');
		expect(rpc).not.toHaveBeenCalled();

		expect((await call(DELETE, { reason: 'Pressed on the wrong client' })).status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_withdraw_setup_ready', {
			target_organization_id: ORGANIZATION_ID,
			withdraw_reason: 'Pressed on the wrong client',
			actor_email: 'owner@example.com'
		});
	});
});
