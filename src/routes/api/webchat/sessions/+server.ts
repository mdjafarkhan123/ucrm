import type { RequestHandler } from './$types';
import {
	getWebsiteChatPublicResolverClient,
	hashWebsiteChatSessionToken,
	isWellFormedWidgetToken,
	logWebsiteChatPublicOutcome,
	mintWebsiteChatSessionToken,
	websiteChatJsonResponse,
	websiteChatPreflight,
	websiteChatRefusal,
	websiteChatVisitorIpHash
} from '$lib/server/communications/website-chat-public';
import { websiteChatFirstMessageSchema } from '$lib/server/validation/communications.schema';

// The first message a visitor ever sends. This is the only Website Chat call that costs the contractor
// money -- it creates the Client, opens the session and claims one conversation from the allowance --
// so every decision that protects that claim lives inside `accept_website_chat_first_message`, in one
// transaction. This route's whole job is to be a careful doorman: reject what is obviously not a real
// visitor before spending a database round trip, mint the session secret, and translate the command's
// answer into an HTTP response that never leaks more than the visitor is entitled to know.

type FirstMessageResult = {
	status: 'accepted' | 'refused' | 'rate_limited' | 'cap_reached' | 'unavailable';
	replayed?: boolean;
	session_id?: string;
	organization_id?: string;
	client_id?: string | null;
	match_status?: string;
	message_id?: string;
	reason?: 'not_entitled' | 'allowance_period_unavailable';
};

export const OPTIONS: RequestHandler = ({ url, request, getClientAddress }) =>
	websiteChatPreflight(
		url.searchParams.get('token') ?? undefined,
		request.headers.get('origin') ?? '',
		getClientAddress(),
		'POST'
	);

export const POST: RequestHandler = async ({ url, request, getClientAddress }) => {
	const token = url.searchParams.get('token') ?? undefined;
	const requestOrigin = request.headers.get('origin') ?? '';

	// A malformed token, or a call with no `Origin` header at all, never reaches the database. The
	// header is the security boundary here (WC0.3): the browser sets it and page script cannot forge it.
	if (!isWellFormedWidgetToken(token) || !requestOrigin) return websiteChatRefusal();

	let rawBody: unknown;
	try {
		rawBody = await request.json();
	} catch {
		return websiteChatRefusal();
	}

	const parsed = websiteChatFirstMessageSchema.safeParse(rawBody);
	if (!parsed.success) return websiteChatRefusal();

	// Honeypot: invisible to a real visitor, so anything in it is a bot. Silent drop, no database work,
	// and the same answer a bad token gets -- a bot that can tell it was caught learns to stop filling
	// the field.
	if (parsed.data.company_website) {
		logWebsiteChatPublicOutcome('sessions', 'honeypot', {});
		return websiteChatRefusal();
	}

	const body = parsed.data;

	// Derived, not random, so a retried first message reproduces the token the database already stored.
	// The command only ever sees the hash.
	const sessionToken = mintWebsiteChatSessionToken(token, body.idempotency_key);

	const client = getWebsiteChatPublicResolverClient();
	const { data, error } = await client.rpc('accept_website_chat_first_message', {
		widget_public_token: token,
		requesting_origin: requestOrigin,
		new_session_token_hash: hashWebsiteChatSessionToken(sessionToken),
		new_idempotency_key: body.idempotency_key,
		visitor_name: body.name,
		// The command normalizes an empty string to null itself, so an omitted identifier is sent as ''
		// rather than fighting the generated argument types over a nullable text parameter.
		visitor_phone_e164: body.phone ?? '',
		visitor_email: body.email ?? '',
		message_body: body.message,
		consent_transactional_sms: body.consent_transactional_sms,
		visitor_ip_hash: websiteChatVisitorIpHash(getClientAddress()),
		new_attribution: body.attribution
	});
	if (error) throw error;

	const result = data as unknown as FirstMessageResult;

	if (result.status === 'accepted') {
		logWebsiteChatPublicOutcome('sessions', result.replayed ? 'replayed' : 'accepted', {
			organizationId: result.organization_id,
			sessionId: result.session_id
		});
		return websiteChatJsonResponse(
			{
				status: 'accepted',
				replayed: result.replayed ?? false,
				session_id: result.session_id,
				session_token: sessionToken,
				match_status: result.match_status,
				message_id: result.message_id
			},
			200,
			requestOrigin
		);
	}

	// A visitor who is being flooded off has to be told something, or the widget spins forever. The
	// answer carries no detail about which of the three buckets tripped.
	if (result.status === 'rate_limited') {
		logWebsiteChatPublicOutcome('sessions', 'rate_limited', {});
		return websiteChatJsonResponse({ status: 'rate_limited' }, 429, requestOrigin);
	}

	// The two honest, readable outcomes. The contractor has hit their conversation cap, or the channel
	// is not available to them at all -- the visitor deserves a real "we can't take messages right now"
	// instead of silence, and neither answer reveals anything about the widget's existence that the
	// config fetch has not already confirmed to this same allowed origin.
	if (result.status === 'cap_reached') {
		logWebsiteChatPublicOutcome('sessions', 'cap_reached', {});
		return websiteChatJsonResponse({ status: 'cap_reached' }, 409, requestOrigin);
	}
	if (result.status === 'unavailable') {
		logWebsiteChatPublicOutcome('sessions', `unavailable:${result.reason ?? 'unknown'}`, {});
		return websiteChatJsonResponse(
			{ status: 'unavailable', reason: result.reason },
			503,
			requestOrigin
		);
	}

	logWebsiteChatPublicOutcome('sessions', 'refused', {});
	return websiteChatRefusal();
};
