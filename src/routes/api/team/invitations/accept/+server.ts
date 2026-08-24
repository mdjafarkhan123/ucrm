import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { acceptTeamInvitation, inspectTeamInvitation } from '$lib/server/team/invitations';
import { invitationErrorResponse } from '$lib/server/team/invitation-responses';
import {
	teamInvitationAcceptSchema,
	teamInvitationTokenSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

function noStoreRateLimit(retryAfterSeconds: number) {
	const response = rateLimitedResponse(retryAfterSeconds);
	response.headers.set('cache-control', 'no-store');
	return response;
}

export const GET: RequestHandler = async (event) => {
	const parsedToken = teamInvitationTokenSchema.safeParse(event.url.searchParams.get('token'));
	if (!parsedToken.success) {
		return json({ valid: false }, { headers: NO_STORE_HEADERS });
	}

	const client = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(client, {
			bucketKey: `team_invitation_accept_get:${event.getClientAddress()}`,
			windowSeconds: 300,
			maxAttempts: 30
		});
		if (!limit.allowed) return noStoreRateLimit(limit.retryAfterSeconds);

		const result = await inspectTeamInvitation(client, parsedToken.data);
		return json(
			result.valid
				? {
						valid: true,
						email_hint: result.emailHint,
						company_name: result.companyName
					}
				: { valid: false },
			{ headers: NO_STORE_HEADERS }
		);
	} catch {
		return json({ valid: false }, { headers: NO_STORE_HEADERS });
	}
};

export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Please enter your email and a new password.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}

	const parsed = teamInvitationAcceptSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the highlighted fields.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(client, {
			bucketKey: `team_invitation_accept_post:${event.getClientAddress()}`,
			windowSeconds: 900,
			maxAttempts: 10
		});
		if (!limit.allowed) return noStoreRateLimit(limit.retryAfterSeconds);

		const result = await acceptTeamInvitation(client, {
			token: parsed.data.token,
			email: parsed.data.email,
			password: parsed.data.password
		});
		return json(result, { headers: NO_STORE_HEADERS });
	} catch (error) {
		return invitationErrorResponse(error);
	}
};
