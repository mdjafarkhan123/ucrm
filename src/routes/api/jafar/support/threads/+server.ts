import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSupportInbox, readSupportSettings } from '$lib/server/support/inbox';
import { supportThreadQuerySchema } from '$lib/server/validation/support.schema';

// The Support Inbox: every contractor's conversation with Uplift, newest activity first, plus how Uplift
// currently appears to them. Separate from any tenant's customer inbox.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const parsed = supportThreadQuerySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined
	});
	if (!parsed.success) return json({ error: 'The inbox filter is invalid.' }, { status: 422 });

	try {
		const client = getOwnerSupabaseClient();
		const [inbox, settings] = await Promise.all([
			readSupportInbox(client, parsed.data.limit),
			readSupportSettings(client)
		]);
		return json({ ...inbox, settings });
	} catch (error) {
		console.error('Could not load the Support Inbox.', error);
		return json({ error: 'The Support Inbox could not be loaded.' }, { status: 500 });
	}
};
