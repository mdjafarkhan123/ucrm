import { createHmac } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('$env/dynamic/private', () => ({ env: { APP_URL: 'https://app.example.com' } }));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/communications/twilio-provisioning-store', () => ({
	createSupabaseTwilioProvisioningStore: vi.fn(() => fakeStore)
}));
vi.mock('$lib/server/communications/twilio-credential-crypto', () => ({
	decryptTwilioCredential: (encrypted: { __token: string }) => encrypted.__token
}));

import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

const URL = 'https://app.example.com/api/webhooks/twilio/inbound';
const ACCOUNT_SID = 'AC00000000000000000000000000000001';
const MESSAGE_SID = 'SM00000000000000000000000000000001';

const account = {
	id: 'account-1',
	organizationId: '00000000-0000-4000-8000-000000000001',
	subaccountSid: ACCOUNT_SID,
	messagingServiceSid: null,
	lifecycleState: 'ready'
};

let fakeStore: {
	getAccountBySubaccountSid: ReturnType<typeof vi.fn>;
	getCredential: ReturnType<typeof vi.fn>;
};

function credential(token: string) {
	return { id: `cred-${token}`, encrypted: { __token: token }, retireAfter: null };
}

function twilioSignature(token: string, params: Record<string, string>) {
	const data = Object.keys(params)
		.sort()
		.reduce((acc, key) => acc + key + params[key], URL);
	return createHmac('sha1', token).update(Buffer.from(data, 'utf-8')).digest('base64');
}

function inboundRequest(params: Record<string, string>, signature: string | null) {
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
	messageError?: { code?: string } | null;
	consentError?: { code?: string } | null;
	messageData?: { id: string; organization_id: string } | null;
	attachmentError?: { code?: string } | null;
}) {
	const insert = vi.fn().mockResolvedValue({ error: options.attachmentError ?? null });
	const from = vi.fn(() => ({ insert }));
	const rpc = vi.fn((fn: string) => {
		if (fn === 'record_communication_sms_inbound_message') {
			return Promise.resolve({
				data: options.messageError
					? null
					: (options.messageData ?? { id: 'message-1', organization_id: account.organizationId }),
				error: options.messageError ?? null
			});
		}
		if (fn === 'record_communication_sms_consent_event_from_reply') {
			return Promise.resolve({ error: options.consentError ?? null });
		}
		return Promise.resolve({ error: null });
	});
	return { rpc, from, insert };
}

const validParams = {
	MessageSid: MESSAGE_SID,
	AccountSid: ACCOUNT_SID,
	From: '+15005550006',
	To: '+15005550001',
	Body: 'Ahoy!',
	NumMedia: '0'
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

describe('Twilio inbound message route', () => {
	it('rejects a malformed payload before touching the database', async () => {
		const response = await POST(
			inboundRequest({ MessageSid: 'nope', AccountSid: ACCOUNT_SID, From: '+1', To: '+1' }, 'sig')
		);
		expect(response.status).toBe(403);
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects a forged AccountSid with no matching subaccount', async () => {
		fakeStore.getAccountBySubaccountSid.mockResolvedValue(null);
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			inboundRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(403);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('rejects an invalid signature', async () => {
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			inboundRequest(validParams, twilioSignature('wrong-token', validParams))
		);

		expect(response.status).toBe(403);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('records an ordinary reply and returns empty TwiML', async () => {
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			inboundRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(200);
		expect(response.headers.get('content-type')).toBe('text/xml');
		expect(await response.text()).toBe('<Response/>');
		expect(client.rpc).toHaveBeenCalledWith('record_communication_sms_inbound_message', {
			target_organization_id: account.organizationId,
			target_provider_message_id: MESSAGE_SID,
			target_from_number: validParams.From,
			target_body: 'Ahoy!',
			target_num_media: 0
		});
		expect(client.rpc).not.toHaveBeenCalledWith(
			'record_communication_sms_consent_event_from_reply',
			expect.anything()
		);
	});

	it('asks the provider to retry when the message could not be stored', async () => {
		const client = makeClient({ messageError: { code: '08006' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			inboundRequest(validParams, twilioSignature('current-token', validParams))
		);

		expect(response.status).toBe(500);
		expect(client.rpc).not.toHaveBeenCalledWith(
			'record_communication_sms_consent_event_from_reply',
			expect.anything()
		);
	});

	it('records provider-confirmed STOP consent and sends no duplicate reply', async () => {
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const params = { ...validParams, Body: 'Stop', OptOutType: 'STOP' };

		const response = await POST(inboundRequest(params, twilioSignature('current-token', params)));

		expect(response.status).toBe(200);
		expect(await response.text()).toBe('<Response/>');
		expect(client.rpc).toHaveBeenCalledWith('record_communication_sms_consent_event_from_reply', {
			target_organization_id: account.organizationId,
			target_provider_message_id: MESSAGE_SID,
			target_from_number: validParams.From,
			target_event_kind: 'opt_out',
			target_confirmed_by_provider: true
		});
	});

	it('falls back to Twilio default keyword matching when OptOutType is absent', async () => {
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const params = { ...validParams, Body: 'stop' };

		await POST(inboundRequest(params, twilioSignature('current-token', params)));

		expect(client.rpc).toHaveBeenCalledWith('record_communication_sms_consent_event_from_reply', {
			target_organization_id: account.organizationId,
			target_provider_message_id: MESSAGE_SID,
			target_from_number: validParams.From,
			target_event_kind: 'opt_out',
			target_confirmed_by_provider: false
		});
	});

	it('records an inbound MMS picture as a pending_import attachment', async () => {
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const params = {
			...validParams,
			NumMedia: '1',
			MediaUrl0: 'https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/ME1',
			MediaContentType0: 'image/jpeg'
		};

		const response = await POST(inboundRequest(params, twilioSignature('current-token', params)));

		expect(response.status).toBe(200);
		expect(client.from).toHaveBeenCalledWith('communication_inbound_attachments');
		expect(client.insert).toHaveBeenCalledWith([
			{
				organization_id: account.organizationId,
				inbound_message_id: 'message-1',
				file_name: 'mms-1.jpg',
				mime_type: 'image/jpeg',
				byte_size: 0,
				status: 'pending_import',
				provider: 'twilio',
				provider_download_token:
					'https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/ME1'
			}
		]);
	});

	it('records no attachment when NumMedia is zero', async () => {
		const client = makeClient({});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		await POST(inboundRequest(validParams, twilioSignature('current-token', validParams)));

		expect(client.from).not.toHaveBeenCalled();
	});

	it('does not fail the webhook when the attachment insert itself fails', async () => {
		const client = makeClient({ attachmentError: { code: '23505' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const params = {
			...validParams,
			NumMedia: '1',
			MediaUrl0: 'https://api.twilio.com/2010-04-01/Accounts/AC1/Messages/MM1/Media/ME1',
			MediaContentType0: 'image/jpeg'
		};

		const response = await POST(inboundRequest(params, twilioSignature('current-token', params)));

		expect(response.status).toBe(200);
	});

	it('retries when consent evidence could not be stored, after the message already was', async () => {
		const client = makeClient({ consentError: { code: '08006' } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);
		const params = { ...validParams, Body: 'HELP', OptOutType: 'HELP' };

		const response = await POST(inboundRequest(params, twilioSignature('current-token', params)));

		expect(response.status).toBe(500);
		expect(client.rpc).toHaveBeenCalledWith(
			'record_communication_sms_inbound_message',
			expect.anything()
		);
	});
});
