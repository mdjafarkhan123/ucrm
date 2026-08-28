import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationMessageRecoveryActionSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

const noStore = { 'cache-control': 'no-store' };
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const notFound = json({ error: 'That message was not found.' }, { status: 404, headers: noStore });

// The history read is tenant-scoped by design, so the owner surface resolves the owning organization
// from the message itself rather than trusting one from the request.
async function organizationIdFor(intentId: string) {
	const { data, error } = await getOwnerSupabaseClient()
		.from('communication_delivery_intents')
		.select('organization_id')
		.eq('id', intentId)
		.maybeSingle();
	if (error) throw error;
	return data?.organization_id ?? null;
}

// One message's whole story: how it was queued, every deferral and attempt, what the provider said,
// and any owner intervention.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const intentId = event.params.intentId ?? '';
	if (!uuidPattern.test(intentId)) return notFound;

	try {
		const organizationId = await organizationIdFor(intentId);
		if (!organizationId) return notFound;

		const { data, error } = await getOwnerSupabaseClient().rpc(
			'get_communication_message_history',
			{ p_organization_id: organizationId, p_delivery_intent_id: intentId }
		);
		if (error) throw error;
		if (!data) return notFound;

		return json(data, { headers: noStore });
	} catch (error) {
		console.error('Could not load a message history.', error);
		return json(
			{ error: 'The message history could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
};

// Retry re-opens the message for the claim -- it sends nothing and skips no check. Cancel stops it and
// hands the reserved allowance back. Both write an owner audit event inside the command.
export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const intentId = event.params.intentId ?? '';
	if (!uuidPattern.test(intentId)) return notFound;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = communicationMessageRecoveryActionSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the action.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422, headers: noStore }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data: result, error } = await client.rpc(
			parsed.data.action === 'retry'
				? 'retry_communication_message'
				: 'cancel_communication_message',
			{
				p_delivery_intent_id: intentId,
				p_reason: parsed.data.reason,
				p_actor_email: session.email
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
			'get_communication_message_recovery_queue'
		);
		if (queueError) throw queueError;

		return json({ result, ...((queue ?? {}) as Record<string, unknown>) }, { headers: noStore });
	} catch (error) {
		console.error('Could not act on a stuck message.', error);
		return json({ error: 'The message could not be updated.' }, { status: 500, headers: noStore });
	}
};
