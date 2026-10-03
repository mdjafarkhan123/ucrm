import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { supportUploadTicketResponse } from '$lib/server/support/attachments';
import { supportAttachmentPresignSchema } from '$lib/server/validation/support.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// Somewhere to upload one file for a chat Uplift is about to start (D5a). There is no chat yet, so the
// business names where it is stored: under that organization, beside its team's own support files.
export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const organizationId = z.string().uuid().safeParse(event.params.organizationId);
	if (!organizationId.success)
		return json({ error: 'That business could not be found.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
	}

	const parsed = supportAttachmentPresignSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'That file cannot be attached.', field_errors: zodOwnerFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const { data: organization, error } = await getOwnerSupabaseClient()
		.from('organizations')
		.select('id')
		.eq('id', organizationId.data)
		.maybeSingle();
	if (error) {
		console.error('Could not read a business for a support upload.', error);
		return json({ error: 'That file could not be uploaded.' }, { status: 500 });
	}
	if (!organization) return json({ error: 'That business could not be found.' }, { status: 404 });

	return supportUploadTicketResponse(organization.id, parsed.data);
};
