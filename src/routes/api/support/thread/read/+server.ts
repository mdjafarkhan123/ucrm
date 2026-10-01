import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { supportMemberReadSchema } from '$lib/server/validation/support.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// The member's screen showed their conversation up to `read_through`, so the badge clears.
export const POST: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = supportMemberReadSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { error } = await event.locals.supabase.rpc('mark_support_thread_read', {
		target_thread_id: parsed.data.thread_id,
		read_through: parsed.data.read_through
	});
	if (error) {
		if (error.code === '42501')
			return json(
				{ error: 'That conversation is not yours to mark as read.', reason: 'permission_denied' },
				{ status: 403 }
			);
		console.error('Could not mark a support conversation as read.', error);
		return databaseError();
	}

	return new Response(null, { status: 204, headers: NO_STORE_HEADERS });
};
