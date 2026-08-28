import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// The Website Chat write path is unauthenticated and lives on a stranger's website, so these tests care
// about three things above all: that every rejection is answered identically, that the visitor's raw
// session secret never leaves this process in either direction, and that a retried first message hands
// back a token that still works.

const rpc = vi.fn();
vi.mock('$lib/server/db/owner-supabase', () => ({
	getOwnerSupabaseClient: () => ({ rpc })
}));
vi.mock('$lib/server/env', () => ({ getServerEnv: vi.fn() }));

const { getServerEnv } = await import('$lib/server/env');
const { POST: postFirstMessage } = await import('./sessions/+server');
const { POST: postLaterMessage } = await import('./messages/+server');

const widgetToken = 'e0730f19-a89a-4ab4-a8ae-0d2182e2298d';
const origin = 'https://raad-ltd-demo.com';

const firstMessageBody = {
	idempotency_key: 'visitor-attempt-0001',
	name: 'Priya Sharma',
	phone: '+447700900123',
	message: 'Can you quote a fence?',
	consent_transactional_sms: true,
	attribution: { landing_page: '/fencing' }
};

function firstMessageEvent(body: unknown = firstMessageBody, token = widgetToken, from = origin) {
	return {
		url: new URL(`https://app.example.com/api/webchat/sessions?token=${token}`),
		getClientAddress: () => '198.51.100.7',
		request: new Request('https://app.example.com/api/webchat/sessions', {
			method: 'POST',
			headers: from
				? { origin: from, 'content-type': 'application/json' }
				: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		})
	} as unknown as Parameters<typeof postFirstMessage>[0];
}

function laterMessageEvent(authorization: string, body: unknown = { message: 'Any update?' }) {
	return {
		url: new URL(`https://app.example.com/api/webchat/messages?token=${widgetToken}`),
		getClientAddress: () => '198.51.100.7',
		request: new Request('https://app.example.com/api/webchat/messages', {
			method: 'POST',
			headers: { origin, authorization, 'content-type': 'application/json' },
			body: JSON.stringify(body)
		})
	} as unknown as Parameters<typeof postLaterMessage>[0];
}

function commandArgs(name: string) {
	return rpc.mock.calls.find(([called]) => called === name)?.[1];
}

// A refusal is only safe if the calling page cannot read it: 204, no body, and above all no
// `access-control-allow-origin`, which is what actually stops the host page's JavaScript from telling
// a bad token apart from a stranger's domain.
async function expectUnreadableRefusal(response: Response) {
	expect(response.status).toBe(204);
	expect(response.headers.get('access-control-allow-origin')).toBeNull();
	expect(response.headers.get('cache-control')).toBe('no-store');
	expect(await response.text()).toBe('');
}

beforeEach(() => {
	rpc.mockReset();
	vi.mocked(getServerEnv).mockReturnValue({ SESSION_SECRET: 'test-session-secret' } as never);
});

