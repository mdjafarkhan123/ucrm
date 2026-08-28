import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationEmailReputationPlatformThresholdSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

async function loadOverview() {
	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_communication_email_reputation_overview'
	);
	if (error) throw error;
	return data;
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	try {
		return json({ overview: await loadOverview() }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load the email reputation overview.', error);
		return json({ error: 'The email reputation overview could not be loaded.' }, { status: 500 });
	}
};

export const POST: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = communicationEmailReputationPlatformThresholdSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the threshold details.',
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
			p_scope: 'platform',
			p_organization_id: null,
			p_signal: parsed.data.signal,
			p_window_key: parsed.data.window_key,
			p_window_hours: parsed.data.window_hours,
			p_warn_rate: parsed.data.warn_rate,
			p_pause_rate: parsed.data.pause_rate,
			p_min_sample_recipients: parsed.data.min_sample_recipients,
			p_min_event_count: parsed.data.min_event_count,
			p_reason: parsed.data.reason,
			p_actor_email: session.email,
			p_confirm_platform_change: parsed.data.confirm_platform_change
		} as never);
		if (error) {
			// The command refuses an unconfirmed ceiling change and a value outside its bounds the same
			// way: a check violation carrying the sentence Jafar should read.
			if (['23503', '23505', '23514'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}

		return json(
			{ result: data, overview: await loadOverview() },
			{ headers: { 'cache-control': 'no-store' } }
		);
	} catch (error) {
		console.error('Could not change the platform reputation threshold.', error);
		return json({ error: 'The platform threshold could not be changed.' }, { status: 500 });
	}
};
