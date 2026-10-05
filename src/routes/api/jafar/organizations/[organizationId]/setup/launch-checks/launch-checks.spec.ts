import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Client onboarding E5: Jafar ticks, marks Doesn't apply or clears one launch check.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();

function call(body: unknown) {
	return POST({
		params: { organizationId: ORGANIZATION_ID },
		url: new URL('http://localhost/api'),
		request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) })
	} as never);
}

describe('launch check POST', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
		rpc.mockResolvedValue({ data: { status: 'saved' }, error: null });
	});

	it('needs the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await call({ version: 1, check_key: 'imports', outcome: 'checked' });
		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('ticks a line through the audited command, dropping a reason a tick does not need', async () => {
		const response = await call({
			version: 2,
			check_key: 'phone_look',
			outcome: 'checked',
			reason: '  '
		});
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_set_setup_launch_check', {
			target_organization_id: ORGANIZATION_ID,
			target_version: 2,
			target_check_key: 'phone_look',
			new_outcome: 'checked',
			new_reason: null,
			actor_email: 'owner@example.com'
		});
	});

	it('refuses Doesn’t apply without a reason, and a line that is not a check', async () => {
		const missing = await call({ version: 1, check_key: 'imports', outcome: 'not_applicable' });
		expect(missing.status).toBe(422);
		expect((await missing.json()).field_errors.reason).toBe('Say why this check doesn’t apply.');

		const unknown = await call({ version: 1, check_key: 'coffee', outcome: 'checked' });
		expect(unknown.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes on the database’s refusal in its own words', async () => {
		rpc.mockResolvedValueOnce({
			data: null,
			error: { code: '23514', message: 'This check waits on an outside step that is still open.' }
		});
		const response = await call({ version: 1, check_key: 'web_address', outcome: 'checked' });
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(
			'This check waits on an outside step that is still open.'
		);
	});
});
