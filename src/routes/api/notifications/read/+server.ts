import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { NO_STORE_HEADERS, unauthorized } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { teamNotificationReadSchema } from '$lib/server/validation/team-notifications.schema';

// Marks the caller's own alerts read: the ones they opened, or all of them. The database command is scoped to
// the signed-in person, so an id belonging to someone else simply changes nothing.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const body = await event.request.json().catch(() => null);
	const parsed = teamNotificationReadSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'The read request is invalid.' },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { error } = await getOwnerSupabaseClient().rpc('mark_team_notifications_read', {
		p_organization_id: auth.organization.id,
		p_user_id: auth.user.id,
		// Null means "all"; the generated types cannot express a nullable array argument.
		p_notification_ids: ('ids' in parsed.data ? parsed.data.ids : null) as string[]
	});
	if (error) {
		console.error('Could not mark team alerts read.', error);
		return json(
			{ error: 'Alerts could not be updated.' },
			{ status: 500, headers: NO_STORE_HEADERS }
		);
	}
	return json({ ok: true }, { headers: NO_STORE_HEADERS });
};
