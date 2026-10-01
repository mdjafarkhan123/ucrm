import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { SupportUnread } from '$lib/support/api';

// How many conversations are waiting unread for Uplift: the number on the Support menu item.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const { data, error } = await getOwnerSupabaseClient().rpc('support_inbox_unread_count');
	if (error) {
		console.error('Could not count unread support conversations.', error);
		return json({ error: 'The unread count could not be loaded.' }, { status: 500 });
	}

	const unread: SupportUnread = { unread: data ?? 0 };
	return json(unread, { headers: { 'cache-control': 'private, no-cache' } });
};
