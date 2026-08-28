import type { RequestHandler } from './$types';
import { getPublicEnv } from '$lib/config/public';
import {
	getWebsiteChatPublicResolverClient,
	hashWebsiteChatSessionToken,
	isWellFormedSessionToken,
	logWebsiteChatPublicOutcome,
	mintWebsiteChatRealtimeTopic,
	websiteChatJsonResponse,
	websiteChatPreflight,
	websiteChatRefusal
} from '$lib/server/communications/website-chat-public';

// The visitor asking to be let onto their own live channel. Everything the widget needs to open the
// socket comes back from this one call -- the project URL, the publishable key, the topic and its
// expiry -- so the widget never carries build-time configuration for an environment it is embedded on
// from somewhere else.
//
// The two values that look like credentials are not: `PUBLIC_SUPABASE_URL` and the publishable key are
// already public on every signed-in page of this application. They identify the project, never a
// person, and on their own they authorize nothing -- joining the channel still requires the topic,
// which the database hands out only against this session's own secret and an allowlisted origin.
//
// POST, not GET: this mints and stores a grant. A GET would be cached, prefetched and retried by
// things that have no business rotating a channel.

type RealtimeGrantResult = {
	status: 'ok' | 'refused' | 'rate_limited';
	session_id?: string;
	channel_topic?: string;
	expires_at?: string;
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
		'POST'
	);

export const POST: RequestHandler = async ({ request }) => {
	const requestOrigin = request.headers.get('origin') ?? '';
	const sessionToken = readSessionToken(request);

	if (!isWellFormedSessionToken(sessionToken) || !requestOrigin) return websiteChatRefusal();

	// No request body at all. The topic is the authorization, so it is minted here from the server
	// secret; there is nothing about this grant a caller is allowed to propose.
	const sessionTokenHash = hashWebsiteChatSessionToken(sessionToken);
	const client = getWebsiteChatPublicResolverClient();
	const { data, error } = await client.rpc('mint_website_chat_realtime_grant', {
		session_token_hash: sessionTokenHash,
		requesting_origin: requestOrigin,
		proposed_topic: mintWebsiteChatRealtimeTopic(sessionTokenHash)
	});
	if (error) throw error;

	const result = data as unknown as RealtimeGrantResult;

	if (result.status === 'ok' && result.channel_topic && result.expires_at) {
		const publicEnv = getPublicEnv();
		return websiteChatJsonResponse(
			{
				status: 'ok',
				channel_topic: result.channel_topic,
				expires_at: result.expires_at,
				supabase_url: publicEnv.PUBLIC_SUPABASE_URL,
				supabase_key: publicEnv.PUBLIC_SUPABASE_PUBLISHABLE_KEY
			},
			200,
			requestOrigin
		);
	}

	// A refused or throttled mint is never fatal to the conversation: the widget keeps its poll and the
	// visitor never learns there was a socket. Logged because, unlike a message send, this fires once
	// per connect -- a refusal here is a real signal rather than noise.
	if (result.status === 'rate_limited') {
		logWebsiteChatPublicOutcome('sessions/realtime', 'rate_limited', {
			tokenHash: sessionTokenHash
		});
		return websiteChatJsonResponse({ status: 'rate_limited' }, 429, requestOrigin);
	}

	logWebsiteChatPublicOutcome('sessions/realtime', 'refused', { tokenHash: sessionTokenHash });
	return websiteChatRefusal();
};
