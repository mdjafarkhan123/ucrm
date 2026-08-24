import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { createTeamInvitation } from '$lib/server/team/invitations';
import { invitationErrorResponse } from '$lib/server/team/invitation-responses';
import {
	teamInvitationCreateSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const POST: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}

	const parsed = teamInvitationCreateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the invitation details.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(client, {
			bucketKey: `team_invitation_create:${required.context.auth.organization.id}:${required.context.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const result = await createTeamInvitation(client, {
			organizationId: required.context.auth.organization.id,
			invitedBy: required.context.auth.user.id,
			email: parsed.data.email,
			role: parsed.data.role,
			permissionAdjustments: parsed.data.permission_adjustments,
			businessName: required.context.auth.organization.name,
			origin: event.url.origin
		});

		return json(result, {
			status: result.status === 'delivery_failed' ? 202 : 201,
			headers: NO_STORE_HEADERS
		});
	} catch (error) {
		console.error('Could not create team invitation.', error);
		return invitationErrorResponse(error);
	}
};
