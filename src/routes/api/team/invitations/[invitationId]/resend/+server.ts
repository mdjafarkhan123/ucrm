import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { invitationErrorResponse } from '$lib/server/team/invitation-responses';
import { resendTeamInvitation } from '$lib/server/team/invitations';
import { invitationIdSchema } from '$lib/server/validation/access.schema';

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

	const client = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(client, {
			bucketKey: `team_invitation_resend:${required.context.auth.organization.id}:${required.context.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const result = await resendTeamInvitation(client, {
			organizationId: required.context.auth.organization.id,
			invitationId: invitationId.data,
			businessName: required.context.auth.organization.name,
			origin: event.url.origin
		});
		return json(result, {
			status: result.status === 'delivery_failed' ? 202 : 200,
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not resend team invitation.', error);
		return invitationErrorResponse(error);
	}
};
