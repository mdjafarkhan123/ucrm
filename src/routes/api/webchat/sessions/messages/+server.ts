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
import { websiteChatSessionMessagesQuerySchema } from '$lib/server/validation/communications.schema';

// The visitor reading their own conversation back: session restore after a reload, and the ~4s polling
// fallback behind Realtime, both land here. Authorization is the same pair `post_website_chat_message`
// uses -- the visitor's session secret plus an allowlisted origin -- so a script copied onto an
// unauthorized site can no more read a conversation than write to one.
//
// This is the highest-frequency route in the application by design (every open tab polls it when the
// socket is unavailable), which is why the happy path is not logged and the command clamps its own page
// size rather than trusting the query string.

type SessionMessage = {
	id: string;
	direction: 'inbound' | 'outbound';
	sender_type: 'visitor' | 'staff' | 'system' | 'automation';
	body: string;
	created_at: string;
};

type SessionMessagesResult = {
	status: 'ok' | 'refused' | 'rate_limited';
	session_id?: string;
	closed_at?: string | null;
	messages?: SessionMessage[];
	has_more?: boolean;
};

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
		'GET'
	);

export const GET: RequestHandler = async ({ url, request }) => {
	const requestOrigin = request.headers.get('origin') ?? '';
	const sessionToken = readSessionToken(request);

	if (!isWellFormedSessionToken(sessionToken) || !requestOrigin) return websiteChatRefusal();

	const parsed = websiteChatSessionMessagesQuerySchema.safeParse({
		before_created_at: url.searchParams.get('before_created_at') ?? undefined,
		before_id: url.searchParams.get('before_id') ?? undefined,
		page_size: url.searchParams.get('page_size') ?? undefined
	});
	if (!parsed.success) return websiteChatRefusal();

	const sessionTokenHash = hashWebsiteChatSessionToken(sessionToken);
	const client = getWebsiteChatPublicResolverClient();
	const { data, error } = await client.rpc('get_website_chat_session_messages', {
		session_token_hash: sessionTokenHash,
		requesting_origin: requestOrigin,
		// The command treats a null cursor as "from the newest message"; the schema has already
		// guaranteed both halves are present together or absent together.
		before_created_at: parsed.data.before_created_at ?? undefined,
		before_id: parsed.data.before_id ?? undefined,
		page_size: parsed.data.page_size ?? undefined
	});
	if (error) throw error;

	const result = data as unknown as SessionMessagesResult;

	if (result.status === 'ok') {
		return websiteChatJsonResponse(
			{
				status: 'ok',
				session_id: result.session_id,
				closed_at: result.closed_at ?? null,
				messages: result.messages ?? [],
				has_more: result.has_more ?? false
			},
			200,
			requestOrigin
		);
	}

	if (result.status === 'rate_limited') {
		logWebsiteChatPublicOutcome('sessions/messages', 'rate_limited', {
			tokenHash: sessionTokenHash
		});
		return websiteChatJsonResponse({ status: 'rate_limited' }, 429, requestOrigin);
	}

	logWebsiteChatPublicOutcome('sessions/messages', 'refused', { tokenHash: sessionTokenHash });
	return websiteChatRefusal();
};
