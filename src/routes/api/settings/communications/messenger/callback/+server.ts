import { timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	MessengerGraphError,
	exchangeMessengerLoginCode,
	fetchMessengerFacebookUser,
	fetchMessengerManagedPages
} from '$lib/server/communications/messenger-graph';
import { saveMessengerLoginSession } from '$lib/server/communications/messenger-connections';
import {
	MESSENGER_LOGIN_COOKIE_PATH,
	MESSENGER_LOGIN_STATE_COOKIE,
	messengerAppOrigin,
	messengerLoginWindow,
	messengerRedirectUri
} from '$lib/server/communications/messenger-login';

// Where Facebook sends its window back. The code becomes a short-lived, encrypted login session; the Settings tab
// then shows the Pages it can see. The window reports the result to that tab and closes.

const querySchema = z.object({
	code: z.string().min(1).max(2000),
	state: z.string().min(1).max(200)
});

function sameText(a: string, b: string) {
	const left = Buffer.from(a);
	const right = Buffer.from(b);
	return left.length === right.length && timingSafeEqual(left, right);
}

export const GET: RequestHandler = async (event) => {
	const origin = messengerAppOrigin(event.url.origin);
	const done = (result: 'cancelled' | 'no_pages' | 'failed') =>
		messengerLoginWindow({ type: 'ucrm-messenger-login', result }, origin);

	const expected = event.cookies.get(MESSENGER_LOGIN_STATE_COOKIE);
	event.cookies.delete(MESSENGER_LOGIN_STATE_COOKIE, { path: MESSENGER_LOGIN_COOKIE_PATH });

	// The person pressed Cancel or closed Facebook's consent.
	if (event.url.searchParams.has('error')) return done('cancelled');
	const parsed = querySchema.safeParse(Object.fromEntries(event.url.searchParams));
	if (!parsed.success || !expected || !sameText(expected, parsed.data.state)) return done('failed');

	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return done('failed');

	try {
		const userToken = await exchangeMessengerLoginCode(
			parsed.data.code,
			messengerRedirectUri(origin)
		);
		const [facebookUser, pages] = await Promise.all([
			fetchMessengerFacebookUser(userToken),
			fetchMessengerManagedPages(userToken)
		]);
		if (!pages.length) return done('no_pages');
		const sessionId = await saveMessengerLoginSession({
			organizationId: check.auth.organization.id,
			userId: check.auth.user.id,
			userToken,
			facebookUser
		});
		return messengerLoginWindow(
			{ type: 'ucrm-messenger-login', result: 'ok', session_id: sessionId },
			origin
		);
	} catch (error) {
		console.error('Messenger Facebook login could not finish.', {
			failure: error instanceof MessengerGraphError ? error.failure : 'internal',
			code: error instanceof MessengerGraphError ? error.code : null
		});
		return done('failed');
	}
};
