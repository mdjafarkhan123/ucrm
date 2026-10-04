import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { SETUP_VERSION_1 } from '$lib/setup/catalogue.fixture';

// Client onboarding C3: Jafar accepts or sends back one section of a client's newest send.

vi.mock('$lib/server/auth/owner', () => ({ getOwnerSession: vi.fn() }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

const ORGANIZATION_ID = '11111111-1111-4111-8111-111111111111';
const rpc = vi.fn();
let send: unknown = { setup_version_id: 'version-1', service_keys: [] };

const from = () => {
	const builder = {
		select: () => builder,
		eq: () => builder,
		maybeSingle: async () => ({ data: send, error: null })
	};
	return builder;
};

function call(body: unknown, organizationId = ORGANIZATION_ID) {
	return POST({
		params: { organizationId },
		request: new Request('http://localhost/api', {
			method: 'POST',
			body: typeof body === 'string' ? body : JSON.stringify(body)
		})
	} as never);
}

const reviewCalls = () => rpc.mock.calls.filter(([name]) => name === 'owner_review_setup_section');

describe('setup section review POST', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		send = { setup_version_id: 'version-1', service_keys: [] };
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
		expect((await call({ decision: 'accepted', section_key: 'business', send: 1 })).status).toBe(
			401
		);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses a return without a note, and extra fields on an acceptance', async () => {
		const empty = await call({ decision: 'returned', section_key: 'business', send: 1, note: ' ' });
		expect(empty.status).toBe(422);
		expect((await empty.json()).field_errors.note).toBe('Say what the client should change.');
		expect(
			(await call({ decision: 'accepted', section_key: 'business', send: 1, note: 'x' })).status
		).toBe(422);
		expect((await call('not json')).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('accepts a section through the audited command, naming Jafar', async () => {
		const response = await call({ decision: 'accepted', section_key: 'business', send: 1 });
		expect(response.status).toBe(200);
		expect(reviewCalls()[0][1]).toEqual({
			target_organization_id: ORGANIZATION_ID,
			target_section_key: 'business',
			seen_number: 1,
			new_decision: 'accepted',
			return_note: '',
			return_question_keys: [],
			actor_email: 'owner@example.com'
		});
	});

	it('returns a section with the ticked questions of that section only', async () => {
		const response = await call({
			decision: 'returned',
			section_key: 'business',
			send: 1,
			note: 'Use the name on your van.',
			question_keys: ['business.public_name']
		});
		expect(response.status).toBe(200);
		expect(reviewCalls()[0][1]).toMatchObject({
			new_decision: 'returned',
			return_note: 'Use the name on your van.',
			return_question_keys: ['business.public_name']
		});

		const foreign = await call({
			decision: 'returned',
			section_key: 'business',
			send: 1,
			note: 'Fix it.',
			question_keys: ['somewhere.else']
		});
		expect(foreign.status).toBe(422);
		expect(reviewCalls()).toHaveLength(1);
	});

	it('refuses a section the send does not have, or a send that does not exist', async () => {
		expect((await call({ decision: 'accepted', section_key: 'nowhere', send: 1 })).status).toBe(
			422
		);
		send = null;
		expect((await call({ decision: 'accepted', section_key: 'business', send: 9 })).status).toBe(
			404
		);
		expect(reviewCalls()).toHaveLength(0);
	});

	it('tells Jafar to look again when the client has sent since', async () => {
		rpc.mockImplementation(async (name: string) =>
			name === 'owner_setup_version_catalogue'
				? { data: SETUP_VERSION_1, error: null }
				: { data: { status: 'stale', latest_number: 2 }, error: null }
		);
		const response = await call({ decision: 'accepted', section_key: 'business', send: 1 });
		expect(response.status).toBe(409);
		expect(await response.json()).toMatchObject({ latest_number: 2 });
	});
});
