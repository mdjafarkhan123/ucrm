import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { requireSetupReader } from '$lib/server/setup/access';
import { readSetupState, setupSummary } from '$lib/server/setup/read';

// The task list and the dashboard's setup card: every section's status, overall progress, and the next
// useful thing to do. Owners and administrators only.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const state = await readSetupState(event.locals.supabase, check.auth.organization.id);
	if (!state) return databaseError();

	return json(setupSummary(state), { headers: PRIVATE_READ_HEADERS });
};
