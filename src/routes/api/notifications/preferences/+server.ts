import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, PRIVATE_READ_HEADERS, unauthorized } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { alertPreferenceSchema } from '$lib/server/validation/team-notifications.schema';

// My alerts: the signed-in person's own Email and Browser switches. The database decides which alerts they can
// receive and every default, so this only passes their own identity through. Nobody reads or changes anyone
// else's switches.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const { data, error } = await getOwnerSupabaseClient().rpc('team_alert_settings', {
		p_organization_id: auth.organization.id,
		p_user_id: auth.user.id
	});
	if (error) {
		console.error('Could not load alert settings.', error);
		return json({ error: 'Your alert settings could not be loaded.' }, { status: 500 });
	}
	return json(data, { headers: PRIVATE_READ_HEADERS });
};

export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const parsed = alertPreferenceSchema.safeParse(await event.request.json().catch(() => null));
	if (!parsed.success) {
		return json(
			{ error: 'Choose an alert and a channel.' },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { error } = await getOwnerSupabaseClient().rpc('set_team_alert_preference', {
		p_organization_id: auth.organization.id,
		p_user_id: auth.user.id,
		p_kind: parsed.data.kind,
		p_channel: parsed.data.channel,
		p_enabled: parsed.data.enabled
	});
	if (error) {
		// 42501: this alert does not reach them (their access changed since the page loaded).
		if (error.code === '42501') {
			return json(
				{ error: 'You do not receive that alert.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		console.error('Could not save an alert setting.', error);
		return json(
			{ error: 'That alert setting could not be saved.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
	return json({ ok: true }, { headers: NO_STORE_HEADERS });
};
