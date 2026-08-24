import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { logoUploadSchema } from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { buildOrganizationLogoObjectKey, createPresignedUploadUrl } from '$lib/server/storage/r2';

const UPLOAD_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

// Hands back a short-lived slot to put the image in. Nothing is saved yet: the key only becomes this
// organization's logo when PUT /api/settings/branding/logo commits it, and that step checks what
// actually arrived.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-logo-upload:${organizationId}`,
			...UPLOAD_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = logoUploadSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const objectKey = buildOrganizationLogoObjectKey(organizationId, parsed.data.file_name);

	let uploadUrl: string;
	try {
		uploadUrl = await createPresignedUploadUrl(objectKey, parsed.data.mime_type);
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}

	return json({ upload_url: uploadUrl, object_key: objectKey }, { headers: NO_STORE_HEADERS });
};
