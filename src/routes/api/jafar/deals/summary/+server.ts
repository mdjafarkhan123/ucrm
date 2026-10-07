import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type { DealBoardSummary } from '$lib/jafar/deals';

// Jafar business management B4: every column's count and monthly total, and how many Deals are Lost.

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_deal_board_summary');
		if (error) throw error;
		return json(data as unknown as DealBoardSummary, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not load the Deals summary.', error);
		return json({ error: 'The board could not be loaded.' }, { status: 500 });
	}
};
