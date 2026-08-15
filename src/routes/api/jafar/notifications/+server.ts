import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { notificationListQuerySchema } from '$lib/server/validation/notification.schema';

const notificationSelect =
	'id, correlation_id, kind, severity, title, body, target_kind, target_id, read_at, created_at';

const DEFAULT_LIMIT = 50;

/**
 * PostgREST's `or` filter is comma/parenthesis delimited, so those characters in a search
 * term would change the meaning of the filter rather than be matched literally. `%` and `_`
 * are ilike wildcards. Stripping all of them keeps the search a plain contains-this-text
 * search, which is all the history page offers.
 */
function sanitizeSearch(term: string) {
	return term.replace(/[,()%_\\*]/g, ' ').trim();
}

export const GET: RequestHandler = async (event) => {
	if (!await getOwnerSession(event)) return ownerUnauthorized();

	const parsed = notificationListQuerySchema.safeParse({
		status: event.url.searchParams.get('status') ?? undefined,
		search: event.url.searchParams.get('search') ?? undefined,
		limit: event.url.searchParams.get('limit') ?? undefined
	});
	if (!parsed.success)
		return json({ error: 'The notification filter is invalid.' }, { status: 422 });

	const client = getOwnerSupabaseClient();
	const search = parsed.data.search ? sanitizeSearch(parsed.data.search) : '';

	try {
		let query = client
			.from('platform_owner_notifications')
			.select(notificationSelect)
			.order('created_at', { ascending: false })
			.limit(parsed.data.limit ?? DEFAULT_LIMIT);

		if (parsed.data.status !== 'all') query = query.is('read_at', null);
		if (search) query = query.or(`title.ilike.%${search}%,body.ilike.%${search}%`);

		// The unread count is always the true total, never the length of the page above, so the
		// bell keeps telling the truth when there are more unread items than one page holds.
		const [listResult, countResult] = await Promise.all([
			query,
			client
				.from('platform_owner_notifications')
				.select('id', { count: 'exact', head: true })
				.is('read_at', null)
		]);

		if (listResult.error) throw listResult.error;
		if (countResult.error) throw countResult.error;

		return json({
			notifications: listResult.data ?? [],
			unread_count: countResult.count ?? 0
		});
	} catch (error) {
		console.error('Could not load notifications.', error);
		return json({ error: 'Notifications could not be loaded.' }, { status: 500 });
	}
};
