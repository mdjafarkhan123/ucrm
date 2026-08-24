import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { settingsWriteError } from '$lib/server/settings/errors';
import { organizationLogoUrl } from '$lib/server/settings/logo';
import {
	LOGO_MAX_BYTES,
	LOGO_MIME_TYPES,
	logoCommitSchema
} from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { deleteObject, headObject } from '$lib/server/storage/r2';

const LOGO_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

// A replaced logo is kept, not deleted. Published customer documents do not yet record which logo they
// were sent with, so deleting the old object would quietly change a proposal somebody already received.
// Once documents carry that reference, the rule becomes: keep everything a document names, and sweep
// unreferenced uploads after a grace period.
async function discardAbandonedUpload(objectKey: string) {
	try {
		await deleteObject(objectKey);
	} catch (error) {
		console.error('Could not remove a rejected logo upload.', error);
	}
}

export const PUT: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-logo-commit:${organizationId}`,
			...LOGO_LIMIT
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

	const parsed = logoCommitSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// The key was issued by the presign step and carries the organization it was issued for. The database
	// checks this too; refusing here means the caller gets a sentence rather than a raw constraint.
	if (!parsed.data.object_key.startsWith(`${organizationId}/logo/`))
		return validationError({ object_key: 'That upload was not made for this business.' });

	// A presigned URL is a window to put any bytes at that key, and this image is served inline from our
	// own origin afterwards. So we ask storage what actually landed there before trusting it.
	let uploaded;
	try {
		uploaded = await headObject(parsed.data.object_key);
	} catch {
		return validationError({ object_key: 'That upload did not finish. Try again.' });
	}

	const contentType = uploaded.contentType ?? '';
	if (!(LOGO_MIME_TYPES as readonly string[]).includes(contentType)) {
		await discardAbandonedUpload(parsed.data.object_key);
		return validationError({ object_key: 'Upload a PNG, JPG, or WEBP image.' });
	}
	if ((uploaded.contentLength ?? 0) > LOGO_MAX_BYTES) {
		await discardAbandonedUpload(parsed.data.object_key);
		return validationError({ object_key: 'Logos have to be under 2 MB.' });
	}

	const { data, error } = await event.locals.supabase.rpc('set_organization_logo', {
		target_organization_id: organizationId,
		new_object_key: parsed.data.object_key
	});
	if (error) return settingsWriteError(error);

	const result = data as { branding_revision: number };

	return json(
		{
			branding_revision: result.branding_revision,
			logo_url: organizationLogoUrl(result.branding_revision)
		},
		{ headers: NO_STORE_HEADERS }
	);
};

export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.business.edit');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-logo-commit:${organizationId}`,
			...LOGO_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	const { data, error } = await event.locals.supabase.rpc('remove_organization_logo', {
		target_organization_id: organizationId
	});
	if (error) return settingsWriteError(error);

	const result = data as { branding_revision: number };

	return json(
		{ branding_revision: result.branding_revision, logo_url: null },
		{ headers: NO_STORE_HEADERS }
	);
};
