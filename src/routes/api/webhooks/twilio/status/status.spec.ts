import { createHmac } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: { APP_URL: 'https://app.example.com' } }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/communications/twilio-provisioning-store', () => ({
	createSupabaseTwilioProvisioningStore: vi.fn(() => fakeStore)
}));
vi.mock('$lib/server/communications/twilio-credential-crypto', () => ({
	// The route's decrypt step is stubbed: the token is carried on the fake credential's envelope.
	decryptTwilioCredential: (encrypted: { __token: string }) => encrypted.__token
}));

import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

const URL = 'https://app.example.com/api/webhooks/twilio/status';
const ACCOUNT_SID = 'AC00000000000000000000000000000001';
const MESSAGE_SID = 'SM00000000000000000000000000000001';

const account = {
	id: 'account-1',
	organizationId: '00000000-0000-4000-8000-000000000001',
	subaccountSid: ACCOUNT_SID,
	messagingServiceSid: null,
	lifecycleState: 'ready'
};

// Configured per test.
let fakeStore: {
	getAccountBySubaccountSid: ReturnType<typeof vi.fn>;
	getCredential: ReturnType<typeof vi.fn>;
};

function credential(token: string, retireAfter: string | null = null) {
	return { id: `cred-${token}`, encrypted: { __token: token }, retireAfter };
}

function twilioSignature(token: string, params: Record<string, string>) {
	const data = Object.keys(params)
		.sort()
		.reduce((acc, key) => acc + key + params[key], URL);
	return createHmac('sha1', token).update(Buffer.from(data, 'utf-8')).digest('base64');
}

function statusRequest(params: Record<string, string>, signature: string | null) {
	return {
		request: new Request(URL, {
			method: 'POST',
			headers: {
				'content-type': 'application/x-www-form-urlencoded',
				...(signature ? { 'x-twilio-signature': signature } : {})
			},
			body: new URLSearchParams(params).toString()
		})
	} as Parameters<typeof POST>[0];
}

function makeClient(options: {
	intent?: { id: string } | null;
	insertError?: { code?: string } | null;
}) {
	const insert = vi.fn().mockResolvedValue({ error: options.insertError ?? null });
	const rpc = vi.fn().mockResolvedValue({ error: null });
	const maybeSingle = vi.fn().mockResolvedValue({ data: options.intent ?? null });
	const chain = { eq: vi.fn(() => chain), maybeSingle };
	const select = vi.fn(() => chain);
	const from = vi.fn((table: string) =>
		table === 'communication_delivery_intents' ? { select } : { insert }
	);
	return { from, insert, rpc, select, maybeSingle };
}

const validParams = {
	MessageSid: MESSAGE_SID,
	MessageStatus: 'delivered',
	AccountSid: ACCOUNT_SID,
	To: '+15005550006'
};

beforeEach(() => {
	vi.clearAllMocks();
	fakeStore = {
		getAccountBySubaccountSid: vi.fn().mockResolvedValue(account),
		getCredential: vi.fn(async ({ lifecycleState }: { lifecycleState: string }) =>
			lifecycleState === 'current' ? credential('current-token') : null
		)
	};
});

describe('Twilio status callback route', () => {
	it('rejects a malformed payload before touching the database', async () => {
		const response = await POST(
			statusRequest(
				{ MessageSid: 'nope', MessageStatus: 'delivered', AccountSid: ACCOUNT_SID },
				'sig'
			)
		);
		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects a forged AccountSid with no matching subaccount', async () => {
		fakeStore.getAccountBySubaccountSid.mockResolvedValue(null);
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(403);
		expect(client.insert).not.toHaveBeenCalled();
	});

	it('rejects an invalid signature', async () => {
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('wrong-token', validParams))
		);

		expect(response.status).toBe(403);
		expect(client.insert).not.toHaveBeenCalled();
	});

	it('records an unknown MessageSid unresolved and still drains', async () => {
		const client = makeClient({ intent: null });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(204);
		expect(client.insert).toHaveBeenCalledWith(
			expect.objectContaining({
				provider: 'twilio',
				channel: 'sms',
				provider_event_key: `${MESSAGE_SID}:delivered`,
				delivery_intent_id: null,
				event_kind: 'delivered'
			})
		);
		expect(client.rpc).toHaveBeenCalledWith('process_communication_sms_provider_callbacks', {
			batch_size: 25
		});
	});

	it('records a resolved status against its delivery intent', async () => {
		const client = makeClient({ intent: { id: 'intent-1' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(204);
		expect(client.insert).toHaveBeenCalledWith(
			expect.objectContaining({ delivery_intent_id: 'intent-1' })
		);
	});

	it('treats a duplicate event as accepted and still drains', async () => {
		const client = makeClient({ intent: { id: 'intent-1' }, insertError: { code: '23505' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(204);
		expect(client.rpc).toHaveBeenCalled();
	});

	it('asks the provider to retry when the event could not be stored', async () => {
		const client = makeClient({ intent: { id: 'intent-1' }, insertError: { code: '08006' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(500);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('still accepts the event when on-arrival draining fails', async () => {
		const client = makeClient({ intent: { id: 'intent-1' } });
		client.rpc.mockResolvedValue({ error: { code: '57014' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(204);
	});

	it('accepts a signature made with the just-promoted staged token during rotation', async () => {
		fakeStore.getCredential = vi.fn(async ({ lifecycleState }: { lifecycleState: string }) => {
			if (lifecycleState === 'current') return credential('current-token');
			if (lifecycleState === 'staged') return credential('staged-token');
			return null;
		});
		const client = makeClient({ intent: { id: 'intent-1' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('staged-token', validParams))
		);

		expect(response.status).toBe(204);
	});

	it('rejects a prior token whose retirement window has passed', async () => {
		fakeStore.getCredential = vi.fn(async ({ lifecycleState }: { lifecycleState: string }) => {
			if (lifecycleState === 'current') return credential('current-token');
			if (lifecycleState === 'prior') return credential('prior-token', '2000-01-01T00:00:00.000Z');
			return null;
		});
		const client = makeClient({ intent: { id: 'intent-1' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			statusRequest(validParams, twilioSignature('prior-token', validParams))
		);

		expect(response.status).toBe(403);
		expect(client.insert).not.toHaveBeenCalled();
	});
});
