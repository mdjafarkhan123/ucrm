import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

const validBody = {
	business_name: 'Bright Co',
	main_contact_name: 'Jamie Rivera',
	main_contact_email: 'jamie@bright.co',
	main_contact_phone: '+1 555 111 2222',
	initial_administrator_name: null,
	initial_administrator_email: null,
	trade: 'Electrical',
	city_country: 'Austin, USA',
	time_zone: 'America/Chicago',
	note: null,
	reason: 'Applicant emailed a spelling correction for the business name.'
};

function event(id: string, body: unknown = validBody) {
	return {
		params: { prospectId: id },
		request: new Request('http://localhost/api/jafar/prospects/' + id + '/correct', {
			method: 'POST',
			body: JSON.stringify(body),
			headers: { 'content-type': 'application/json' }
		}),
		url: new URL('http://localhost/api/jafar/prospects/' + id + '/correct'),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

function session() {
	return { email: 'owner@example.com', expiresAt: Date.now() + 1000 };
}

function clientWith(rpcError: { message: string } | null = null) {
	const rpc = vi.fn().mockResolvedValue({ error: rpcError });
	return { rpc, __rpc: rpc };
}

describe('platform owner prospect correction API boundary', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockReturnValue(null);
		const response = await POST(event(prospectId));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the prospect identifier before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event('not-a-uuid'));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('validates the request body before database access', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const response = await POST(event(prospectId, { ...validBody, main_contact_email: 'nope' }));
		expect(response.status).toBe(422);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 404 when the prospect does not exist', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'The onboarding application does not exist.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(404);
	});

	it('rejects a correction once the application is past review', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(
			clientWith({ message: 'This application can no longer be corrected.' }) as never
		);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(409);
	});

	it('saves the correction and records before/after state on success', async () => {
		mockedOwnerSession.mockReturnValue(session());
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(200);
		expect(client.__rpc).toHaveBeenCalledWith('correct_onboarding_application', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			correction_reason: validBody.reason,
			new_business_name: 'Bright Co',
			new_main_contact_name: 'Jamie Rivera',
			new_main_contact_email: 'jamie@bright.co',
			new_main_contact_phone: '+1 555 111 2222',
			new_initial_administrator_name: null,
			new_initial_administrator_email: null,
			new_trade: 'Electrical',
			new_city_country: 'Austin, USA',
			new_time_zone: 'America/Chicago',
			new_note: null
		});
	});

	it('returns a safe server error when the correction cannot be saved', async () => {
		mockedOwnerSession.mockReturnValue(session());
		mockedClient.mockReturnValue(clientWith({ message: 'internal database details' }) as never);

		const response = await POST(event(prospectId));
		expect(response.status).toBe(500);
		expect(await response.json()).toEqual({ error: 'The correction could not be saved.' });
	});
});
