import type { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { teammatesWhoCan } from '$lib/server/jafar/team-choices';

// Jafar business management E3: who can host a sales call -- Jafar, and the teammates who can change Leads &
// Deals, the same people who can own a Lead. A booking becomes its host's call on their Lead, so the host must be
// able to work on it.

type Client = ReturnType<typeof getOwnerSupabaseClient>;

export const hostChoices = (client: Client) => teammatesWhoCan(client, 'leads', 'work');

/** The teammate ids among `ids` who cannot host (not active, or no Leads & Deals change access). */
export async function unqualifiedHosts(client: Client, ids: (string | null)[]) {
	const teammates = ids.filter((id): id is string => id !== null);
	if (teammates.length === 0) return [];
	const qualified = new Set((await hostChoices(client)).map((choice) => choice.id));
	return teammates.filter((id) => !qualified.has(id));
}

export const HOST_REFUSED = 'A host you chose cannot change Leads & Deals. Change their access first.';
