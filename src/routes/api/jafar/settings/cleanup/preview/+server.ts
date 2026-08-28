import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * What an early permanent deletion would destroy right now for one closing organization: active reply
 * aliases, unfinished queued messages, and replies received since closure started. Read-only; it is
 * the same RPC the purge path reads, so the number the owner confirms against is the number that will
 * actually be lost. Prefetched on hover of the delete control on /jafar/settings/cleanup.
 */
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = event.url.searchParams.get('organization_id') ?? '';
	if (!UUID.test(organizationId)) {
		return json({ error: 'Choose a valid organization.' }, { status: 400 });
	}

	try {
		const client = getOwnerSupabaseClient();
		const { data, error } = await client.rpc('preview_organization_closure_impact', {
			target_organization_id: organizationId
		});
		if (error) throw error;
		return json({ impact: data });
	} catch (error) {
		console.error('Could not load the closure impact preview.', error);
		return json({ error: 'The deletion impact could not be loaded.' }, { status: 500 });
	}
};
