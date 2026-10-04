import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError } from '$lib/server/api/errors';
import { requireSetupReader } from '$lib/server/setup/access';
import { readOrganizationSetupCatalogue } from '$lib/server/setup/catalogue';
import { readClientSetupReviews } from '$lib/server/setup/client-review';
import { readSetupState, setupSummary } from '$lib/server/setup/read';

// The task list and the dashboard's setup card: every section's status and Uplift's review of it, overall
// progress, and the next useful thing to do. Owners and administrators only.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;
	const [catalogue, state, optOut] = await Promise.all([
		readOrganizationSetupCatalogue(event.locals.supabase, organizationId),
		readSetupState(event.locals.supabase, organizationId),
		// The signed-in person's own choice about reminder emails; each person reads only their own row.
		event.locals.supabase
			.from('organization_setup_reminder_opt_outs')
			.select('user_id')
			.eq('organization_id', organizationId)
			.eq('user_id', check.auth.user.id)
			.maybeSingle()
	]);
	if (!catalogue || !state || optOut.error) return databaseError();

	let reviews;
	try {
		reviews = await readClientSetupReviews(event.locals.supabase, organizationId, state, catalogue);
	} catch (error) {
		console.error('Could not read the setup review.', error);
		return databaseError();
	}

	return json(
		{ ...setupSummary(state, catalogue, reviews), reminder_emails_on: optOut.data === null },
		{ headers: PRIVATE_READ_HEADERS }
	);
};
