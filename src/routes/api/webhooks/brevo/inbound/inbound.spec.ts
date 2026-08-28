import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST } from './+server';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

vi.mock('$env/dynamic/private', () => ({
	env: { BREVO_INBOUND_WEBHOOK_TOKEN: 'inbound-webhook-token' }
}));
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));

function eventWith(body: unknown, authorization?: string) {
	return {
		request: new Request('https://app.example.com/api/webhooks/brevo/inbound', {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				...(authorization ? { authorization } : {})
			},
			body: typeof body === 'string' ? body : JSON.stringify(body)
		})
	} as Parameters<typeof POST>[0];
}

function itemWith(overrides: Record<string, unknown> = {}) {
	return {
		MessageId: 'provider-message-1',
		From: { Address: 'customer@example.com', Name: 'Customer' },
		To: [{ Address: 'reply-alias@mail.ucrm.example', Name: 'Ridgeway' }],
		Cc: [],
		Subject: 'Re: Your quote',
		RawHtmlBody: '<p>Sounds good.</p>',
		RawTextBody: 'Sounds good.',
		Attachments: [],
		Headers: {},
		...overrides
	};
}

function clientWith(
	options: {
		callback?: { data: { id: string } | null; error: { code?: string } | null };
		rpc?: { data: unknown; error: { message: string } | null };
	} = {}
) {
	const callbackResult = options.callback ?? { data: { id: 'callback-1' }, error: null };
	const rpcResult = options.rpc ?? { data: null, error: null };

	const single = vi.fn().mockResolvedValue(callbackResult);
	const select = vi.fn(() => ({ single }));
	const callbackInsert = vi.fn(() => ({ select }));
	const attachmentInsert = vi.fn().mockResolvedValue({ data: null, error: null });
	const rpc = vi.fn().mockResolvedValue(rpcResult);

	const from = vi.fn((table: string) => {
		if (table === 'communication_provider_callback_events') return { insert: callbackInsert };
		if (table === 'communication_inbound_attachments') return { insert: attachmentInsert };
		throw new Error(`Unexpected table: ${table}`);
	});

	return { from, rpc, callbackInsert, attachmentInsert, single };
}

describe('Brevo inbound callback route', () => {
	beforeEach(() => vi.clearAllMocks());

	it('rejects requests before attempting a privileged write', async () => {
		const response = await POST(eventWith({ items: [itemWith()] }));

		expect(response.status).toBe(401);
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(getOwnerSupabaseClient).not.toHaveBeenCalled();
	});

	it('rejects an invalid payload', async () => {
		const response = await POST(eventWith({ items: [] }, 'Bearer inbound-webhook-token'));

		expect(response.status).toBe(422);
	});

	it('resolves a message and imports its attachments', async () => {
		const client = clientWith({
			rpc: {
				data: { id: 'message-1', organization_id: 'org-1' },
				error: null
			}
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(
			eventWith(
				{
					items: [
						itemWith({
							Attachments: [
								{
									Name: 'estimate.pdf',
									ContentType: 'application/pdf',
									ContentLength: 1024,
									DownloadToken: 'token-1'
								},
								{
									Name: 'invoice.exe',
									ContentType: 'application/octet-stream',
									ContentLength: 1024,
									DownloadToken: 'token-2'
								}
							]
						})
					]
				},
				'Bearer inbound-webhook-token'
			)
		);

		expect(response.status).toBe(200);
		expect(client.rpc).toHaveBeenCalledWith(
			'record_communication_inbound_message',
			expect.objectContaining({
				target_provider_message_id: 'provider-message-1',
				target_sender_email: 'customer@example.com',
				target_message_kind: 'reply'
			})
		);
		expect(client.attachmentInsert).toHaveBeenCalledWith([
			expect.objectContaining({
				organization_id: 'org-1',
				inbound_message_id: 'message-1',
				file_name: 'estimate.pdf',
				status: 'pending_import',
				provider_download_token: 'token-1'
			}),
			expect.objectContaining({
				file_name: 'invoice.exe',
				status: 'blocked_type',
				provider_download_token: null
			})
		]);
		expect(await response.json()).toEqual({ accepted: true });
	});

	it('blocks every attachment on a message once their combined size exceeds the total limit', async () => {
		const client = clientWith({
			rpc: { data: { id: 'message-1', organization_id: 'org-1' }, error: null }
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		await POST(
			eventWith(
				{
					items: [
						itemWith({
							Attachments: [
								{
									Name: 'huge.pdf',
									ContentType: 'application/pdf',
									ContentLength: 21 * 1024 * 1024,
									DownloadToken: 'token-1'
								}
							]
						})
					]
				},
				'Bearer inbound-webhook-token'
			)
		);

		expect(client.attachmentInsert).toHaveBeenCalledWith([
			expect.objectContaining({ status: 'blocked_size', provider_download_token: null })
		]);
	});

	it('classifies an auto-responder reply and still records it, suppressed', async () => {
		const client = clientWith({
			rpc: { data: { id: 'message-1', organization_id: 'org-1' }, error: null }
		});
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		await POST(
			eventWith(
				{ items: [itemWith({ Headers: { 'Auto-Submitted': 'auto-replied' } })] },
				'Bearer inbound-webhook-token'
			)
		);

		expect(client.rpc).toHaveBeenCalledWith(
			'record_communication_inbound_message',
			expect.objectContaining({ target_message_kind: 'auto_response' })
		);
	});

	it('skips resolution once the callback event was already recorded', async () => {
		const client = clientWith({ callback: { data: null, error: { code: '23505' } } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		const response = await POST(eventWith({ items: [itemWith()] }, 'Bearer inbound-webhook-token'));

		expect(response.status).toBe(200);
		expect(client.rpc).not.toHaveBeenCalled();
	});

	it('does not insert attachments when resolution finds no matching organization', async () => {
		const client = clientWith({ rpc: { data: null, error: null } });
		vi.mocked(getOwnerSupabaseClient).mockReturnValue(client as never);

		await POST(
			eventWith(
				{
					items: [
						itemWith({
							Attachments: [
								{
									Name: 'estimate.pdf',
									ContentType: 'application/pdf',
									ContentLength: 1024,
									DownloadToken: 'token-1'
								}
							]
						})
					]
				},
				'Bearer inbound-webhook-token'
			)
		);

		expect(client.attachmentInsert).not.toHaveBeenCalled();
	});
});
