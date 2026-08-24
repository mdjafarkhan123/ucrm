import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// Signing from the customer's own link. What these tests defend: the bytes are checked before they are
// stored, an image that nothing ends up pointing at is cleaned up, and asking for changes is never a
// place to sign anything.

const rpc = vi.fn();
const from = vi.fn();
vi.mock('$lib/server/db/owner-supabase', () => ({
	getOwnerSupabaseClient: () => ({ rpc, from })
}));

const putObject = vi.fn(() => Promise.resolve());
const deleteObject = vi.fn(() => Promise.resolve());
vi.mock('$lib/server/storage/r2', async () => {
	const actual =
		await vi.importActual<typeof import('$lib/server/storage/r2')>('$lib/server/storage/r2');
	return { ...actual, putObject, deleteObject };
});

const { POST: approve } = await import('./approve/+server');
const { POST: requestChanges } = await import('./changes/+server');

const token = 'c'.repeat(43);
const tokenHash = `\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`;

// A real one-pixel PNG, magic bytes and all.
const PNG =
	'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const allowed = { data: [{ allowed: true, retry_after_seconds: 0 }], error: null };

function event(body: unknown) {
	return {
		params: { token },
		getClientAddress: () => '198.51.100.7',
		request: {
			text: async () => JSON.stringify(body),
			headers: new Headers({ 'user-agent': 'Mozilla/5.0 (iPhone)' })
		}
	} as unknown as Parameters<typeof approve>[0] & Parameters<typeof requestChanges>[0];
}

function commandCall() {
	return rpc.mock.calls.find(([name]) => name === 'submit_quote_customer_decision');
}

function answered(data: Record<string, unknown>) {
	rpc.mockImplementation((name: string) => {
		if (name === 'check_rate_limit') return Promise.resolve(allowed);
		return Promise.resolve({ data, error: null });
	});
}

beforeEach(() => {
	vi.clearAllMocks();
	answered({ quote_id: 'quote-1', status: 'approved', signed: true, already_answered: false });
	from.mockReturnValue({
		select: () => ({
			eq: () => ({
				maybeSingle: async () => ({
					data: { organization_id: 'org-1', quote_id: 'quote-1' },
					error: null
				})
			})
		})
	});
});

describe('a customer signing their approval', () => {
	it('stores the drawing and hands the command its key, never its bytes', async () => {
		const response = await approve(
			event({ signature: { name: 'Dana Reed', method: 'drawn', image: PNG } })
		);

		expect(response.status).toBe(200);
		expect(putObject).toHaveBeenCalledTimes(1);

		const [key] = putObject.mock.calls[0] as unknown as [string];
		expect(key).toContain('org-1/quote-signatures/quote-1/');

		const [, args] = commandCall() ?? [];
		expect(args.signature_name).toBe('Dana Reed');
		expect(args.signature_method).toBe('drawn');
		expect(args.signature_object_key).toBe(key);
		expect(args.signature_byte_size).toBeGreaterThan(0);
		expect(JSON.stringify(args)).not.toContain('base64');
	});

	it('takes a typed name with nothing to store', async () => {
		await approve(event({ signature: { name: 'Dana Reed', method: 'typed' } }));

		expect(putObject).not.toHaveBeenCalled();
		const [, args] = commandCall() ?? [];
		expect(args.signature_method).toBe('typed');
		expect(args.signature_object_key).toBeUndefined();
	});

	it('still approves with nothing signed at all', async () => {
		const response = await approve(event({}));

		expect(response.status).toBe(200);
		const [, args] = commandCall() ?? [];
		expect(args.signature_name).toBeUndefined();
	});

	it('refuses something that only claims to be a PNG, before storing anything', async () => {
		const response = await approve(
			event({
				signature: {
					name: 'Dana Reed',
					method: 'drawn',
					// Correct prefix, correct alphabet, not a PNG.
					image: 'data:image/png;base64,QUJDREVGR0hJSktMTU5PUFFSU1Q='
				}
			})
		);

		expect(response.status).toBe(422);
		expect(putObject).not.toHaveBeenCalled();
		expect(commandCall()).toBeUndefined();
	});

	it('refuses a drawing with nobody typed beside it', async () => {
		const response = await approve(event({ signature: { name: '', method: 'drawn', image: PNG } }));

		expect(response.status).toBe(422);
		expect(commandCall()).toBeUndefined();
	});

	it('refuses a typed signature that arrives with a picture', async () => {
		const response = await approve(
			event({ signature: { name: 'Dana Reed', method: 'typed', image: PNG } })
		);

		expect(response.status).toBe(422);
		expect(putObject).not.toHaveBeenCalled();
	});

	it('throws away the picture when the answer was already given', async () => {
		answered({ quote_id: 'quote-1', status: 'approved', already_answered: true });

		await approve(event({ signature: { name: 'Dana Reed', method: 'drawn', image: PNG } }));

		expect(deleteObject).toHaveBeenCalledTimes(1);
	});

	it('throws away the picture when the link turns out to be dead', async () => {
		rpc.mockImplementation((name: string) => {
			if (name === 'check_rate_limit') return Promise.resolve(allowed);
			return Promise.resolve({ data: null, error: null });
		});

		const response = await approve(
			event({ signature: { name: 'Dana Reed', method: 'drawn', image: PNG } })
		);

		expect(response.status).toBe(410);
		expect(deleteObject).toHaveBeenCalledTimes(1);
	});

	it('throws away the picture when the quote has since been answered', async () => {
		rpc.mockImplementation((name: string) => {
			if (name === 'check_rate_limit') return Promise.resolve(allowed);
			return Promise.resolve({
				data: null,
				error: { code: 'P0409', message: 'This quote has already been answered.' }
			});
		});

		const response = await approve(
			event({ signature: { name: 'Dana Reed', method: 'drawn', image: PNG } })
		);

		expect(response.status).toBe(409);
		expect(deleteObject).toHaveBeenCalledTimes(1);
	});

	it('sends the hash of the token to the link lookup, never the token', async () => {
		await approve(event({ signature: { name: 'Dana Reed', method: 'drawn', image: PNG } }));

		expect(from).toHaveBeenCalledWith('quote_access_links');
		const [, args] = commandCall() ?? [];
		expect(args.supplied_token_hash).toBe(tokenHash);
	});
});

describe('asking for changes', () => {
	it('has nowhere to sign', async () => {
		const response = await requestChanges(
			event({
				note: 'Please drop the second coat.',
				signature: { name: 'Dana Reed', method: 'typed' }
			})
		);

		expect(response.status).toBe(422);
		expect(commandCall()).toBeUndefined();
	});
});
