import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { requireSupportMember, supportSendLimited } from '$lib/server/support/access';
import { readMemberAttachments } from '$lib/server/support/attachments';
import { supportMemberMessageSchema } from '$lib/server/validation/support.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// A team member writes in a chat they can see. A new chat starts at POST /api/support/threads.
export const POST: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const limited = await supportSendLimited(event, check.auth.user.id);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = supportMemberMessageSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const files = await readMemberAttachments(check.auth.organization.id, parsed.data.attachments);
	if ('response' in files) return files.response;

	const { data, error } = await event.locals.supabase.rpc('send_support_message', {
		target_organization_id: check.auth.organization.id,
		target_thread_id: parsed.data.thread_id,
		message_body: parsed.data.body,
		message_client_id: parsed.data.client_message_id,
		message_attachments: files.attachments
	});
	if (error) {
		if (error.code === '42501')
			return json(
				{
					error: 'That conversation is not one you can write in.',
					reason: 'permission_denied'
				},
				{ status: 403 }
			);
		if (error.code === '23514')
			return validationError({ body: error.message ?? 'That message could not be sent.' });
		console.error('Could not send a support message.', error);
		return databaseError();
	}

	return json(data, { status: 201, headers: NO_STORE_HEADERS });
};
