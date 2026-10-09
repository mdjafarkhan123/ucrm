import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { ActivityReport } from '$lib/jafar/activity-report';

// Jafar business management C3: the activity report for one period (plan § 6). Anyone who can open Leads sees the
// whole business's numbers; the days run in the viewer's own time zone. The front-door gate checks the Leads area.

const rangeSchema = z
	.object({ from: z.iso.date().nullable(), to: z.iso.date() })
	.refine((range) => range.from === null || range.from <= range.to);

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const range = rangeSchema.safeParse({
		from: event.url.searchParams.get('from'),
		to: event.url.searchParams.get('to')
	});
	if (!range.success) return json({ error: 'The dates are invalid.' }, { status: 422 });

	const { data, error } = await getOwnerSupabaseClient().rpc('owner_activity_report', {
		// The generated types cannot say a date argument takes null; null means from the first activity.
		from_date: range.data.from as string,
		to_date: range.data.to,
		viewer_member_id: session.memberId ?? undefined
	});
	if (error) {
		console.error('Could not load the activity report.', error);
		return json({ error: 'The report could not be loaded.' }, { status: 500 });
	}
	return json(data as unknown as ActivityReport, { headers: PRIVATE_READ_HEADERS });
};
