import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { checkStripeConnection } from '$lib/server/payments/stripe-connection';

const CHECK_LIMIT = { windowSeconds: 60, maxAttempts: 6 };

/** Re-check the stored Stripe key and webhook endpoint. Takes no input. */
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.payments.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-payments-stripe-check:${organizationId}`,
			...CHECK_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	try {
		return json(
			{ stripe: await checkStripeConnection(organizationId) },
			{ headers: NO_STORE_HEADERS }
		);
	} catch {
		return databaseError();
	}
};
