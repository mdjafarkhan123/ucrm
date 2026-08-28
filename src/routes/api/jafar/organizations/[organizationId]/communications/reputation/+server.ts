import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema, zodAccessFieldErrors } from '$lib/server/validation/access.schema';
import {
	communicationEmailReputationOverrideSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

async function loadReputation(organizationId: string) {
	const { data, error } = await getOwnerSupabaseClient().rpc('get_communication_email_reputation', {
		p_organization_id: organizationId
	});
	if (error) throw error;
	return data;
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json({ error: 'The organization identifier is invalid.' }, { status: 422 });
	}

	try {
		return json(
			{ reputation: await loadReputation(parsedOrganizationId.data) },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not load the organization email reputation.', error);
		return json({ error: 'The email reputation could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	const parsedOrganizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!parsedOrganizationId.success) {
		return json(
			{
				error: 'The organization identifier is invalid.',
				field_errors: zodAccessFieldErrors(parsedOrganizationId.error)
			},
			{ status: 422 }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationEmailReputationOverrideSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the override details.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		// Postgres cannot express argument nullability, so the generated Args type reads every
		// threshold field as required. Null is what "leave this one alone" means to the command.
		const { data, error } = await client.rpc('set_communication_email_reputation_threshold', {
			p_scope: 'organization',
			p_organization_id: parsedOrganizationId.data,
			p_signal: parsed.data.signal,
			p_window_key: parsed.data.window_key,
			p_window_hours: null,
			p_warn_rate: parsed.data.warn_rate,
			p_pause_rate: parsed.data.pause_rate,
			p_min_sample_recipients: parsed.data.min_sample_recipients,
			p_min_event_count: parsed.data.min_event_count,
			p_reason: parsed.data.reason,
			p_actor_email: session.email
		} as never);
		if (error) {
			if (error.code === '23503') {
				return json({ error: 'That organization was not found.' }, { status: 404 });
			}
			// An override that would weaken the platform ceiling comes back as a check violation whose
			// message names the field and the ceiling it broke.
			if (['23505', '23514'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		return json(
			{ result: data, reputation: await loadReputation(parsedOrganizationId.data) },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not change the organization reputation override.', error);
		return json({ error: 'The reputation override could not be changed.' }, { status: 500 });
	}
};
