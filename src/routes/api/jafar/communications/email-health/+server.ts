import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import {
	communicationEmailSendingPauseSchema,
	zodOwnerFieldErrors
} from '$lib/server/validation/owner.schema';

async function loadHealth() {
	const { data, error } = await getOwnerSupabaseClient().rpc(
		'get_communication_email_sending_health'
	);
	if (error) throw error;
	return data;
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	try {
		return json({ health: await loadHealth() }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not load email sending health.', error);
		return json({ error: 'Email sending health could not be loaded.' }, { status: 500 });
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

	const parsed = communicationEmailSendingPauseSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the pause details.',
				field_errors: zodOwnerFieldErrors(parsed.error)
			},
			{ status: 422 }
		);
	}

	try {
		const client = getOwnerSupabaseClient();
		const { error } = await client.rpc('set_communication_email_platform_pause', {
			p_engage: parsed.data.engage,
			p_reason: parsed.data.reason,
			p_actor_email: session.email
		});
		if (error) {
			if (['23503', '23505', '23514'].includes(error.code ?? '')) {
				return json({ error: error.message }, { status: 409 });
			}
			throw error;
		}
		return json({ health: await loadHealth() }, { headers: { 'cache-control': 'no-store' } });
	} catch (error) {
		console.error('Could not change the platform email pause.', error);
		return json({ error: 'The platform email pause could not be changed.' }, { status: 500 });
	}
};
