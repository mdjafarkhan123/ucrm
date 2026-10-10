import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const mockedOwnerSession = vi.mocked(getOwnerSession);
const mockedClient = vi.mocked(getOwnerSupabaseClient);

const prospectId = '123e4567-e89b-12d3-a456-426614174000';

function event(id: string, body: unknown) {
	const url = `http://localhost/api/jafar/prospects/${id}/qualify`;
	return {
		params: { prospectId: id },
		request: new Request(url, { method: 'POST', body: JSON.stringify(body) }),
		url: new URL(url),
		cookies: {}
	} as Parameters<typeof POST>[0];
}

const session = {
	email: 'owner@example.com',
	sessionId: 'session-id',
	role: null,
	access: null,
	memberId: null,
	name: null
};

function clientWith(rpcError: { message: string } | null = null) {
	const rpc = vi.fn().mockResolvedValue({ data: 'decision-1', error: rpcError });
	return { rpc };
}

const supported = {
	outcome: 'supported',
	experience_key: 'contractor',
	business_type_key: 'roofing',
	reviewed_work: 'Residential roof repair',
	reason: 'Checked their website'
};

describe('Uplift confirms the kind of business an Application is', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedOwnerSession.mockResolvedValue(session);
	});

	it('rejects callers without the separate owner session', async () => {
		mockedOwnerSession.mockResolvedValue(null);
		const response = await POST(event(prospectId, supported));
		expect(response.status).toBe(401);
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('records a supported decision with the experience and Business type', async () => {
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);
		const response = await POST(event(prospectId, supported));
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith('record_onboarding_application_qualification', {
			target_application_id: prospectId,
			actor_email: 'owner@example.com',
			target_outcome: 'supported',
			target_experience_key: 'contractor',
			target_business_type_key: 'roofing',
			target_reviewed_work: 'Residential roof repair',
			target_buyer_message: null,
			target_reason: 'Checked their website'
		});
	});

	it('holds with a message the business reads, sending nothing about an experience', async () => {
		const client = clientWith();
		mockedClient.mockReturnValue(client as never);
		const response = await POST(
			event(prospectId, {
				outcome: 'holding',
				buyer_message: 'Which treatments do you offer?',
				reason: 'Clinical boundary unclear'
			})
		);
		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'record_onboarding_application_qualification',
			expect.objectContaining({
				target_outcome: 'holding',
				target_experience_key: null,
				target_business_type_key: null,
				target_buyer_message: 'Which treatments do you offer?'
			})
		);
	});

	it('asks for the message before holding, without touching the database', async () => {
		const response = await POST(event(prospectId, { outcome: 'holding', reason: 'x' }));
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.buyer_message).toBeDefined();
		expect(mockedClient).not.toHaveBeenCalled();
	});

	it('returns 409 once the account is created', async () => {
		mockedClient.mockReturnValue(
			clientWith({
				message: 'The kind of business can only be decided before the account is created.'
			}) as never
		);
		const response = await POST(event(prospectId, supported));
		expect(response.status).toBe(409);
	});

	it('points at the Business type field when it is not one of the listed types', async () => {
		mockedClient.mockReturnValue(
			clientWith({ message: 'Choose one of the listed business types.' }) as never
		);
		const response = await POST(event(prospectId, supported));
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.business_type_key).toBeDefined();
	});
});
