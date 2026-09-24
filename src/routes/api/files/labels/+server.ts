import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getOrganizationContext } from '$lib/server/auth/organization';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { fileLabelSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// The organization's photo label list, alphabetical. Any member may read it -- a field member picking
// "Before" on a job photo needs the list, and a label name reveals nothing about a customer. It is capped at
// 100 by create_file_label, so it comes back whole.
export const GET: RequestHandler = async (event) => {
	const auth = await getOrganizationContext(event);
	if (!auth)
		return json({ error: 'Authentication or organization membership required.' }, { status: 401 });

	const { data, error } = await event.locals.supabase
		.from('file_labels')
		.select('id, name')
		.eq('organization_id', auth.organization.id)
		.order('name');
	if (error) {
		console.error('Could not list file labels.', error);
		return databaseError();
	}

	const labels = (data ?? []).sort((a, b) =>
		a.name.localeCompare(b.name, undefined, { sensitivity: 'base' })
	);
	return json({ labels }, { headers: PRIVATE_READ_HEADERS });
};

// One new label. Curating the list is files.manage, like folders; everyone else only picks from it.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fileLabelSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireOrganizationPermission(event, 'files.manage');
	if ('response' in access) return access.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('create_file_label', {
		target_organization_id: access.auth.organization.id,
		target_actor_id: access.auth.user.id,
		target_name: parsed.data.name
	});
	if (error) {
		if (error.code === '23505')
			return validationError({ name: 'You already have a label with that name.' });
		if (error.code === '23514') return validationError({ name: 'You can have up to 100 labels.' });
		console.error('Could not create a file label.', error);
		return databaseError();
	}

	return json({ label: { id: data.id, name: data.name } }, { status: 201 });
};
