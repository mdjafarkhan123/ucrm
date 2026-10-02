import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { getOwnerSession } from '$lib/server/auth/owner';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { supportAttachmentResponse } from '$lib/server/support/attachments';

const NOT_FOUND = { error: 'That file could not be found.' };

// A file from any contractor's chat, for the Support Inbox.
export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();

	const id = z.string().uuid().safeParse(event.params.id);
	if (!id.success) return json(NOT_FOUND, { status: 404 });

	const { data: attachment, error } = await getOwnerSupabaseClient()
		.from('support_message_attachments')
		.select('object_key, file_name, mime_type, has_thumbnail')
		.eq('id', id.data)
		.maybeSingle();
	if (error) {
		console.error('Could not read a support attachment.', error);
		return json({ error: 'That file could not be loaded.' }, { status: 500 });
	}
	if (!attachment) return json(NOT_FOUND, { status: 404 });

	return supportAttachmentResponse(attachment, event.url);
};
