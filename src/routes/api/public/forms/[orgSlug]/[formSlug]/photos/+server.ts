import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { resolvePublicForm } from '$lib/server/forms/public-resolver';
import { buildPublicFormSubmissionAttachmentObjectKey } from '$lib/server/storage/r2';
import {
	PUBLIC_FORM_PHOTO_MAX_COUNT,
	decodePublicFormPhoto,
	storePublicFormPhotoAt
} from '$lib/server/forms/public-submission-photo';

const NOT_AVAILABLE = { error: 'That form is not available.' };

const bodySchema = z.object({
	idempotency_key: z.string().trim().min(1).max(200),
	file_name: z.string().trim().max(200).optional(),
	photo: z.string().min(1)
});

// One photo per request, server-proxied rather than presigned -- an anonymous stranger is the one upload
// class this app never hands a direct-to-storage window to (see public-submission-photo.ts). The
// idempotency-key-scoped rate limit is what actually caps how many photos one visit can attach: at most
// PUBLIC_FORM_PHOTO_MAX_COUNT, matching submit_form_response's own max_photos.
export const POST: RequestHandler = async (event) => {
	const client = getOwnerSupabaseClient();
	const clientAddress = event.getClientAddress();
	const { orgSlug, formSlug } = event.params;

	const resolved = await resolvePublicForm(client, orgSlug, formSlug);
	if (!resolved) return json(NOT_AVAILABLE, { status: 404 });
	if (!resolved.content.photos.enabled) return json(NOT_AVAILABLE, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'That photo could not be read.' }, { status: 400 });
	}
	const parsed = bodySchema.safeParse(body);
	if (!parsed.success) return json({ error: 'That photo could not be read.' }, { status: 422 });

	const rateLimit = await checkRateLimit(client, {
		bucketKey: `public-form-photo:${resolved.formId}:${parsed.data.idempotency_key}`,
		windowSeconds: 3600,
		maxAttempts: PUBLIC_FORM_PHOTO_MAX_COUNT
	});
	if (!rateLimit.allowed) return rateLimitedResponse(rateLimit.retryAfterSeconds);

	// Also bounded by the IP itself, independent of whatever idempotency key a caller claims.
	const ipRateLimit = await checkRateLimit(client, {
		bucketKey: `public-form-photo-ip:${resolved.formId}:${clientAddress}`,
		windowSeconds: 3600,
		maxAttempts: PUBLIC_FORM_PHOTO_MAX_COUNT * 3
	});
	if (!ipRateLimit.allowed) return rateLimitedResponse(ipRateLimit.retryAfterSeconds);

	const decoded = decodePublicFormPhoto(parsed.data.photo);
	if (!decoded)
		return json(
			{ error: 'That photo could not be used. Try a PNG, JPEG, or WebP file.' },
			{ status: 422 }
		);

	const objectKey = buildPublicFormSubmissionAttachmentObjectKey(
		resolved.organizationId,
		resolved.formId,
		parsed.data.file_name ?? 'photo'
	);

	try {
		await storePublicFormPhotoAt(objectKey, decoded);
	} catch (error) {
		console.error('Could not store a public form photo.', error);
		return json({ error: 'That photo could not be uploaded. Please try again.' }, { status: 500 });
	}

	return json({ object_key: objectKey }, { status: 201 });
};
