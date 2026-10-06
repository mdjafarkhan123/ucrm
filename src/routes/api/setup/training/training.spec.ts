import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as saveTraining } from './+server';
import { POST as skipTraining } from './skip/+server';
import { POST as setConsent } from './consent/+server';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { checkRateLimit } from '$lib/server/security/rate-limit';
import { tellOwnerToRestrictRecording } from '$lib/server/setup/training';

// Client onboarding E6: the client's training details, the owner's skip, and recording consent.

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationAdmin: vi.fn() };
});
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});
vi.mock('$lib/server/setup/training', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/setup/training')>(
		'$lib/server/setup/training'
	);
	return { ...actual, tellOwnerToRestrictRecording: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn(() => ({})) }));

const ORGANIZATION_ID = 'org-1';
const rpc = vi.fn();

function call(handler: (event: never) => Response | Promise<Response>, body: unknown = {}) {
	return handler({
		locals: { supabase: { rpc } },
		url: new URL('http://localhost/api'),
		request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) })
	} as never);
}

function signedInAs(role: 'owner' | 'admin') {
	vi.mocked(requireOrganizationAdmin).mockResolvedValue({
		auth: { organization: { id: ORGANIZATION_ID, role }, user: { id: 'user-1' } }
	} as never);
}

const details = {
	attendees: [{ name: ' Sam ', role: '', email: 'sam@example.com' }],
	time_zone: 'Europe/London',
	preferred_times: 'Weekday mornings',
	needs: '  ',
	top_tasks: null,
	recording_consent: true
};

describe('client training routes', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		signedInAs('owner');
		vi.mocked(checkRateLimit).mockResolvedValue({ allowed: true } as never);
		rpc.mockResolvedValue({ data: { status: 'saved', restrict_recording: false }, error: null });
	});

	it('saves the details, sending blank answers as null so the command is found', async () => {
		const response = await call(saveTraining, details);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('client_save_setup_training', {
			target_organization_id: ORGANIZATION_ID,
			new_attendees: [{ name: 'Sam', role: '', email: 'sam@example.com' }],
			new_time_zone: 'Europe/London',
			new_preferred_times: 'Weekday mornings',
			new_needs: null,
			new_top_tasks: null,
			consent: true
		});
		expect(tellOwnerToRestrictRecording).not.toHaveBeenCalled();
	});

	it('refuses details without a person, or with a made-up time zone', async () => {
		expect((await call(saveTraining, { ...details, attendees: [] })).status).toBe(422);
		expect((await call(saveTraining, { ...details, time_zone: 'Mars/Base' })).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('lets only the owner say they don’t need training', async () => {
		signedInAs('admin');
		const refused = await call(skipTraining);
		expect(refused.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();

		signedInAs('owner');
		const response = await call(skipTraining);
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('client_skip_setup_training', {
			target_organization_id: ORGANIZATION_ID
		});
	});

	it('gives Jafar a task when a withdrawal hides a recording', async () => {
		rpc.mockResolvedValueOnce({
			data: { status: 'saved', restrict_recording: true },
			error: null
		});
		const response = await call(setConsent, { recording_consent: false });
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('client_set_setup_training_consent', {
			target_organization_id: ORGANIZATION_ID,
			consent: false
		});
		expect(tellOwnerToRestrictRecording).toHaveBeenCalledOnce();
	});

	it('passes on the database’s refusal in its own words', async () => {
		rpc.mockResolvedValueOnce({
			data: null,
			error: { code: '23514', message: 'Uplift has booked your training. Ask in Chat with Uplift.' }
		});
		const response = await call(saveTraining, details);
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.form).toBe(
			'Uplift has booked your training. Ask in Chat with Uplift.'
		);
	});
});
