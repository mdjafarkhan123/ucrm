import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { stripeConnectSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { connectStripe, disconnectStripe } from '$lib/server/payments/stripe-connection';

// Each connect creates a webhook endpoint inside the contractor's Stripe account, so attempts are kept low.
const CONNECT_LIMIT = { windowSeconds: 600, maxAttempts: 10 };

const CONNECT_FAILURES = {
	key_rejected: {
		status: 422,
		field: 'Stripe did not accept this key. Copy it again from Stripe and paste the whole key.'
	},
	permission_missing: {
		status: 422,
		field:
			'This key is missing a permission UCRM needs. In Stripe, edit the key and match the permissions in the guide below.'
	},
	stripe_unavailable: {
		status: 502,
		field: 'Stripe could not be reached just now. Please try again in a minute.'
	},
	not_configured: {
		status: 503,
		field: 'Online payments are not set up on our side yet. Please contact support.'
	},
	storage_failed: {
		status: 500,
		field: 'We could not save the connection. Nothing was changed — please try again.'
	}
} as const;

/** Connect Stripe, or replace the key of an existing connection. */
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.payments.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-payments-stripe-connect:${organizationId}`,
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

	const parsed = stripeConnectSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	let result;
	try {
		result = await connectStripe({
			organizationId,
			actorUserId: check.auth.user.id,
			apiKey: parsed.data.api_key
		});
	} catch {
		return databaseError();
	}

	if (!result.ok) {
		const failure = CONNECT_FAILURES[result.reason];
		return json(
			{ error: failure.field, reason: result.reason, field_errors: { api_key: failure.field } },
			{ status: failure.status, headers: NO_STORE_HEADERS }
		);
	}

	return json({ stripe: result.status }, { headers: NO_STORE_HEADERS });
};

/** Disconnect Stripe. Pay buttons disappear at once; payments already recorded stay. */
export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.payments.manage');
	if ('response' in check) return check.response;

	try {
		await disconnectStripe({
			organizationId: check.auth.organization.id,
			actorUserId: check.auth.user.id
		});
	} catch {
		return databaseError();
	}

	return json({ stripe: { connected: false } }, { headers: NO_STORE_HEADERS });
};
