import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { submitTwilioSms, TwilioSmsSubmissionError, type SubmitTwilioSmsInput } from './twilio';

const input: SubmitTwilioSmsInput = {
	subaccountSid: 'AC00000000000000000000000000000001',
	messagingServiceSid: 'MG00000000000000000000000000000001',
	apiKeySid: 'SK00000000000000000000000000000001',
	apiKeySecret: 'super-secret',
	from: '+15005550006',
	to: '+15551234567',
	body: 'Your job is confirmed for tomorrow at 9am.',
	deliveryIntentId: '11111111-1111-1111-1111-111111111111'
};

const acceptedSid = 'SM00000000000000000000000000000abc';

describe('submitTwilioSms', () => {
	beforeEach(() => vi.stubGlobal('fetch', vi.fn()));
	afterEach(() => vi.unstubAllGlobals());

	it('returns the Message SID when Twilio accepts the message', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ sid: acceptedSid, status: 'queued' }), { status: 201 })
		);

		await expect(submitTwilioSms(input)).resolves.toEqual({ providerMessageId: acceptedSid });

		const [url, init] = vi.mocked(fetch).mock.calls[0];
		expect(String(url)).toContain(`/2010-04-01/Accounts/${input.subaccountSid}/Messages.json`);
		expect(init).toMatchObject({ method: 'POST', signal: expect.any(AbortSignal) });
		// The Restricted key SID authenticates the send; the secret is never placed in the URL.
		expect((init?.headers as Record<string, string>).authorization).toContain(
			Buffer.from(`${input.apiKeySid}:${input.apiKeySecret}`).toString('base64')
		);
		expect(String(url)).not.toContain(input.apiKeySecret);
		const bodyParams = new URLSearchParams(init?.body as string);
		expect(bodyParams.get('To')).toBe(input.to);
		expect(bodyParams.get('From')).toBe(input.from);
		expect(bodyParams.get('MessagingServiceSid')).toBe(input.messagingServiceSid);
		expect(bodyParams.get('Body')).toBe(input.body);
	});

	it('classifies a 429 rate limit as a retryable pre-submission failure', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ code: 20429 }), { status: 429 })
		);

		await expect(submitTwilioSms(input)).rejects.toMatchObject({
			outcome: 'retry',
			code: 'twilio_http_429',
			providerCode: '20429'
		});
	});

	it('classifies a 5xx as a retryable pre-submission failure', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response('bad gateway', { status: 502 }));

		await expect(submitTwilioSms(input)).rejects.toMatchObject({
			outcome: 'retry',
			code: 'twilio_http_502'
		});
	});

	it('classifies a definite 4xx (opted-out) as cancelled and keeps the provider code', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(
			new Response(JSON.stringify({ code: 21610, message: 'unsubscribed recipient' }), {
				status: 400
			})
		);

		await expect(submitTwilioSms(input)).rejects.toMatchObject({
			outcome: 'cancelled',
			code: 'twilio_http_400',
			providerCode: '21610'
		});
	});

	it('treats a network/timeout failure as an unknown submission', async () => {
		vi.mocked(fetch).mockRejectedValueOnce(new Error('aborted'));

		await expect(submitTwilioSms(input)).rejects.toMatchObject({
			outcome: 'submission_unknown',
			code: 'twilio_network_unknown'
		});
	});

	it('treats a 2xx without a usable Message SID as an unknown submission', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response(JSON.stringify({ status: 'queued' }), { status: 201 }));

		await expect(submitTwilioSms(input)).rejects.toMatchObject({
			outcome: 'submission_unknown',
			code: 'twilio_missing_message_sid'
		});
	});

	it('is a TwilioSmsSubmissionError for every provider failure', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(new Response('nope', { status: 401 }));
		await expect(submitTwilioSms(input)).rejects.toBeInstanceOf(TwilioSmsSubmissionError);
	});
});
