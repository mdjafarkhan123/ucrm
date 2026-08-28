import type { RequestHandler } from './$types';
import {
	getWebsiteChatPublicResolverClient,
	hashWebsiteChatSessionToken,
	isWellFormedSessionToken,
	logWebsiteChatPublicOutcome,
	websiteChatJsonResponse,
	websiteChatPreflight,
	websiteChatRefusal
} from '$lib/server/communications/website-chat-public';
import { websiteChatLaterMessageSchema } from '$lib/server/validation/communications.schema';

// Every message after the first. Nothing here claims an allowance unit and nothing here touches
// identity -- the contract is explicit that an accepted conversation stays usable even when the
// organization is at its cap. Authorization is the visitor's own session secret, which is scoped to
// exactly one session and is never enumerable across sessions or widgets (WC0.3).

type LaterMessageResult = {
	status: 'accepted' | 'refused' | 'session_closed' | 'rate_limited';
	replayed?: boolean;
	session_id?: string;
	message_id?: string;
};

// The bearer token is the visitor's session secret; the widget token in the query string exists only so
// the preflight has something to check the origin against before any session is in play.
function readSessionToken(request: Request) {
	const header = request.headers.get('authorization') ?? '';
	const [scheme, value] = header.split(' ');
	return scheme?.toLowerCase() === 'bearer' ? value?.trim() : undefined;
}

export const OPTIONS: RequestHandler = ({ url, request, getClientAddress }) =>
	websiteChatPreflight(
		url.searchParams.get('token') ?? undefined,
		request.headers.get('origin') ?? '',
		getClientAddress(),
		'POST'
	);

export const POST: RequestHandler = async ({ request }) => {
	const requestOrigin = request.headers.get('origin') ?? '';
	const sessionToken = readSessionToken(request);

	if (!isWellFormedSessionToken(sessionToken) || !requestOrigin) return websiteChatRefusal();

	let rawBody: unknown;
	try {
		rawBody = await request.json();
	} catch {
		return websiteChatRefusal();
	}

	const parsed = websiteChatLaterMessageSchema.safeParse(rawBody);
	if (!parsed.success) return websiteChatRefusal();

	// The command re-checks the origin against this session's own widget, so a script copied onto an
	// unauthorized site fails on every message, not only on the first one.
	const sessionTokenHash = hashWebsiteChatSessionToken(sessionToken);
	const client = getWebsiteChatPublicResolverClient();
	const { data, error } = await client.rpc('post_website_chat_message', {
		session_token_hash: sessionTokenHash,
		requesting_origin: requestOrigin,
		message_body: parsed.data.message,
		// Empty string is the command's own "no key" -- it normalizes it to null before use.
		new_idempotency_key: parsed.data.idempotency_key ?? ''
	});
	if (error) throw error;

	const result = data as unknown as LaterMessageResult;

	// Deliberately not logged on the happy path: unlike a first message, which is a paid conversation
	// and worth one audit line each, this route fires on every sentence a visitor types. At scale that
	// is the highest-volume line in the application, and it would say nothing a message row does not
	// already record. Only the outcomes that need explaining are logged.
	if (result.status === 'accepted') {
		return websiteChatJsonResponse(
			{
				status: 'accepted',
				replayed: result.replayed ?? false,
				session_id: result.session_id,
				message_id: result.message_id
			},
			200,
			requestOrigin
		);
	}

	// A closed session is a normal end state, not an error to hide: the widget has to be able to show
	// the contract's "this conversation has ended" state instead of a message that silently never sends.
	if (result.status === 'session_closed') {
		logWebsiteChatPublicOutcome('messages', 'session_closed', { tokenHash: sessionTokenHash });
		return websiteChatJsonResponse({ status: 'session_closed' }, 409, requestOrigin);
	}

	if (result.status === 'rate_limited') {
		logWebsiteChatPublicOutcome('messages', 'rate_limited', { tokenHash: sessionTokenHash });
		return websiteChatJsonResponse({ status: 'rate_limited' }, 429, requestOrigin);
	}

	logWebsiteChatPublicOutcome('messages', 'refused', { tokenHash: sessionTokenHash });
	return websiteChatRefusal();
};
