import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { supportUploadTicketResponse } from '$lib/server/support/attachments';
import { supportAttachmentPresignSchema } from '$lib/server/validation/support.schema';
import { zodOwnerFieldErrors } from '$lib/server/validation/owner.schema';

// Somewhere to upload one file Uplift is about to send. It is stored under the contractor's organization,
// beside the files their own team sent, so a chat's files live and leave together.
export const POST: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const threadId = z.string().uuid().safeParse(event.params.threadId);
	if (!threadId.success)
		return json({ error: 'That conversation could not be found.' }, { status: 404 });

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

	const { data: thread, error } = await getOwnerSupabaseClient()
		.from('support_threads')
		.select('organization_id')
		.eq('id', threadId.data)
		.maybeSingle();
	if (error) {
		console.error('Could not read a support conversation.', error);
		return json({ error: 'That file could not be uploaded.' }, { status: 500 });
	}
	if (!thread) return json({ error: 'That conversation no longer exists.' }, { status: 404 });

	return supportUploadTicketResponse(thread.organization_id, parsed.data);
};
