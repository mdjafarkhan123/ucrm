import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, validationError } from '$lib/server/api/errors';
import { fileTrashSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

// Moving one File to Trash. Any File can go, wherever it is used -- the behavior contract's warning grows
// with how the File is used, and the strongest one asks for an explicit tick before a customer's copy is
// touched. The dialog is what says the consequence in plain words; this route only carries the answer.
export const POST: RequestHandler = async (event) => {
	const fileId = event.params.id;
	if (!/^[0-9a-f-]{36}$/i.test(fileId)) return validationError({ id: 'That file was not found.' });

	let body: unknown = {};
	try {
		body = await event.request.json();
	} catch {
		// An empty body is the ordinary case -- most Trash confirms carry no acknowledgement at all.
	}
	const parsed = fileTrashSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// Its own permission, separate from files.manage: sales and finance browse the library and attach from
	// it, but nobody makes a file disappear from other people's jobs by accident.
	const access = await requireOrganizationPermission(event, 'files.trash');
	if ('response' in access) return access.response;

	const { data, error } = await getOwnerSupabaseClient().rpc('trash_file', {
		target_organization_id: access.auth.organization.id,
		target_file_id: fileId,
		target_actor_id: access.auth.user.id,
		acknowledge_customer_copies: parsed.data.acknowledge_customer_copies
	});
	if (error) {
		if (error.code === 'P0002') return json({ error: 'That file was not found.' }, { status: 404 });
		// The customer-copy warning: refused until the contractor ticks "I understand" and sends it again.
		if (error.code === 'P0412') return json({ error: error.message }, { status: 409 });
		console.error('Could not move a file to Trash.', error);
		return databaseError();
	}

	return json({ file: data });
};
