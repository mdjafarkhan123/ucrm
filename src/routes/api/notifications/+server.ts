import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { PRIVATE_READ_HEADERS, unauthorized } from '$lib/server/api/errors';
import { loadNotificationLinks } from '$lib/server/team/inquiry-alerts';
import { teamNotificationHref, type TeamNotificationKind } from '$lib/team/notifications';

// The contractor header bell: the signed-in person's newest alerts and their true unread total. Row level
// security already limits the rows to the caller's own; the organization filter matches the indexes.
const PAGE_SIZE = 20;
// The badge shows "99+" past this, so counting further is wasted work.
const UNREAD_COUNT_CAP = 100;

export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const supabase = event.locals.supabase;
	const [list, unread] = await Promise.all([
		supabase
			.from('team_notifications')
			.select('id, kind, subject_type, subject_id, title, body, read_at, created_at')
			.eq('organization_id', auth.organization.id)
			.eq('user_id', auth.user.id)
			.order('created_at', { ascending: false })
			.order('id', { ascending: false })
			.limit(PAGE_SIZE),
		supabase
			.from('team_notifications')
			.select('id')
			.eq('organization_id', auth.organization.id)
			.eq('user_id', auth.user.id)
			.is('read_at', null)
			.limit(UNREAD_COUNT_CAP)
	]);

	if (list.error || unread.error) {
		console.error('Could not load team alerts.', list.error ?? unread.error);
		return json({ error: 'Alerts could not be loaded.' }, { status: 500 });
	}

	const rows = list.data ?? [];
	let links;
	try {
		links = await loadNotificationLinks(
			auth.organization.id,
			rows.map((row) => row.subject_id)
		);
	} catch (error) {
		console.error('Could not resolve team alert links.', error);
		return json({ error: 'Alerts could not be loaded.' }, { status: 500 });
	}

	return json(
		{
			notifications: rows.map((row) => ({
				id: row.id,
				kind: row.kind as TeamNotificationKind,
				title: row.title,
				body: row.body,
				href: teamNotificationHref(links.get(row.subject_id), row.subject_type, row.subject_id),
				read_at: row.read_at,
				created_at: row.created_at
			})),
			unread_count: unread.data?.length ?? 0
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};
