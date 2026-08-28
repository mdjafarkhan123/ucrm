import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationEmailSuppressionRemovalDecisionSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'cache-control': 'no-store' };
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Approve (releases the suppression) or deny (leaves it in place) one pending complaint-removal
// request. Both write an immutable owner audit event inside the command.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const requestId = event.params.requestId ?? '';
	if (!uuidPattern.test(requestId)) {
		return json(
			{ error: 'That removal request was not found.' },
			{ status: 404, headers: noStore }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationEmailSuppressionRemovalDecisionSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the decision.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: request, error } = await client.rpc(
			'decide_communication_email_suppression_removal',
			{
				p_request_id: requestId,
				p_actor_email: session.email,
				p_decision: parsed.data.decision,
				// The command treats an empty note as absent (nullif); Postgres arg types cannot be null.
				p_note: parsed.data.note ?? ''
			}
		);
		if (error) {
			if (error.code === 'P0002') {
				return json({ error: error.message }, { status: 404, headers: noStore });
			}
			if (error.code === '23514') {
				return json({ error: error.message }, { status: 409, headers: noStore });
			}
			throw error;
		}

		const { data: queue, error: queueError } = await client.rpc(
			'get_communication_email_suppression_removal_queue'
		);
		if (queueError) throw queueError;

		return json({ request, ...((queue ?? {}) as Record<string, unknown>) }, { headers: noStore });
	} catch (error) {
		console.error('Could not decide a suppression removal request.', error);
		return json(
			{ error: 'The removal request could not be updated.' },
			{ status: 500, headers: noStore }
		);
	}
};
