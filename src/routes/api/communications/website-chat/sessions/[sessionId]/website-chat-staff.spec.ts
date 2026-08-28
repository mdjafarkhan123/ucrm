import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POST as postMessage } from './messages/+server';
import { POST as endSession } from './end/+server';
import { POST as resolveIdentity } from './identity/+server';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit } from '$lib/server/security/rate-limit';

vi.mock('$lib/server/access/permission', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/access/permission')>(
		'$lib/server/access/permission'
	);
	return { ...actual, requireOrganizationPermission: vi.fn() };
});
vi.mock('$lib/server/db/owner-supabase', () => ({ getOwnerSupabaseClient: vi.fn() }));
vi.mock('$lib/server/security/rate-limit', async () => {
	const actual = await vi.importActual<typeof import('$lib/server/security/rate-limit')>(
		'$lib/server/security/rate-limit'
	);
	return { ...actual, checkRateLimit: vi.fn() };
});

const mockedRequire = vi.mocked(requireOrganizationPermission);
const mockedOwnerClient = vi.mocked(getOwnerSupabaseClient);
const mockedRateLimit = vi.mocked(checkRateLimit);

const sessionId = '00000000-0000-4000-8000-0000000000a1';
const clientId = '00000000-0000-4000-8000-0000000000b2';
const idempotencyKey = '00000000-0000-4000-8000-0000000000c3';

function event(body: unknown, params: Record<string, string> = { sessionId }) {
	return {
		params,
		request: new Request('http://localhost/api/communications/website-chat/sessions/x', {
			method: 'POST',
			body: body === undefined ? null : JSON.stringify(body)
		})
	} as never;
}

const rpc = vi.fn();

// customers.* rides the core.customers_properties entitlement, so a permission map alone is not enough
// to grant it -- the same pair the conversation reply route already asks for.
function grant(
	permissions: Record<string, boolean>,
	features = { 'core.customers_properties': true }
) {
	mockedRequire.mockResolvedValue({
		auth: { organization: { id: 'org-1' }, user: { id: 'user-1' } },
		access: { permissions, features }
	} as never);
}

beforeEach(() => {
	vi.clearAllMocks();
	grant({
		'conversations.send': true,
		'conversations.manage_assignment': true,
		'customers.view': true
	});
	mockedOwnerClient.mockReturnValue({ rpc } as never);
	mockedRateLimit.mockResolvedValue({ allowed: true, retryAfterSeconds: 0 });
	rpc.mockResolvedValue({ data: { status: 'sent' }, error: null });
});

describe('replying into a Website Chat session', () => {
	it('refuses a caller without conversations.send before touching the database', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		const response = await postMessage(event({ body: 'Hi', idempotency_key: idempotencyKey }));
		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	// The session id comes off the URL, so a malformed one must be refused here rather than handed to a
	// uuid column as a 500.
	it('refuses a session id that is not a uuid', async () => {
		const response = await postMessage(
			event({ body: 'Hi', idempotency_key: idempotencyKey }, { sessionId: 'not-a-uuid' })
		);
		expect(response.status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('refuses an empty message and a missing idempotency key', async () => {
		expect(
			(await postMessage(event({ body: '   ', idempotency_key: idempotencyKey }))).status
		).toBe(422);
		expect((await postMessage(event({ body: 'Hi' }))).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	// Addressed by session, never by client: a conflicting-identity session has no client at all and is
	// still a real conversation somebody has to answer.
	it('passes the session id and the retry key straight to the command', async () => {
		const response = await postMessage(
			event({ body: '  On my way.  ', idempotency_key: idempotencyKey })
		);
		expect(response.status).toBe(201);
		expect(rpc).toHaveBeenCalledWith('post_website_chat_staff_message', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_session_id: sessionId,
			message_body: 'On my way.',
			new_idempotency_key: idempotencyKey
		});
	});

	it('forwards the ended-session refusal as something the operator can act on', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '55000', message: 'This conversation has ended.' }
		});
		const response = await postMessage(event({ body: 'Hi', idempotency_key: idempotencyKey }));
		expect(response.status).toBe(422);
		expect((await response.json()).error).toBe('This conversation has ended.');
	});

	it('hides an unexpected database fault behind the generic failure', async () => {
		rpc.mockResolvedValue({ data: null, error: { code: '42P01', message: 'relation missing' } });
		const response = await postMessage(event({ body: 'Hi', idempotency_key: idempotencyKey }));
		expect(response.status).toBe(500);
	});

	it('stops a flood before it reaches a visitor', async () => {
		mockedRateLimit.mockResolvedValue({ allowed: false, retryAfterSeconds: 30 });
		const response = await postMessage(event({ body: 'Hi', idempotency_key: idempotencyKey }));
		expect(response.status).toBe(429);
		expect(rpc).not.toHaveBeenCalled();
	});
});

describe('ending a Website Chat session', () => {
	it('takes no request body -- who ended it comes from the session, not the browser', async () => {
		rpc.mockResolvedValue({ data: { status: 'closed' }, error: null });
		const response = await endSession(event(undefined));
		expect(response.status).toBe(200);
		expect(rpc).toHaveBeenCalledWith('end_website_chat_session', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_session_id: sessionId
		});
	});

	it('requires conversations.send, the same permission replying does', async () => {
		mockedRequire.mockResolvedValue({ response: new Response(null, { status: 403 }) } as never);
		expect((await endSession(event(undefined))).status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('forwards an already-ended session as an actionable refusal', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '55000', message: 'This conversation has already ended.' }
		});
		expect((await endSession(event(undefined))).status).toBe(422);
	});
});

describe('resolving a conflicting Website Chat identity', () => {
	it('needs customers.view as well, because it attaches a conversation to a contact', async () => {
		grant({ 'conversations.manage_assignment': true });
		const response = await resolveIdentity(event({ client_id: clientId }));
		expect(response.status).toBe(403);
		expect(rpc).not.toHaveBeenCalled();
	});

	// There is deliberately no dismiss path: the session already holds real messages and has already
	// claimed an allowance unit, so it always belongs to somebody.
	it('refuses a request with no client to attach the conversation to', async () => {
		expect((await resolveIdentity(event({}))).status).toBe(422);
		expect((await resolveIdentity(event({ client_id: null }))).status).toBe(422);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('sends the chosen client to the command', async () => {
		rpc.mockResolvedValue({
			data: { status: 'resolved', messages_backfilled: 3 },
			error: null
		});
		const response = await resolveIdentity(event({ client_id: clientId }));
		expect(response.status).toBe(200);
		expect(await response.json()).toEqual({ status: 'resolved', messages_backfilled: 3 });
		expect(rpc).toHaveBeenCalledWith('resolve_website_chat_session_identity', {
			target_organization_id: 'org-1',
			target_actor_user_id: 'user-1',
			target_session_id: sessionId,
			target_client_id: clientId
		});
	});

	it('forwards a session someone else already resolved', async () => {
		rpc.mockResolvedValue({
			data: null,
			error: { code: '55000', message: 'This conversation no longer needs review.' }
		});
		const response = await resolveIdentity(event({ client_id: clientId }));
		expect(response.status).toBe(422);
		expect((await response.json()).error).toBe('This conversation no longer needs review.');
	});
});
