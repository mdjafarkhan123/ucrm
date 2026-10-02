import type { RequestHandler } from './$types';
import { validationError } from '$lib/server/api/errors';
import { requireSupportMember, supportUploadLimited } from '$lib/server/support/access';
import { supportUploadTicketResponse } from '$lib/server/support/attachments';
import { supportAttachmentPresignSchema } from '$lib/server/validation/support.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Somewhere to upload one file a team member is about to send to Uplift. The key is always under the
// member's own organization, so the message that names it can only be one of theirs.
export const POST: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const limited = await supportUploadLimited(event, check.auth.user.id);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = supportAttachmentPresignSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	return supportUploadTicketResponse(check.auth.organization.id, parsed.data);
};
