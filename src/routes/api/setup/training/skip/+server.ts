import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireSetupEditor, setupWriteError, setupWriteLimited } from '$lib/server/setup/access';

// Client onboarding E6 (plan §6): the business owner says "We don't need training". It settles the training
// requirement; the database refuses anyone but an active owner, and refuses once training is booked.

export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;
	if (check.auth.organization.role !== 'owner')
		return json(
			{ error: 'Only the business owner can say you don’t need training.', reason: 'owner_only' },
			{ status: 403 }
		);

	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	const { data, error } = await event.locals.supabase.rpc('client_skip_setup_training', {
		target_organization_id: organizationId
	});
	if (error) return setupWriteError(error);
	return json(data, { headers: NO_STORE_HEADERS });
};
