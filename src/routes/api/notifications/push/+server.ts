import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, unauthorized } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { vapidKeys } from '$lib/server/team/browser-alerts';
import {
	pushSubscriptionRemoveSchema,
	pushSubscriptionSchema
} from '$lib/server/validation/team-notifications.schema';

// The computers a person gets browser alerts on. A computer belongs to one person at a time: registering a
// browser another person registered before moves it to the new person (a shared office PC).
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const { data, error } = await getOwnerSupabaseClient()
		.from('push_subscriptions')
		.select('id, label, endpoint, created_at, last_success_at')
		.eq('user_id', auth.user.id)
		.order('created_at', { ascending: true });
	if (error) {
		console.error('Could not load registered computers.', error);
		return json({ error: 'Your computers could not be loaded.' }, { status: 500 });
	}
	return json(
		{ public_key: vapidKeys()?.publicKey ?? null, computers: data ?? [] },
		{ headers: PRIVATE_READ_HEADERS }
	);
};

export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const parsed = pushSubscriptionSchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) {
		return json(
			{ error: 'This browser did not give a usable alert address.' },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('register_push_subscription', {
		p_user_id: auth.user.id,
		p_endpoint: parsed.data.endpoint,
		p_p256dh: parsed.data.keys.p256dh,
		p_auth_secret: parsed.data.keys.auth,
		p_label: parsed.data.label
	});
	if (error) {
		if (error.code === '23514') {
			return json({ error: error.message }, { status: 409, headers: NO_STORE_HEADERS });
		}
		console.error('Could not register a computer for browser alerts.', error);
		return json(
			{ error: 'Browser alerts could not be turned on.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
	return json({ id: data }, { status: 201, headers: NO_STORE_HEADERS });
};

export const DELETE: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const parsed = pushSubscriptionRemoveSchema.safeParse(
		await event.request.json().catch(() => null)
	);
	if (!parsed.success) {
		return json(
			{ error: 'Choose a computer to remove.' },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	// Only the person's own computers can match, so another person's can never be removed here.
	let query = getOwnerSupabaseClient()
		.from('push_subscriptions')
		.delete()
		.eq('user_id', auth.user.id);
	query =
		'id' in parsed.data
			? query.eq('id', parsed.data.id)
			: query.eq('endpoint', parsed.data.endpoint);
	const { error } = await query;
	if (error) {
		console.error('Could not remove a computer.', error);
		return json(
			{ error: 'That computer could not be removed.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
	return json({ ok: true }, { headers: NO_STORE_HEADERS });
};
