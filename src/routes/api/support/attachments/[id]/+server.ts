import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { databaseError } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { supportAttachmentResponse } from '$lib/server/support/attachments';

const NOT_FOUND = { error: 'That file could not be found.' };

// A file from a chat the member can see. Row level security decides: a file is visible exactly when its
// chat is, so one from a hidden chat reads like one that does not exist.
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const id = z.string().uuid().safeParse(event.params.id);
	if (!id.success) return json(NOT_FOUND, { status: 404 });

	const { data: attachment, error } = await event.locals.supabase
		.from('support_message_attachments')
		.select('object_key, file_name, mime_type, has_thumbnail')
		.eq('organization_id', check.auth.organization.id)
		.eq('id', id.data)
		.maybeSingle();
	if (error) return databaseError();
	if (!attachment) return json(NOT_FOUND, { status: 404 });

	return supportAttachmentResponse(attachment, event.url);
};
