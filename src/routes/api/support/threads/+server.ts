import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { readTeamThreads } from '$lib/server/support/team';
import type { SupportTeamThreads } from '$lib/support/api';

// "Team chats": conversations other than the member's own that they may see (D3).
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	try {
		const threads = await readTeamThreads(
			event.locals.supabase,
			check.auth.organization.id,
			check.auth.user.id
		);
		const body: SupportTeamThreads = { threads };
		return json(body, { headers: PRIVATE_READ_HEADERS });
	} catch {
		return databaseError();
	}
};
