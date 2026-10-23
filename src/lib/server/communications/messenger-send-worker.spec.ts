import { describe, expect, it, vi } from 'vitest';

vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: () => ({}) }));
vi.mock('./messenger-connections', () => ({ loadMessengerPageToken: vi.fn() }));
vi.mock('$env/dynamic/private', () => ({ env: {} }));

const { MessengerGraphError } = await import('./messenger-graph');
const { messengerSendFailure, processClaimedMessenger } = await import('./messenger-send-worker');

const claim = {
	outbox_event_id: 'ob-1',
	delivery_intent_id: 'intent-1',
	organization_id: 'org-1',
	connection_id: 'conn-1',
	page_id: '9001',
	psid: '7001',
	claim_token: 'claim-1',
	attempt_number: 1,
	body: 'On my way'
};

function fakeClient(claimed: unknown[] = [claim]) {
	const rpc = vi.fn(async (name: string, _args?: Record<string, unknown>) => {
		if (name === 'claim_communication_messenger_outbox_event')
			return { data: claimed, error: null };
		return { data: [{}], error: null };
	});
	return { rpc };
}

function finalizeArgs(client: ReturnType<typeof fakeClient>) {
	return client.rpc.mock.calls.find(
		([name]) => name === 'finalize_communication_messenger_outbox_event'
	)?.[1];
}

describe('processClaimedMessenger', () => {
	it('sends the claimed reply with its intent ID as metadata and records Meta’s message ID', async () => {
		const client = fakeClient();
		const send = vi.fn(async () => ({ messageId: 'm_1' }));
		const result = await processClaimedMessenger({
			client,
			send,
			loadPageToken: async () => 'page-key'
		});

		expect(result).toEqual({ status: 'submitted', intentId: 'intent-1' });
		expect(send).toHaveBeenCalledWith({
			pageId: '9001',
			pageToken: 'page-key',
			psid: '7001',
			text: 'On my way',
			metadata: 'intent-1'
		});
		expect(finalizeArgs(client)).toMatchObject({
			target_outbox_event_id: 'ob-1',
			target_claim_token: 'claim-1',
			target_outcome: 'submitted',
			target_provider_message_id: 'm_1'
		});
	});

	it('is idle when nothing is waiting', async () => {
		const client = fakeClient([]);
		expect(await processClaimedMessenger({ client, send: vi.fn() })).toEqual({ status: 'idle' });
	});

	it('retries without contacting Meta when the Page key cannot be read', async () => {
		const client = fakeClient();
		const send = vi.fn();
		const result = await processClaimedMessenger({ client, send, loadPageToken: async () => null });

		expect(send).not.toHaveBeenCalled();
		expect(result.status).toBe('retry');
		expect(finalizeArgs(client)).toMatchObject({
			target_outcome: 'retry',
			target_failure_code: 'messenger_page_key_unavailable'
		});
	});

	it('passes Meta’s refusal on as the reason staff read', async () => {
		const client = fakeClient();
		const send = vi.fn(async () => {
			throw new MessengerGraphError('Invalid OAuth access token', 'token_invalid', 190);
		});
		const result = await processClaimedMessenger({
			client,
			send,
			loadPageToken: async () => 'key'
		});

		expect(result.status).toBe('cancelled');
		expect(finalizeArgs(client)).toMatchObject({ target_failure_code: 'token_invalid' });
	});
});

describe('messengerSendFailure', () => {
	it.each([
		[new MessengerGraphError('x', 'unavailable', null, new Error('timeout')), 'submission_unknown'],
		[new Error('boom'), 'submission_unknown'],
		[new MessengerGraphError('x', 'unavailable', 2), 'retry'],
		[new MessengerGraphError('x', 'permission_missing', 10), 'cancelled'],
		[new MessengerGraphError('Outside window', 'rejected', 10, null, 2018278), 'cancelled']
	])('%s → %s', (error, outcome) => {
		expect(messengerSendFailure(error).outcome).toBe(outcome);
	});
});
