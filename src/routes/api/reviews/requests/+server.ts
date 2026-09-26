import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	reviewRequestContextQuerySchema,
	reviewRequestCreateSchema
} from '$lib/server/validation/reviews.schema';
import {
	ReviewRequestRefusedError,
	loadReviewRequestContext,
	sendReviewRequest
} from '$lib/server/reviews/requests';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

// Google review campaign Part 3: the manual "Request a review" panel. reviews.request folds in the plan's
// Reputation feature; the database re-checks it with the member's scope for the exact job.

// Everything the panel needs for one job (job page) or one client (client page).
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.request');
	if ('response' in check) return check.response;

	const parsed = reviewRequestContextQuerySchema.safeParse({
		job_id: event.url.searchParams.get('job_id') ?? undefined,
		client_id: event.url.searchParams.get('client_id') ?? undefined
	});
	if (!parsed.success) return validationError({ form: 'Choose a job or a client.' });

	try {
		const context = await loadReviewRequestContext(check.auth.organization.id, check.auth.user.id, {
			jobId: parsed.data.job_id ?? null,
			clientId: parsed.data.client_id ?? null
		});
		if (!context) {
			return json(
				{ error: 'You can ask for a review only about work you can see.' },
				{ status: 404, headers: NO_STORE_HEADERS }
			);
		}
		return json(context, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the review request context.', error);
		return json(
			{ error: 'The review request details could not be loaded.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'reviews.request');
	if ('response' in check) return check.response;

	const body = await event.request.json().catch(() => null);
	const parsed = reviewRequestCreateSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;
	try {
		const limit = await checkRateLimit(getOwnerSupabaseClient(), {
			bucketKey: `review_request_manual:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 30
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const request = await sendReviewRequest(
			organizationId,
			check.auth.user.id,
			event.url.origin,
			parsed.data
		);
		return json(request, { status: 201, headers: NO_STORE_HEADERS });
	} catch (error) {
		if (error instanceof ReviewRequestRefusedError) {
			return json({ error: error.message }, { status: error.status, headers: NO_STORE_HEADERS });
		}
		console.error('Could not send the review request.', error);
		return json(
			{ error: 'The review request could not be sent.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
};
