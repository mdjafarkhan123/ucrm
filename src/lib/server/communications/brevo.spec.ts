import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
	OperationalEmailSubmissionError,
	createBrevoDomain,
	createBrevoInboundWebhook,
	deleteBrevoDomain,
	deleteBrevoWebhook,
	getBrevoDomain,
	listBrevoInboundWebhooks,
	listBrevoSenders,
	sendOperationalEmail
} from './brevo';
import { getBrevoInboundWebhookToken, getEmailEnv } from '$lib/server/email/env';

vi.mock('$lib/server/email/env', () => ({
	getEmailEnv: vi.fn(),
	getBrevoInboundWebhookToken: vi.fn()
}));

const message = {
	from: { email: 'service@ridgeway.example', name: 'Ridgeway' },
	to: { email: 'customer@example.com', name: 'Taylor' },
	subject: 'Your job update',
	htmlContent: '<p>Your job is scheduled.</p>',
	textContent: 'Your job is scheduled.',
	intentId: 'intent-42'
};

describe('Brevo operational email adapter', () => {
	beforeEach(() => {
		vi.stubGlobal('fetch', vi.fn());
		vi.mocked(getEmailEnv).mockReturnValue({
			BREVO_API_KEY: 'server-only-api-key',
			SYSTEM_FROM_EMAIL: 'system@ridgeway.example'
		});
	});

	afterEach(() => vi.unstubAllGlobals());

	it('submits the exact intent once and keeps its UCRM tag', async () => {
		vi.mocked(fetch).mockResolvedValue(
			new Response(JSON.stringify({ messageId: 'provider-message-42' }), { status: 201 })
		);

		await expect(sendOperationalEmail(message)).resolves.toEqual({
			messageId: 'provider-message-42'
		});

		expect(fetch).toHaveBeenCalledWith('https://api.brevo.com/v3/smtp/email', {
			method: 'POST',
			headers: expect.objectContaining({
				'api-key': 'server-only-api-key',
				'content-type': 'application/json'
			}),
			body: JSON.stringify({
				sender: message.from,
				to: [message.to],
				subject: message.subject,
				htmlContent: message.htmlContent,
				textContent: message.textContent,
				headers: { idempotencyKey: 'intent-42' },
				tags: ['ucrm:email:intent-42']
			}),
			signal: expect.any(AbortSignal)
		});
	});

	it('includes Brevo attachment field only when attachments are present', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ messageId: 'provider-message-42' }), { status: 201 })
		);

		await sendOperationalEmail({
			...message,
			attachments: [{ name: 'quote.pdf', content: 'YWJjZA==' }]
		});

		const [, init] = vi.mocked(fetch).mock.calls[0];
		expect(JSON.parse(init!.body as string)).toMatchObject({
			attachment: [{ name: 'quote.pdf', content: 'YWJjZA==' }]
		});

		vi.mocked(fetch).mockClear();
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ messageId: 'provider-message-43' }), { status: 201 })
		);
		await sendOperationalEmail({ ...message, attachments: [] });
		const [, initEmpty] = vi.mocked(fetch).mock.calls[0];
		expect(JSON.parse(initEmpty!.body as string)).not.toHaveProperty('attachment');
	});

	it('classifies a provider rejection that is safe to retry', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response('provider unavailable', { status: 503 }));

		await expect(sendOperationalEmail(message)).rejects.toMatchObject({
			outcome: 'retry',
			code: 'brevo_http_503'
		});
	});

	it('quarantines network ambiguity and an accepted response without an identifier', async () => {
		vi.mocked(fetch).mockRejectedValueOnce(new TypeError('connection closed'));

		await expect(sendOperationalEmail(message)).rejects.toMatchObject({
			outcome: 'submission_unknown',
			code: 'brevo_network_unknown'
		});

		vi.mocked(fetch).mockResolvedValueOnce(new Response('{}', { status: 201 }));

		await expect(sendOperationalEmail(message)).rejects.toBeInstanceOf(
			OperationalEmailSubmissionError
		);
	});

	it('does not retry a permanent provider rejection', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response('invalid sender', { status: 400 }));

		await expect(sendOperationalEmail(message)).rejects.toMatchObject({
			outcome: 'cancelled',
			code: 'brevo_http_400'
		});
	});

	it('keeps domain management behind the server-only adapter', async () => {
		vi.mocked(fetch)
			.mockResolvedValueOnce(
				new Response(
					JSON.stringify({ id: '6a8bb41bb9734c854105f2f5', domain_name: 'mail.ridgeway.example' }),
					{
						status: 200
					}
				)
			)
			.mockResolvedValueOnce(
				new Response(
					JSON.stringify({
						domain: 'mail.ridgeway.example',
						verified: false,
						authenticated: false,
						dns_records: []
					}),
					{ status: 200 }
				)
			);

		await expect(createBrevoDomain('mail.ridgeway.example')).resolves.toMatchObject({
			id: '6a8bb41bb9734c854105f2f5'
		});
		await expect(getBrevoDomain('mail.ridgeway.example')).resolves.toMatchObject({
			domain: 'mail.ridgeway.example'
		});
		expect(fetch).toHaveBeenNthCalledWith(
			1,
			'https://api.brevo.com/v3/senders/domains',
			expect.objectContaining({
				method: 'POST',
				headers: expect.objectContaining({ 'api-key': 'server-only-api-key' })
			})
		);
	});

	it('preserves a not-found provider result for reconciliation', async () => {
		vi.mocked(fetch).mockResolvedValue(new Response('{}', { status: 404 }));

		await expect(getBrevoDomain('missing.example')).rejects.toMatchObject({
			status: 404,
			code: 'brevo_http_404'
		});
	});

	it('normalizes Brevo named DNS records and ignores nullable record slots', async () => {
		vi.mocked(fetch).mockResolvedValue(
			new Response(
				JSON.stringify({
					domain: 'mail.ridgeway.example',
					verified: false,
					authenticated: false,
					dns_records: {
						dkim_record: null,
						dkim1Record: {
							type: 'CNAME',
							host_name: 'brevo1._domainkey',
							value: 'b1.mail-ridgeway-example.dkim.brevo.com',
							status: false
						},
						brevo_code: {
							type: 'TXT',
							host_name: 'mail',
							value: 'brevo-code:example',
							status: false
						}
					}
				}),
				{ status: 200 }
			)
		);

		await expect(getBrevoDomain('mail.ridgeway.example')).resolves.toMatchObject({
			dns_records: [
				{ type: 'CNAME', host_name: 'brevo1._domainkey' },
				{ type: 'TXT', host_name: 'mail' }
			]
		});
	});

	it('lists only the provider senders for the requested domain', async () => {
		vi.mocked(fetch).mockResolvedValue(
			new Response(
				JSON.stringify({
					senders: [{ id: 81, email: 'alex@mail.ridgeway.example', name: 'Alex', active: true }]
				}),
				{ status: 200 }
			)
		);

		await expect(listBrevoSenders('mail.ridgeway.example')).resolves.toHaveLength(1);
		expect(fetch).toHaveBeenCalledWith(
			'https://api.brevo.com/v3/senders?domain=mail.ridgeway.example',
			expect.objectContaining({
				headers: expect.objectContaining({ 'api-key': 'server-only-api-key' })
			})
		);
	});

	it('uses Brevo domain deletion without accepting an unconfirmed response', async () => {
		vi.mocked(fetch).mockResolvedValue(new Response(null, { status: 204 }));

		await expect(deleteBrevoDomain('mail.ridgeway.example')).resolves.toBeUndefined();
		expect(fetch).toHaveBeenCalledWith(
			'https://api.brevo.com/v3/senders/domains/mail.ridgeway.example',
			expect.objectContaining({ method: 'DELETE' })
		);
	});
});

