import { createHmac } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const upsert = vi.fn();
const drain = vi.fn();

vi.mock('$env/dynamic/private', () => ({
	env: { META_APP_SECRET: 'app-secret', MESSENGER_VERIFY_TOKEN: 'verify-me' }
}));
vi.mock('$lib/server/db/owner-supabase', () => ({
	getOwnerSupabaseClient: () => ({
		from: () => ({ upsert: (...args: unknown[]) => upsert(...args) })
	})
}));
vi.mock('$lib/server/communications/messenger-inbound-worker', () => ({
	drainMessengerWebhookEvents: (...args: unknown[]) => drain(...args)
}));

const { GET, POST } = await import('./+server');

const BODY = '{"object":"page","entry":[{"id":"9001","messaging":[]}]}';
const sign = (body: string) =>
	`sha256=${createHmac('sha256', 'app-secret').update(body).digest('hex')}`;

function post(body: string, signature: string | null = sign(body)) {
	const headers: Record<string, string> = { 'content-type': 'application/json' };
	if (signature) headers['x-hub-signature-256'] = signature;
	const request = new Request('https://app.example/api/webhooks/messenger', {
		method: 'POST',
		headers,
		body
	});
	return POST({ request } as Parameters<typeof POST>[0]);
}

beforeEach(() => {
	upsert.mockReset().mockResolvedValue({ error: null });
	drain.mockReset().mockResolvedValue({ claimed: 1, processed: 1, failed: 0 });
});

describe('GET /api/webhooks/messenger', () => {
	const get = (token: string) =>
		GET({
			url: new URL(
				`https://app.example/api/webhooks/messenger?hub.mode=subscribe&hub.verify_token=${token}&hub.challenge=42`
			)
		} as Parameters<typeof GET>[0]);

	it('answers Meta’s handshake with the challenge', async () => {
		const response = await get('verify-me');
		expect(response.status).toBe(200);
		expect(await response.text()).toBe('42');
	});

	it('refuses a wrong verify token', async () => {
		expect((await get('guess')).status).toBe(403);
	});
});

describe('POST /api/webhooks/messenger', () => {
	it('saves a signed delivery by its body hash, answers 200 and wakes processing', async () => {
		const response = await post(BODY);
		expect(response.status).toBe(200);
		expect(upsert).toHaveBeenCalledWith(
			{ body_sha256: expect.stringMatching(/^\\x[0-9a-f]{64}$/), payload: JSON.parse(BODY) },
			{ onConflict: 'body_sha256', ignoreDuplicates: true }
		);
		expect(drain).toHaveBeenCalledOnce();
	});

	it('saves a repeated delivery under the same hash, so it stays one row', async () => {
		await post(BODY);
		await post(BODY);
		const [first, second] = upsert.mock.calls.map(([row]) => row.body_sha256);
		expect(first).toBe(second);
	});

	it('refuses an unsigned or forged delivery without saving it', async () => {
		expect((await post(BODY, null)).status).toBe(403);
		expect((await post(BODY, sign(BODY + 'x'))).status).toBe(403);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('refuses a body over 1 MiB before checking anything else', async () => {
		const response = await post('x'.repeat(1024 * 1024 + 1));
		expect(response.status).toBe(413);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('asks Meta to retry when the delivery could not be saved', async () => {
		upsert.mockResolvedValue({ error: { code: '08006' } });
		const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
		const response = await post(BODY);
		logged.mockRestore();
		expect(response.status).toBe(500);
		expect(drain).not.toHaveBeenCalled();
	});

	it('still answers 200 when instant processing fails, leaving it for the cron', async () => {
		drain.mockRejectedValue(new Error('worker down'));
		const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
		const response = await post(BODY);
		await Promise.resolve();
		logged.mockRestore();
		expect(response.status).toBe(200);
	});
});
