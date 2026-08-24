import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	SenderCommandError,
	updateCommunicationSender
} from '$lib/server/communications/sender-commands';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationFieldErrors,
	communicationSenderUpdateSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

function contractorSender(sender: Awaited<ReturnType<typeof updateCommunicationSender>>['sender']) {
	return {
		id: sender.id,
		domain_id: sender.domain_id,
		email_address: sender.email_address,
		display_name: sender.display_name,
		lifecycle_state: sender.lifecycle_state,
		assigned_user_id: sender.assigned_user_id,
		is_organization_default: sender.is_organization_default,
		allows_manual: sender.allows_manual,
		allows_automated: sender.allows_automated,
		restriction_reason: sender.restriction_reason,
		created_at: sender.created_at,
		updated_at: sender.updated_at
	};
}

export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const senderId = organizationIdSchema.safeParse(event.params.senderId);
	if (!senderId.success)
		return json({ error: 'The sender identifier is invalid.' }, { status: 422, headers: noStore });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationSenderUpdateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the sender details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	try {
		const rateLimit = await checkRateLimit(client, {
			bucketKey: `communication_sender:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const input = parsed.data;
		const result = await updateCommunicationSender(client, {
			organizationId: check.auth.organization.id,
			actorUserId: check.auth.user.id,
			senderId: senderId.data,
			displayName: input.display_name,
			assignedUserId: input.assigned_user_id,
			isOrganizationDefault: input.is_organization_default,
			allowsManual: input.allows_manual,
			allowsAutomated: input.allows_automated,
			enabled: input.enabled,
			idempotencyKey: input.idempotency_key
		});
		return json(
			{ sender: contractorSender(result.sender), replayed: result.replayed },
			{ headers: noStore }
		);
	} catch (error) {
		if (error instanceof SenderCommandError) {
			return json(
				{ error: error.message, reason: error.reason, field_errors: error.fieldErrors },
				{ status: error.status, headers: noStore }
			);
		}
		console.error('Could not update communication sender.', error);
		return json(
			{ error: 'The email sender could not be changed.' },
			{ status: 500, headers: noStore }
		);
	}
};