describe('Brevo inbound-webhook management adapter', () => {
	beforeEach(() => {
		vi.stubGlobal('fetch', vi.fn());
		vi.mocked(getEmailEnv).mockReturnValue({
			BREVO_API_KEY: 'server-only-api-key',
			SYSTEM_FROM_EMAIL: 'system@ridgeway.example'
		});
		vi.mocked(getBrevoInboundWebhookToken).mockReturnValue('inbound-bearer-secret');
	});

	afterEach(() => vi.unstubAllGlobals());

	it('creates the inbound webhook with bearer auth, not a token in the URL', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response(JSON.stringify({ id: 2148900 }), { status: 201 }));

		await expect(
			createBrevoInboundWebhook({
				url: 'https://app.upliftcontractor.com/api/webhooks/brevo/inbound',
				domain: 'reply.test.upliftcontractor.com',
				description: 'UCRM inbound replies for reply.test.upliftcontractor.com'
			})
		).resolves.toMatchObject({ id: 2148900, type: 'inbound' });

		const [url, init] = vi.mocked(fetch).mock.calls[0];
		expect(url).toBe('https://api.brevo.com/v3/webhooks');
		const body = JSON.parse(init!.body as string);
		expect(body).toMatchObject({
			type: 'inbound',
			url: 'https://app.upliftcontractor.com/api/webhooks/brevo/inbound',
			domain: 'reply.test.upliftcontractor.com',
			events: ['inboundEmailProcessed'],
			auth: { type: 'bearer', token: 'inbound-bearer-secret' }
		});
		// The secret must never be smuggled into the callback URL, only into the bearer auth field.
		expect(body.url).not.toContain('inbound-bearer-secret');
	});

	it('lists inbound webhooks whether Brevo wraps them or returns a bare array', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(
				JSON.stringify({
					webhooks: [
						{ id: 2148900, url: 'https://app.example/api/webhooks/brevo/inbound', type: 'inbound', domain: 'reply.test.upliftcontractor.com', events: ['inboundEmailProcessed'] }
					]
				}),
				{ status: 200 }
			)
		);

		await expect(listBrevoInboundWebhooks()).resolves.toEqual([
			{
				id: 2148900,
				url: 'https://app.example/api/webhooks/brevo/inbound',
				type: 'inbound',
				domain: 'reply.test.upliftcontractor.com',
				events: ['inboundEmailProcessed']
			}
		]);
		expect(fetch).toHaveBeenCalledWith(
			'https://api.brevo.com/v3/webhooks?type=inbound',
			expect.objectContaining({ headers: expect.objectContaining({ 'api-key': 'server-only-api-key' }) })
		);
	});

	it('treats a missing webhook as already deleted so cleanup is retryable', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response('not found', { status: 404 }));

		await expect(deleteBrevoWebhook('2148900')).resolves.toBeUndefined();
		expect(fetch).toHaveBeenCalledWith(
			'https://api.brevo.com/v3/webhooks/2148900',
			expect.objectContaining({ method: 'DELETE' })
		);
	});

	it('propagates a non-404 delete failure so it can be retried, not swallowed', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response('server error', { status: 500 }));

		await expect(deleteBrevoWebhook('2148900')).rejects.toMatchObject({ code: 'brevo_http_500' });
	});
});
