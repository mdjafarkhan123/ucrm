import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { listMessengerPageChoices } from '$lib/server/communications/messenger-connections';
import { messengerSessionFailureResponse } from '$lib/server/communications/messenger-session-failures';

/** The Pages the person ticked in Facebook's window, for the Choose Pages pop-up. No keys leave the server. */
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	const session = z.string().uuid().safeParse(event.url.searchParams.get('session'));
	if (!session.success) return validationError({ session: 'Log in with Facebook again.' });

	try {
		const listed = await listMessengerPageChoices({
			organizationId: check.auth.organization.id,
			userId: check.auth.user.id,
			sessionId: session.data
		});
		if (!listed.ok) return messengerSessionFailureResponse(listed.reason);
		return json(listed.choices, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not list Facebook Pages.', error);
		return json(
			{ error: 'Your Facebook Pages could not be loaded.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
