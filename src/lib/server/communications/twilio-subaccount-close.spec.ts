import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { closeTwilioSubaccount, TwilioProvisioningError, type TwilioPlatformEnv } from './twilio';

const platform: TwilioPlatformEnv = {
	TWILIO_ACCOUNT_SID: 'AC00000000000000000000000000000000',
	TWILIO_AUTH_TOKEN: 'master-token',
	TWILIO_PROVISIONING_KEY_SID: 'SK00000000000000000000000000000000',
	TWILIO_PROVISIONING_KEY_SECRET: 'key-secret'
};
const subaccountSid = 'AC00000000000000000000000000000001';
const masterAuth = `Basic ${Buffer.from('AC00000000000000000000000000000000:master-token').toString('base64')}`;

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

describe('closeTwilioSubaccount', () => {
	beforeEach(() => vi.stubGlobal('fetch', vi.fn()));
	afterEach(() => vi.unstubAllGlobals());

	it('closes an active subaccount with the parent credential', async () => {
		vi.mocked(fetch)
			.mockResolvedValueOnce(json({ sid: subaccountSid, status: 'active' }))
			.mockResolvedValueOnce(json({ sid: subaccountSid, status: 'closed' }));

		await closeTwilioSubaccount(subaccountSid, platform);

		const [url, init] = vi.mocked(fetch).mock.calls[1];
		expect(String(url)).toContain(`/2010-04-01/Accounts/${subaccountSid}.json`);
		expect(init).toMatchObject({ method: 'POST' });
		expect((init?.headers as Record<string, string>).authorization).toBe(masterAuth);
		expect(new URLSearchParams(init?.body as string).get('Status')).toBe('closed');
	});

	it('treats an already closed subaccount as done without writing', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(json({ sid: subaccountSid, status: 'closed' }));

		await closeTwilioSubaccount(subaccountSid, platform);

		expect(fetch).toHaveBeenCalledTimes(1);
	});

	it('treats a subaccount Twilio no longer has as done', async () => {
		vi.mocked(fetch).mockResolvedValueOnce(json({ code: 20404 }, 404));

		await expect(closeTwilioSubaccount(subaccountSid, platform)).resolves.toBeUndefined();
		expect(fetch).toHaveBeenCalledTimes(1);
	});

	it('fails retryably when Twilio is down, so the closure sweep tries again', async () => {
		vi.mocked(fetch)
			.mockResolvedValueOnce(json({ sid: subaccountSid, status: 'active' }))
			.mockResolvedValueOnce(json({ code: 20500 }, 503));

		const error = await closeTwilioSubaccount(subaccountSid, platform).catch((caught) => caught);
		expect(error).toBeInstanceOf(TwilioProvisioningError);
		expect(error.retryable).toBe(true);
	});

	it('refuses an id that is not a subaccount SID before calling Twilio', async () => {
		await expect(closeTwilioSubaccount('not-a-sid', platform)).rejects.toBeInstanceOf(
			TwilioProvisioningError
		);
		expect(fetch).not.toHaveBeenCalled();
	});
});
