import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { invitationErrorResponse } from '$lib/server/team/invitation-responses';
import { replaceTeamInvitationEmail } from '$lib/server/team/invitations';
import {
	invitationIdSchema,
	teamInvitationReplaceEmailSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const POST: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const invitationId = invitationIdSchema.safeParse(event.params.invitationId);
	if (!invitationId.success) {
		return json(
			{ error: 'That invitation is not valid.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}

	const parsed = teamInvitationReplaceEmailSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the new email address.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(client, {
			bucketKey: `team_invitation_replace_email:${required.context.auth.organization.id}:${required.context.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const result = await replaceTeamInvitationEmail(client, {
			organizationId: required.context.auth.organization.id,
			invitationId: invitationId.data,
			replacedBy: required.context.auth.user.id,
			email: parsed.data.email,
			businessName: required.context.auth.organization.name,
			origin: event.url.origin
		});

		return json(result, {
			status: result.status === 'delivery_failed' ? 202 : 201,
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not replace team invitation email.', error);
		return invitationErrorResponse(error);
	}
};
