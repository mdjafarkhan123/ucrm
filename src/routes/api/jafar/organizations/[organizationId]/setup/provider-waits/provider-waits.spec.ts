import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { sendProviderWaitEmails } from '$lib/server/setup/provider-waits';

// Client onboarding E2: Jafar moves one of a client's outside waits; "You need to do something" emails them.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$env/dynamic/private', () => ({ env: {} }));
vi.mock('$lib/server/setup/provider-waits', () => ({
	readOwnerProviderWaits: vi.fn(),
	sendProviderWaitEmails: vi.fn()
}));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();

function call(body: unknown) {
	return POST({
		params: { organizationId: ORGANIZATION_ID },
		url: new URL('http://localhost/api'),
		request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) })
	} as never);
}

describe('outside wait POST', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ rpc } as never);
		rpc.mockResolvedValue({ data: { status: 'saved' }, error: null });
		vi.mocked(sendProviderWaitEmails).mockResolvedValue(1);
	});

	it('needs the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await call({ wait_key: 'google_profile', status: 'in_review' });
		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('records a stage through the audited command without emailing the client', async () => {
		const response = await call({ wait_key: 'google_profile', status: 'in_review', note: '  ' });
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('owner_set_setup_provider_wait', {
			target_organization_id: ORGANIZATION_ID,
			target_wait_key: 'google_profile',
			new_status: 'in_review',
			new_note: null,
			actor_email: 'owner@example.com'
		});
		expect(sendProviderWaitEmails).not.toHaveBeenCalled();
	});

	it('refuses "You need to do something" without saying what', async () => {
		const response = await call({ wait_key: 'texting_approval', status: 'action_needed' });
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.note).toBe('Say what the client needs to do.');
		expect(rpc).not.toHaveBeenCalled();
	});

	it('emails the client when they need to do something, and says when that email failed', async () => {
		const body = { wait_key: 'texting_approval', status: 'action_needed', note: 'Upload a bill' };
		expect(await (await call(body)).json()).toMatchObject({ status: 'saved', emailed: true });
		expect(sendProviderWaitEmails).toHaveBeenCalledWith(expect.anything(), {
			organizationId: ORGANIZATION_ID,
			waitKey: 'texting_approval',
			origin: 'http://localhost'
		});

		vi.mocked(sendProviderWaitEmails).mockRejectedValueOnce(new Error('outbox down'));
		const failed = await call(body);
		expect(failed.status).toBe(200);
		expect(await failed.json()).toMatchObject({ emailed: false });
	});

	it('clears a wait back to not started', async () => {
		await call({ wait_key: 'website_address', status: null });
		expect(rpc).toHaveBeenCalledWith(
			'owner_set_setup_provider_wait',
			expect.objectContaining({ new_status: null, new_note: null })
		);
	});

	it('refuses an unknown wait or stage', async () => {
		expect((await call({ wait_key: 'fax_line', status: 'approved' })).status).toBe(422);
		expect((await call({ wait_key: 'google_profile', status: 'done' })).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('passes on the database’s own refusal, such as a service outside the package', async () => {
		rpc.mockResolvedValueOnce({
			data: null,
			error: { code: '23514', message: 'This client’s package does not include that service.' }
		});
		const response = await call({ wait_key: 'google_profile', status: 'submitted' });
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toContain('does not include');
	});
});
