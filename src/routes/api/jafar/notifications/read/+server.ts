import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { notificationReadSchema } from '$lib/server/validation/notification.schema';

/**
 * Read state is the only thing a notification's row allows to change (the database trigger
 * rejects everything else), so this route is safe to call freely from the bell, the history
 * page, and from simply opening a linked record.
 */
export const POST: RequestHandler = async (event) => {
	if (!await getOwnerSession(event)) return ownerUnauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'The request could not be read.' }, { status: 400 });
	}

	const parsed = notificationReadSchema.safeParse(body);
	if (!parsed.success) return json({ error: 'The read request is invalid.' }, { status: 422 });

	const client = getOwnerSupabaseClient();

	try {
		if ('all' in parsed.data) {
			const { error } = await client
				.from('platform_owner_notifications')
				.update({ read_at: new Date().toISOString() })
				.is('read_at', null);
			if (error) throw error;
			return json({ ok: true });
		}

		if ('target_kind' in parsed.data) {
			const { error } = await client
				.from('platform_owner_notifications')
				.update({ read_at: new Date().toISOString() })
				.eq('target_kind', parsed.data.target_kind)
				.eq('target_id', parsed.data.target_id)
				.is('read_at', null);
			if (error) throw error;
			return json({ ok: true });
		}

		const { error } = await client
			.from('platform_owner_notifications')
			.update({ read_at: parsed.data.read ? new Date().toISOString() : null })
			.in('id', parsed.data.ids);
		if (error) throw error;
		return json({ ok: true });
	} catch (error) {
		console.error('Could not update notification read state.', error);
		return json({ error: 'The notifications could not be updated.' }, { status: 500 });
	}
};
