import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	checkStripeConnection,
	getStripeConnectionStatus
} from '$lib/server/payments/stripe-connection';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import { z } from 'zod';

// Jafar sees Stripe account identity, live/test mode, API health, webhook health, last check, and
// sanitized failures only (docs/jafar-completion-contract.md "Provider and CRM-dependent controls"). The
// restricted key itself never reaches this route — stripe-connection.ts is the one authoritative
// readiness source and never serializes a secret. Jafar has no reconnect/disconnect authority here: the
// key is contractor-owned, so recovery from a failing connection is a contractor action, not a platform
// one. The only action available is re-checking current health.
const noStore = { 'cache-control': 'no-store' };
const recheckBodySchema = z.object({}).strict();

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json(
			{ error: 'The organization identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	try {
		const status = await getStripeConnectionStatus(parsedOrganizationId.data);
		return json({ status }, { headers: noStore });
	} catch (error) {
		console.error('Could not load the organization Stripe connection status.', error);
		return json(
			{ error: 'Stripe connection status could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json(
			{ error: 'The organization identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		body = {};
	}
	const parsed = recheckBodySchema.safeParse(body);
	if (!parsed.success) {
		return json({ error: 'This action takes no parameters.' }, { status: 422, headers: noStore });
	}

	try {
		const rateLimit = await checkRateLimit(getOwnerSupabaseClient(), {
			bucketKey: `jafar_stripe_recheck:${session.sessionId}`,
			windowSeconds: 60,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const status = await checkStripeConnection(parsedOrganizationId.data);
		return json({ status }, { headers: noStore });
	} catch (error) {
		console.error('Could not recheck the organization Stripe connection.', error);
		return json(
			{ error: 'The Stripe connection could not be rechecked.' },
			{ status: 500, headers: noStore }
		);
	}
};
