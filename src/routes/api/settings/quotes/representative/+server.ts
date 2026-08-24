import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { isStale, settingsWriteError, staleSettingsResponse } from '$lib/server/settings/errors';
import {
	decodeSignatureImage,
	discardRepresentativeSignature,
	organizationQuoteRepresentativeSignatureUrl,
	storeDrawnRepresentativeSignature
} from '$lib/server/settings/quote-representative-signature';
import {
	QUOTE_REPRESENTATIVE_SIGNATURE_MAX_BYTES,
	QUOTE_REPRESENTATIVE_SIGNATURE_MIME_TYPES,
	quoteRepresentativeSchema
} from '$lib/server/validation/settings.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { headObject } from '$lib/server/storage/r2';

const SAVE_LIMIT = { windowSeconds: 60, maxAttempts: 20 };

async function discardRejectedUpload(objectKey: string) {
	try {
		await discardRepresentativeSignature(objectKey);
	} catch (error) {
		console.error('Could not remove a rejected representative signature upload.', error);
	}
}

// Enable/name/title always save. The signature image resolves from exactly one of three inputs: a
// previously-uploaded object key (committed here, same "ask storage what actually landed" check the logo
// uses), a freshly drawn data URL (decoded and stored the same way a Quote signature is), or an explicit
// `remove_signature`, which clears it. Omitting all three means the caller is not touching the signature at
// all (e.g. saving only a name/title edit) — the current key is re-read from the row and resent unchanged,
// because the GET route deliberately never sends the raw key to the browser (see its own comment), so the
// browser has nothing to resend on its own. A previously-saved image is never deleted on replace: the block
// is copied into every new Quote draft by the same object key, so an old key can already be the one thing a
// historical draft points at — same reasoning the logo's own "kept, not deleted" comment gives, just true
// from day one here instead of "once documents carry the reference."
export const PATCH: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.quotes.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `settings-quotes-representative:${organizationId}`,
			...SAVE_LIMIT
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

	const parsed = quoteRepresentativeSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	let signatureObjectKey: string | null = null;

	if (parsed.data.remove_signature) {
		signatureObjectKey = null;
	} else if (parsed.data.signature_image) {
		const image = decodeSignatureImage(parsed.data.signature_image);
		if (!image) return validationError({ signature_image: 'That signature could not be read.' });

		try {
			signatureObjectKey = await storeDrawnRepresentativeSignature(organizationId, image);
		} catch {
			console.error('A representative signature could not be stored.');
			return json({ error: 'That signature could not be saved.' }, { status: 500 });
		}
	} else if (parsed.data.signature_object_key) {
		const objectKey = parsed.data.signature_object_key;
		if (!objectKey.startsWith(`${organizationId}/quote-representative-signature/`)) {
			return validationError({
				signature_object_key: 'That upload was not made for this business.'
			});
		}

		let uploaded;
		try {
			uploaded = await headObject(objectKey);
		} catch {
			return validationError({ signature_object_key: 'That upload did not finish. Try again.' });
		}

		const contentType = uploaded.contentType ?? '';
		if (!(QUOTE_REPRESENTATIVE_SIGNATURE_MIME_TYPES as readonly string[]).includes(contentType)) {
			await discardRejectedUpload(objectKey);
			return validationError({ signature_object_key: 'Upload a PNG, JPG, or WEBP image.' });
		}
		if ((uploaded.contentLength ?? 0) > QUOTE_REPRESENTATIVE_SIGNATURE_MAX_BYTES) {
			await discardRejectedUpload(objectKey);
			return validationError({ signature_object_key: 'Signature images have to be under 1 MB.' });
		}

		signatureObjectKey = objectKey;
	} else {
		const { data: current, error: currentError } = await event.locals.supabase
			.from('organization_settings')
			.select('quote_representative_signature_object_key')
			.eq('organization_id', organizationId)
			.maybeSingle();
		if (currentError) return databaseError();
		signatureObjectKey = current?.quote_representative_signature_object_key ?? null;
	}

	const { data, error } = await event.locals.supabase.rpc('set_organization_quote_representative', {
		target_organization_id: organizationId,
		expected_revision: parsed.data.expected_revision,
		new_enabled: parsed.data.enabled,
		new_name: parsed.data.name,
		new_title: parsed.data.title,
		new_signature_object_key: signatureObjectKey
	});

	if (error) {
		if (signatureObjectKey && parsed.data.signature_image) {
			// Only a signature we just wrote for this request is safe to discard on refusal — a resent
			// existing object key belongs to the previous save and must survive a refused request.
			await discardRejectedUpload(signatureObjectKey);
		}
		return settingsWriteError(error);
	}
	if (isStale(data)) return staleSettingsResponse(data);

	// Shaped explicitly rather than spreading the RPC's raw result: that result carries internal storage
	// keys (the new object key and the previous one, kept only so a caller could log it) that the client
	// has no use for and should never see — same reasoning the logo route already follows, returning a URL
	// and never the object key underneath it.
	const result = data as {
		quote_representative_revision: number;
		quote_representative_enabled: boolean;
		quote_representative_name: string | null;
		quote_representative_title: string | null;
		quote_representative_signature_object_key: string | null;
	};

	return json(
		{
			revision: result.quote_representative_revision,
			enabled: result.quote_representative_enabled,
			name: result.quote_representative_name,
			title: result.quote_representative_title,
			signature_url: result.quote_representative_signature_object_key
				? organizationQuoteRepresentativeSignatureUrl(result.quote_representative_revision)
				: null
		},
		{ headers: NO_STORE_HEADERS }
	);
};
