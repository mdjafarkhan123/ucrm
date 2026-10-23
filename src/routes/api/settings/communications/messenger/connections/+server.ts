import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { messengerConnectPagesSchema } from '$lib/server/validation/communications.schema';
import { connectMessengerPages } from '$lib/server/communications/messenger-connections';
import { messengerSessionFailureResponse } from '$lib/server/communications/messenger-session-failures';

// Each connect subscribes Pages at Facebook, so attempts are kept low.
const CONNECT_LIMIT = { windowSeconds: 600, maxAttempts: 20 };

/** Connect the Pages ticked in the Choose Pages pop-up, or reconnect ones that need it. */
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-messenger-connect:${organizationId}`,
			...CONNECT_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = messengerConnectPagesSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	try {
		const connected = await connectMessengerPages({
			organizationId,
			userId: check.auth.user.id,
			sessionId: parsed.data.session_id,
			pageIds: parsed.data.page_ids
		});
		if (!connected.ok) return messengerSessionFailureResponse(connected.reason);
		return json(connected.result, {
			status: connected.result.connected.length ? 200 : 422,
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not connect Facebook Pages.', error);
		return json(
			{ error: 'The Pages could not be connected. Nothing was changed — please try again.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
