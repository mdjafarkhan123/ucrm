import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// The one unauthenticated write path in the app. These tests care about two things above all: that a
// dead token is answered exactly like a live one, and that nothing about a customer - their token, their
// message, their address - ever reaches a log line.

const rpc = vi.fn();
vi.mock('$lib/server/db/owner-supabase', () => ({
	getOwnerSupabaseClient: () => ({ rpc })
}));

const { POST: approve } = await import('./approve/+server');
const { POST: requestChanges } = await import('./changes/+server');
const { POST: recordView } = await import('./view/+server');

const token = 'b'.repeat(43);
const tokenHash = `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;

const allowed = { data: [{ allowed: true, retry_after_seconds: 0 }], error: null };

function event(pathToken: string, body: unknown = {}, address = '198.51.100.7') {
	return {
		params: { token: pathToken },
		getClientAddress: () => address,
		request: {
			text: async () => JSON.stringify(body),
			headers: new Headers({ 'user-agent': 'Mozilla/5.0 (iPhone)' })
		}
		// One shape for three routes: SvelteKit types each handler's event to its own path, and this test
		// deliberately hands the same request to all of them.
	} as unknown as Parameters<typeof approve>[0] &
		Parameters<typeof requestChanges>[0] &
		Parameters<typeof recordView>[0];
}

function commandCall() {
	return rpc.mock.calls.find(([name]) => name === 'submit_quote_customer_decision');
}

beforeEach(() => {
	vi.clearAllMocks();
	rpc.mockImplementation((name: string) => {
		if (name === 'check_rate_limit') return Promise.resolve(allowed);
		return Promise.resolve({
			data: { quote_id: 'quote-1', status: 'approved', already_answered: false },
			error: null
		});
	});
});

describe('a customer approving from their link', () => {
	it('sends the hash of the token and never the token', async () => {
		await approve(event(token));

		const [, args] = commandCall() ?? [];
		expect(args.supplied_token_hash).toBe(tokenHash);
		expect(JSON.stringify(args)).not.toContain(token);
	});

	it('records a truncated address and a trimmed user agent, not the caller', async () => {
		await approve(event(token, {}, '198.51.100.7'));

		const [, args] = commandCall() ?? [];
		expect(args.supplied_evidence.ip_prefix).toBe('198.51.100.0');
		expect(args.supplied_evidence.user_agent).toBe('Mozilla/5.0 (iPhone)');
	});

	it('cuts an IPv6 address down without turning it into a different one', async () => {
		await approve(event(token, {}, '2001:db8:85a3:8d3:1319:8a2e:370:7348'));

		const [, args] = commandCall() ?? [];
		expect(args.supplied_evidence.ip_prefix).toBe('2001:db8:85a3:8d3::');
	});

	it('takes an optional note but does not demand one', async () => {
		const response = await approve(event(token, {}));
		expect(response.status).toBe(200);

		const [, args] = commandCall() ?? [];
		expect(args.customer_note).toBeUndefined();
	});

	it('refuses a field nobody asked for rather than ignoring it', async () => {
		const response = await approve(event(token, { note: 'Great', quote_id: 'somebody-elses' }));

		expect(response.status).toBe(422);
		expect(commandCall()).toBeUndefined();
	});

	it('never spends a database call on a token of the wrong shape', async () => {
		const response = await approve(event('not-a-real-token'));

		expect(response.status).toBe(410);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('answers a dead link with the same sentence as an unknown one', async () => {
		rpc.mockImplementation((name: string) =>
			name === 'check_rate_limit'
				? Promise.resolve(allowed)
				: Promise.resolve({ data: null, error: null })
		);

		const response = await approve(event(token));
		const body = await response.json();

		expect(response.status).toBe(410);
		expect(body.error).not.toMatch(/revok|expir|version|organi/i);
	});

	it('passes on the one refusal a person can act on', async () => {
		rpc.mockImplementation((name: string) =>
			name === 'check_rate_limit'
				? Promise.resolve(allowed)
				: Promise.resolve({
						data: null,
						error: { code: 'P0409', message: 'This quote has already been answered.' }
					})
		);

		const response = await approve(event(token));
		expect(response.status).toBe(409);
		expect((await response.json()).error).toBe('This quote has already been answered.');
	});

	it('explains nothing about any other failure', async () => {
		const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
		rpc.mockImplementation((name: string) =>
			name === 'check_rate_limit'
				? Promise.resolve(allowed)
				: Promise.resolve({ data: null, error: { code: '42501', message: 'permission denied' } })
		);

		const response = await approve(event(token));

		expect(response.status).toBe(500);
		expect((await response.json()).error).not.toMatch(/permission/i);
		expect(JSON.stringify(logged.mock.calls)).not.toContain(token);
		logged.mockRestore();
	});

	it('stops when either bucket is full', async () => {
		rpc.mockImplementation((name: string, args: { target_bucket_key: string }) => {
			if (name !== 'check_rate_limit') return Promise.resolve({ data: {}, error: null });
			const full = args.target_bucket_key.includes('_token:');
			return Promise.resolve({
				data: [{ allowed: !full, retry_after_seconds: full ? 90 : 0 }],
				error: null
			});
		});

		const response = await approve(event(token));

		expect(response.status).toBe(429);
		expect(response.headers.get('Retry-After')).toBe('90');
		expect(commandCall()).toBeUndefined();
	});

	it('keeps the answer out of every cache', async () => {
		const response = await approve(event(token));
		expect(response.headers.get('cache-control')).toBe('no-store');
		expect(response.headers.get('referrer-policy')).toBe('no-referrer');
	});
});

describe('a customer asking for changes', () => {
	it('needs to be told what to change', async () => {
		const response = await requestChanges(event(token, {}));

		expect(response.status).toBe(422);
		expect(commandCall()).toBeUndefined();
	});

	it('sends the message and the right outcome', async () => {
		await requestChanges(event(token, { note: 'Can you split the deck into two stages?' }));

		const [, args] = commandCall() ?? [];
		expect(args.new_outcome).toBe('changes_requested');
		expect(args.customer_note).toBe('Can you split the deck into two stages?');
	});
});

describe('recording that the document was seen', () => {
	it('records the view against the hashed token', async () => {
		const response = await recordView(event(token));

		expect(response.status).toBe(200);
		const [, args] = rpc.mock.calls.find(([name]) => name === 'record_quote_link_view') ?? [];
		expect(args.supplied_token_hash).toBe(tokenHash);
	});

	it('answers the same way for a token it never looked up', async () => {
		const response = await recordView(event('nope'));

		expect(response.status).toBe(200);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('does not tell the customer when recording failed', async () => {
		const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
		rpc.mockImplementation((name: string) =>
			name === 'check_rate_limit'
				? Promise.resolve(allowed)
				: Promise.resolve({ data: null, error: { code: '42501' } })
		);

		const response = await recordView(event(token));

		expect(response.status).toBe(200);
		expect(JSON.stringify(logged.mock.calls)).not.toContain(token);
		logged.mockRestore();
	});
});
