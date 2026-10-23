import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, notFound, validationError } from '$lib/server/api/errors';
import { messengerTestQuerySchema } from '$lib/server/validation/communications.schema';
import { findMessengerTestArrival } from '$lib/server/communications/messenger-connections';

/** The live test asks every few seconds whether a message has reached this Page since the test began. */
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	const query = messengerTestQuerySchema.safeParse({ since: event.url.searchParams.get('since') });
	if (!query.success) return validationError({ since: 'Start the live test again.' });

	try {
		const arrival = await findMessengerTestArrival(
			check.auth.organization.id,
			event.params.connectionId,
			query.data.since
		);
		return arrival
			? json(arrival, { headers: NO_STORE_HEADERS })
			: notFound('This Page is no longer connected.');
	} catch (error) {
		console.error('Could not check the Messenger live test.', error);
		return json(
			{ error: 'The live test could not check for your message.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