describe('the first Website Chat message', () => {
	it('answers a bad token, a missing origin, a malformed body and a refusing command identically', async () => {
		rpc.mockResolvedValue({ data: { status: 'refused' }, error: null });

		await expectUnreadableRefusal(
			await postFirstMessage(firstMessageEvent(firstMessageBody, 'nope'))
		);
		await expectUnreadableRefusal(
			await postFirstMessage(firstMessageEvent(firstMessageBody, widgetToken, ''))
		);
		await expectUnreadableRefusal(
			await postFirstMessage(firstMessageEvent({ ...firstMessageBody, name: '' }))
		);
		// One character passes the widget's own eye but not `clients.display_name`, so it is refused
		// here rather than failing on the Client insert.
		await expectUnreadableRefusal(
			await postFirstMessage(firstMessageEvent({ ...firstMessageBody, name: 'P' }))
		);
		// Neither a phone nor an email is a session that can never be replied to.
		await expectUnreadableRefusal(
			await postFirstMessage(firstMessageEvent({ ...firstMessageBody, phone: undefined }))
		);
		await expectUnreadableRefusal(await postFirstMessage(firstMessageEvent()));
	});

	it('drops a honeypot submission without spending a database call', async () => {
		const response = await postFirstMessage(
			firstMessageEvent({ ...firstMessageBody, company_website: 'http://spam.example' })
		);

		await expectUnreadableRefusal(response);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends the database only the hash, and hands the visitor a token derived from their attempt', async () => {
		rpc.mockResolvedValue({
			data: {
				status: 'accepted',
				replayed: false,
				session_id: 'session-1',
				match_status: 'resolved',
				message_id: 'message-1'
			},
			error: null
		});

		const response = await postFirstMessage(firstMessageEvent());
		const payload = await response.json();

		expect(response.status).toBe(200);
		expect(response.headers.get('access-control-allow-origin')).toBe(origin);
		expect(response.headers.get('cache-control')).toBe('no-store');

		const args = commandArgs('accept_website_chat_first_message');
		expect(args.new_session_token_hash).toBe(
			createHash('sha256').update(payload.session_token, 'utf8').digest('hex')
		);
		// The raw secret exists only in the response the visitor's own browser receives.
		expect(JSON.stringify(args)).not.toContain(payload.session_token);
		// And the visitor's IP is hashed before it is used for anything at all.
		expect(args.visitor_ip_hash).toBe(
			createHash('sha256').update('198.51.100.7', 'utf8').digest('hex')
		);
	});

	it('gives a retried attempt the same working token the first attempt received', async () => {
		rpc.mockResolvedValue({
			data: { status: 'accepted', replayed: false, session_id: 'session-1' },
			error: null
		});
		const first = await (await postFirstMessage(firstMessageEvent())).json();

		rpc.mockResolvedValue({
			data: { status: 'accepted', replayed: true, session_id: 'session-1' },
			error: null
		});
		const retry = await (await postFirstMessage(firstMessageEvent())).json();

		// This is the whole reason the token is derived rather than random: a first message can commit
		// and still fail to reach the browser, and a replay must not hand back a dead session.
		expect(retry.replayed).toBe(true);
		expect(retry.session_token).toBe(first.session_token);
	});

	it('gives a different attempt a different session', async () => {
		rpc.mockResolvedValue({
			data: { status: 'accepted', replayed: false, session_id: 'session-1' },
			error: null
		});

		const one = await (await postFirstMessage(firstMessageEvent())).json();
		const two = await (
			await postFirstMessage(
				firstMessageEvent({ ...firstMessageBody, idempotency_key: 'visitor-attempt-0002' })
			)
		).json();

		expect(two.session_token).not.toBe(one.session_token);
	});

	it('tells the visitor the truth when the contractor is capped, unentitled, or flooding', async () => {
		rpc.mockResolvedValue({ data: { status: 'cap_reached' }, error: null });
		expect((await postFirstMessage(firstMessageEvent())).status).toBe(409);

		rpc.mockResolvedValue({
			data: { status: 'unavailable', reason: 'not_entitled' },
			error: null
		});
		const unavailable = await postFirstMessage(firstMessageEvent());
		expect(unavailable.status).toBe(503);
		expect((await unavailable.json()).reason).toBe('not_entitled');
		// These are readable on purpose -- a widget that cannot say "we can't take messages right now"
		// leaves the visitor typing into nothing.
		expect(unavailable.headers.get('access-control-allow-origin')).toBe(origin);

		rpc.mockResolvedValue({ data: { status: 'rate_limited' }, error: null });
		expect((await postFirstMessage(firstMessageEvent())).status).toBe(429);
	});
});

describe('every later Website Chat message', () => {
	const sessionToken = 'f'.repeat(64);

	it('refuses a missing, malformed, or non-bearer session token before any database call', async () => {
		await expectUnreadableRefusal(await postLaterMessage(laterMessageEvent('')));
		await expectUnreadableRefusal(await postLaterMessage(laterMessageEvent('Bearer short')));
		await expectUnreadableRefusal(await postLaterMessage(laterMessageEvent(sessionToken)));
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends the hash of the session token, never the token itself', async () => {
		rpc.mockResolvedValue({
			data: { status: 'accepted', replayed: false, session_id: 'session-1', message_id: 'm-2' },
			error: null
		});

		await postLaterMessage(laterMessageEvent(`Bearer ${sessionToken}`));

		const args = commandArgs('post_website_chat_message');
		expect(args.session_token_hash).toBe(
			createHash('sha256').update(sessionToken, 'utf8').digest('hex')
		);
		expect(JSON.stringify(args)).not.toContain(sessionToken);
	});

	it('reports a closed session instead of silently swallowing the message', async () => {
		rpc.mockResolvedValue({ data: { status: 'session_closed' }, error: null });

		const response = await postLaterMessage(laterMessageEvent(`Bearer ${sessionToken}`));

		expect(response.status).toBe(409);
		expect((await response.json()).status).toBe('session_closed');
	});
});

describe('public Website Chat logging', () => {
	it('never writes a token, a contact detail, or a message body', async () => {
		const info = vi.spyOn(console, 'info').mockImplementation(() => {});
		rpc.mockResolvedValue({ data: { status: 'refused' }, error: null });

		await postFirstMessage(firstMessageEvent());
		await postFirstMessage(
			firstMessageEvent({ ...firstMessageBody, company_website: 'http://spam.example' })
		);

		const logged = JSON.stringify(info.mock.calls);
		expect(logged).not.toContain(firstMessageBody.phone);
		expect(logged).not.toContain(firstMessageBody.message);
		expect(logged).not.toContain('198.51.100.7');
		info.mockRestore();
	});
});
