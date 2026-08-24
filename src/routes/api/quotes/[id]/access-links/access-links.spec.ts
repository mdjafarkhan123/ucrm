import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as readLinks, POST as issueLink } from './+server';
import { DELETE as revokeLink } from './[linkId]/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const quoteId = '00000000-0000-4000-8000-000000000091';
const linkId = '00000000-0000-4000-8000-0000000000a1';

function context(permissions: Record<string, boolean>) {
	return {
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features: { 'core.quotes': true } }
	} as never;
}

function linkEvent(
	method: string,
	rpcResult: unknown = { data: { quote_access_link_id: linkId }, error: null },
	body?: unknown
) {
	const rpc = vi.fn(() => Promise.resolve(rpcResult));
	return {
		params: { id: quoteId, linkId },
		url: new URL(`https://app.example.com/api/quotes/${quoteId}/access-links`),
		request: new Request(`https://app.example.com/api/quotes/${quoteId}/access-links`, {
			method,
			body: body === undefined ? undefined : JSON.stringify(body)
		}),
		locals: { supabase: { rpc } },
		__rpc: rpc
		// Three routes share this fake event and each names its own generated route id, so the shape is
		// handed over untyped rather than pretending to be one of them.
	} as unknown as Parameters<typeof issueLink>[0] &
		Parameters<typeof readLinks>[0] &
		Parameters<typeof revokeLink>[0] & { __rpc: ReturnType<typeof vi.fn> };
}

describe('issuing a customer link', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.send': true }));
	});

	it('asks for the send permission', async () => {
		await issueLink(linkEvent('POST'));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.send');
	});

	it('sends the database a hash and never the token', async () => {
		const event = linkEvent('POST');
		const response = await issueLink(event);
		const answer = (await response.json()) as { url: string };

		const [, args] = event.__rpc.mock.calls[0] as [string, { supplied_token_hash: string }];
		const token = answer.url.split('/q/')[1];

		expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
		expect(args.supplied_token_hash).toBe(
			`\\x${createHash('sha256').update(token, 'utf8').digest('hex')}`
		);
		expect(JSON.stringify(args)).not.toContain(token);
	});

	it('hands back a full URL on this origin, once', async () => {
		const response = await issueLink(linkEvent('POST'));
		const answer = (await response.json()) as { url: string };
		expect(answer.url.startsWith('https://app.example.com/q/')).toBe(true);
		expect(response.headers.get('cache-control')).toBe('no-store');
	});

	it('gives every request a different token', async () => {
		const first = await (await issueLink(linkEvent('POST'))).json();
		const second = await (await issueLink(linkEvent('POST'))).json();
		expect(first.url).not.toBe(second.url);
	});

	it('refuses a body that tries to name its own recipient', async () => {
		const response = await issueLink(linkEvent('POST', undefined, { email: 'someone@else.com' }));
		expect(response.status).toBe(422);
	});

	it('turns a refusal to share into the answer a person should read', async () => {
		const response = await issueLink(
			linkEvent('POST', {
				data: null,
				error: {
					code: '23514',
					message: 'Add an email address to this client before creating a customer link.'
				}
			})
		);
		expect(response.status).toBe(422);
	});

	it('answers a quote it may not touch the same way as one that does not exist', async () => {
		const response = await issueLink(
			linkEvent('POST', { data: null, error: { code: '42501', message: 'nope' } })
		);
		expect(response.status).toBe(404);
	});
});

describe('reading and revoking links', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mockedRequire.mockResolvedValue(context({ 'quotes.view': true, 'quotes.send': true }));
	});

	it('reads through the function, never the table', async () => {
		const event = linkEvent('GET', { data: [], error: null });
		await readLinks(event);
		expect(event.__rpc).toHaveBeenCalledWith('quote_access_link_state', {
			target_quote_id: quoteId
		});
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.view');
	});

	it('needs the send permission to turn a link off', async () => {
		await revokeLink(linkEvent('DELETE'));
		expect(mockedRequire).toHaveBeenCalledWith(expect.anything(), 'quotes.send');
	});

	it('does not go to the database for an id that is not an id', async () => {
		const event = linkEvent('DELETE');
		(event as unknown as { params: { linkId: string } }).params.linkId = 'not-a-link';
		const response = await revokeLink(event);
		expect(response.status).toBe(404);
		expect(event.__rpc).not.toHaveBeenCalled();
	});
});
