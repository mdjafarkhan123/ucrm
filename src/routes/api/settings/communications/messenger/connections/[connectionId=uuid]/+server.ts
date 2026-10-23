import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { messengerConnectionUpdateSchema } from '$lib/server/validation/communications.schema';
import {
	disconnectMessengerPage,
	makeMessengerPageDefault
} from '$lib/server/communications/messenger-connections';

const GONE = 'This Page is no longer connected.';

/** Make this Page the one new Messenger conversations start from. */
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = messengerConnectionUpdateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const done = await makeMessengerPageDefault(
			check.auth.organization.id,
			event.params.connectionId
		);
		return done ? json({ ok: true }, { headers: NO_STORE_HEADERS }) : notFound(GONE);
	} catch (error) {
		console.error('Could not change the default Messenger Page.', error);
		return databaseError();
	}
};

/** Disconnect the Page: no new messages, key wiped, conversations kept. */
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	try {
		const done = await disconnectMessengerPage(
			check.auth.organization.id,
			event.params.connectionId
		);
		return done ? json({ ok: true }, { headers: NO_STORE_HEADERS }) : notFound(GONE);
	} catch (error) {
		console.error('Could not disconnect a Messenger Page.', error);
		return databaseError();
	}
};
