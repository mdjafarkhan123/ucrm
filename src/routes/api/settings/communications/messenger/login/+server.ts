import { randomBytes } from 'node:crypto';
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	messengerGraphConfig,
	messengerLoginDialogUrl
} from '$lib/server/communications/messenger-graph';
import {
	MESSENGER_LOGIN_COOKIE_PATH,
	MESSENGER_LOGIN_STATE_COOKIE,
	messengerAppOrigin,
	messengerLoginWindow,
	messengerRedirectUri
} from '$lib/server/communications/messenger-login';

// Opened in Facebook's small window from Settings → Messenger. A random state, kept in a cookie only this browser
// holds, is checked when Facebook sends the window back, so nobody else can finish this login.
export const GET: RequestHandler = async (event) => {
	const origin = messengerAppOrigin(event.url.origin);
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check || !messengerGraphConfig())
		return messengerLoginWindow({ type: 'ucrm-messenger-login', result: 'failed' }, origin);

	const state = randomBytes(24).toString('base64url');
	event.cookies.set(MESSENGER_LOGIN_STATE_COOKIE, state, {
		path: MESSENGER_LOGIN_COOKIE_PATH,
		httpOnly: true,
		sameSite: 'lax',
		secure: origin.startsWith('https:'),
		maxAge: 900
	});
	redirect(303, messengerLoginDialogUrl({ state, redirectUri: messengerRedirectUri(origin) }));
};
