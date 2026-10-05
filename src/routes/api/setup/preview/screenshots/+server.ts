import type { RequestHandler } from './$types';
import { validationError } from '$lib/server/api/errors';
import {
	requireSetupEditor,
	requireSetupReader,
	setupWriteLimited
} from '$lib/server/setup/access';
import {
	previewScreenshotResponse,
	previewUploadTicketResponse
} from '$lib/server/setup/preview-screenshots';
import { setupPreviewScreenshotPresignSchema } from '$lib/server/validation/setup.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';

// Client onboarding E3: a screenshot on the preview — shown to the client's owners and administrators (GET
// `?key=`, `&size=thumb` for the small copy), or somewhere to upload one for a note (POST).
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;
	return previewScreenshotResponse(check.auth.organization.id, event.url);
};

export const POST: RequestHandler = async (event) => {
	const check = await requireSetupEditor(event);
	if ('response' in check) return check.response;
	const organizationId = check.auth.organization.id;

	const limited = await setupWriteLimited(event, organizationId);
	if (limited) return limited;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = setupPreviewScreenshotPresignSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));
	return previewUploadTicketResponse(organizationId, parsed.data);
};
