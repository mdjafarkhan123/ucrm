import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	SenderCommandError,
	loadSenderRemovalImpact,
	removeCommunicationSender
} from '$lib/server/communications/sender-commands';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationFieldErrors,
	communicationSenderRemovalSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

function invalidSenderResponse() {
	return json({ error: 'The sender identifier is invalid.' }, { status: 422, headers: noStore });
}

function notFoundResponse() {
	return json({ error: 'The sender could not be found.' }, { status: 404, headers: noStore });
}

/** What removing this sender will change, for the confirmation dialog. */
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const senderId = organizationIdSchema.safeParse(event.params.senderId);
	if (!senderId.success) return invalidSenderResponse();

	try {
		const impact = await loadSenderRemovalImpact(
			getOwnerSupabaseClient(),
			check.auth.organization.id,
			senderId.data
		);
		if (!impact) return notFoundResponse();
		return json({ impact }, { headers: noStore });
	} catch (error) {
		console.error('Could not load the sender removal impact.', error);
		return json(
			{ error: 'What removing this sender affects could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
};

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const senderId = organizationIdSchema.safeParse(event.params.senderId);
	if (!senderId.success) return invalidSenderResponse();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationSenderRemovalSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please try removing the sender again.',
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

		const result = await removeCommunicationSender(client, {
			organizationId: check.auth.organization.id,
			actorUserId: check.auth.user.id,
			senderId: senderId.data,
			idempotencyKey: parsed.data.idempotency_key
		});
		return json(
			{ sender_id: result.sender.id, removed: true, replayed: result.replayed },
			{ headers: noStore }
		);
	} catch (error) {
		if (error instanceof SenderCommandError) {
			return json(
				{ error: error.message, reason: error.reason },
				{ status: error.status, headers: noStore }
			);
		}
		console.error('Could not remove communication sender.', error);
		return json(
			{ error: 'The email sender could not be removed.' },
			{ status: 500, headers: noStore }
		);
	}
};
