import { json } from '@sveltejs/kit';
import type { RequestEvent } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext, type OrganizationContext } from '$lib/server/auth/organization';
import { resolveOrganizationAccess } from '$lib/server/access/effective';
import { hasPermission } from '$lib/server/access/permission';
import {
	NO_STORE_HEADERS,
	databaseError,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

type ConversationViewCheck = { auth: OrganizationContext } | { response: Response };

// Following is self-service: anyone who can already see conversations (view_team or view_assigned) may
// follow or unfollow one for themselves. There is no separate "who can follow" permission -- unlike
// assignment, which conversations.manage_assignment gates because it changes someone else's workload.
async function requireConversationView(event: RequestEvent): Promise<ConversationViewCheck> {
	const auth = await getOrganizationContext(event);
	if (!auth) return { response: unauthorized() };

	let access;
	try {
		access = await resolveOrganizationAccess(
			event.locals.supabase,
			auth.organization.id,
			auth.user.id
		);
	} catch (error) {
		console.error('Could not resolve conversation access.', error);
		return { response: databaseError() };
	}
	const canView =
		hasPermission(access, 'conversations.view_team') ||
		hasPermission(access, 'conversations.view_assigned');
	if (!canView) {
		return {
			response: json(
				{ error: 'You do not have access to conversations.', reason: 'permission_denied' },
				{ status: 403, headers: NO_STORE_HEADERS }
			)
		};
	}
	return { auth };
}

export const POST: RequestHandler = async (event) => {
	const check = await requireConversationView(event);
	if ('response' in check) return check.response;

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_follow:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 60
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const { error } = await ownerClient
			.from('communication_conversation_followers')
			.upsert(
				{ organization_id: organizationId, client_id: clientId, user_id: check.auth.user.id },
				{ onConflict: 'organization_id,client_id,user_id', ignoreDuplicates: true }
			);
		if (error) {
			if ((error as { code?: string }).code === '23503')
				return validationError({ form: 'Choose a valid conversation.' });
			console.error('Could not follow the conversation.', error);
			return databaseError();
		}
		return json({ following: true }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not follow the conversation.', error);
		return databaseError();
	}
};

export const DELETE: RequestHandler = async (event) => {
	const check = await requireConversationView(event);
	if ('response' in check) return check.response;

	const clientId = event.params.clientId;
	if (!clientId) return validationError({ form: 'Choose a valid conversation.' });

	const organizationId = check.auth.organization.id;
	const ownerClient = getOwnerSupabaseClient();
	try {
		const limit = await checkRateLimit(ownerClient, {
			bucketKey: `communications_follow:${organizationId}:${check.auth.user.id}`,
			windowSeconds: 60,
			maxAttempts: 60
		});
		if (!limit.allowed) {
			const response = rateLimitedResponse(limit.retryAfterSeconds);
			response.headers.set('cache-control', 'no-store');
			return response;
		}

		const { error } = await ownerClient
			.from('communication_conversation_followers')
			.delete()
			.eq('organization_id', organizationId)
			.eq('client_id', clientId)
			.eq('user_id', check.auth.user.id);
		if (error) {
			console.error('Could not unfollow the conversation.', error);
			return databaseError();
		}
		return json({ following: false }, { headers: NO_STORE_HEADERS });
	} catch (error) {
		console.error('Could not unfollow the conversation.', error);
		return databaseError();
	}
};
