import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { fileShareTurnOffSchema } from '$lib/server/validation/files.schema';

// "Turn off" on a customer file share. Final: a share never comes back on, and more time is a new share.
// The customer's link then shows that it is no longer active, with the business's phone and email.
export const POST: RequestHandler = async (event) => {
	const parsed = fileShareTurnOffSchema.safeParse({ id: event.params.id });
	if (!parsed.success) return notFound('That link was not found.');

	const access = await requireOrganizationPermission(event, 'files.share');
	if ('response' in access) return access.response;

	// Read under the caller's own policies first, so the service-role call below can only ever reach a
	// share this member could already see.
	const visible = await event.locals.supabase
		.from('file_shares')
		.select('id')
		.eq('id', parsed.data.id)
		.maybeSingle();
	if (visible.error) {
		console.error('Could not check a file share before turning it off.', visible.error);
		return databaseError();
	}
	if (!visible.data) return notFound('That link was not found.');

	const { data, error } = await getOwnerSupabaseClient().rpc('turn_off_file_share', {
		target_organization_id: access.auth.organization.id,
		target_actor_id: access.auth.user.id,
		target_share_id: parsed.data.id
	});
	if (error) {
		if (error.code === 'P0002') return notFound('That link was not found.');
		console.error('Could not turn off a file share.', { code: error.code, message: error.message });
		return databaseError();
	}

	return json({ share: data }, { headers: NO_STORE_HEADERS });
};
