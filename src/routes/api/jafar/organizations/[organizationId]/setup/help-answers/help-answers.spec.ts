import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { SETUP_VERSION_1 } from '$lib/setup/catalogue.fixture';

// Client onboarding C3c: Jafar records the answer Uplift found for a question the client asked help with.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();
const SEND = {
	setup_version_id: 'version-1',
	service_keys: [],
	answers: {
		'business.public_name': { availability: 'have', value: 'Raad LTD', note: null },
		'business.public_phone': { availability: 'need_help', value: null, note: 'We need a number' }
	}
};
let send: unknown = SEND;

const from = () => {
	const builder = {
		select: () => builder,
		eq: () => builder,
		maybeSingle: async () => ({ data: send, error: null })
	};
	return builder;
};

function call(body: unknown) {
	return POST({
		params: { organizationId: ORGANIZATION_ID },
		request: new Request('http://localhost/api', {
			method: 'POST',
			body: typeof body === 'string' ? body : JSON.stringify(body)
		})
	} as never);
}

const answerCalls = () => rpc.mock.calls.filter(([name]) => name === 'owner_answer_setup_help');

describe('setup help answer POST', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		send = SEND;
		vi.mocked(getOwnerSession).mockResolvedValue({
			email: 'owner@example.com',
			sessionId: 'session-id'
		} as never);
		vi.mocked(getOwnerSupabaseClient).mockReturnValue({ from, rpc } as never);
		rpc.mockImplementation(async (name: string) =>
			name === 'owner_setup_version_catalogue'
				? { data: SETUP_VERSION_1, error: null }
				: { data: { status: 'saved' }, error: null }
		);
	});

	it('needs the separate owner session', async () => {
		vi.mocked(getOwnerSession).mockResolvedValue(null);
		const response = await call({
			send: 1,
			fact_key: 'business.public_phone',
			value: '+44 20 7946 0000'
		});
		expect(response.status).toBe(401);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('records an answer in the client’s own box through the audited command', async () => {
		const response = await call({
			send: 1,
			fact_key: 'business.public_phone',
			value: ' +44 20 7946 0000 '
		});
		expect(response.status).toBe(200);
		expect(answerCalls()[0][1]).toEqual({
			target_organization_id: ORGANIZATION_ID,
			target_fact_key: 'business.public_phone',
			seen_number: 1,
			new_value: '+44 20 7946 0000',
			new_note: '',
			actor_email: 'owner@example.com'
		});
	});

	it('checks the value by the question’s own rules', async () => {
		const response = await call({ send: 1, fact_key: 'business.public_phone', value: 'call us' });
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.value).toBeTruthy();
		const empty = await call({ send: 1, fact_key: 'business.public_phone', note: 'Found it' });
		expect(empty.status).toBe(422);
		expect((await empty.json()).field_errors.value).toBe('Enter an answer.');
		expect(answerCalls()).toHaveLength(0);
	});

	it('refuses a question the client did not ask help with', async () => {
		const response = await call({ send: 1, fact_key: 'business.public_name', value: 'Other' });
		expect(response.status).toBe(422);
		expect((await response.json()).field_errors.fact_key).toBeTruthy();
		expect((await call({ send: 1, fact_key: 'nope', value: 'x' })).status).toBe(422);
		expect(answerCalls()).toHaveLength(0);
	});

	it('refuses an unknown send, and an answer on an earlier one', async () => {
		send = null;
		expect(
			(await call({ send: 9, fact_key: 'business.public_phone', value: '+44 20 7946 0000' })).status
		).toBe(404);
		send = SEND;
		rpc.mockImplementation(async (name: string) =>
			name === 'owner_setup_version_catalogue'
				? { data: SETUP_VERSION_1, error: null }
				: { data: { status: 'stale', latest_number: 2 }, error: null }
		);
		const stale = await call({
			send: 1,
			fact_key: 'business.public_phone',
			value: '+44 20 7946 0000'
		});
		expect(stale.status).toBe(409);
		expect((await stale.json()).latest_number).toBe(2);
	});

	it('refuses extra fields and broken bodies', async () => {
		expect(
			(await call({ send: 1, fact_key: 'business.public_phone', value: '1', x: 1 })).status
		).toBe(422);
		expect((await call('not json')).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});
});
