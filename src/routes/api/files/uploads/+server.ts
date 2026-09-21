import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { linkedEntityBelongsToOrganization } from '$lib/server/access/collaboration';
import { databaseError, validationError } from '$lib/server/api/errors';
import { fileUploadStartSchema } from '$lib/server/validation/files.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { checkUploadClaim } from '$lib/server/files/upload-policy';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { buildFileObjectKey, createPresignedUploadUrl } from '$lib/server/storage/r2';

// Step one of an upload: agree what is coming, reserve a File for it, and hand back a short-lived URL the
// browser can put the bytes at. Nothing is usable yet -- the File is born pending and only the processing
// worker can promote it, after it has read the bytes that actually arrived.
export const POST: RequestHandler = async (event) => {
	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = fileUploadStartSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const access = await requireOrganizationPermission(event, 'files.manage');
	if ('response' in access) return access.response;
	const organizationId = access.auth.organization.id;

	// The allowlist, by name, declared type and declared size. The worker checks the bytes themselves
	// later; this is what stops us issuing a storage key for something we would never accept anyway.
	const claim = checkUploadClaim({
		fileName: parsed.data.file_name,
		mimeType: parsed.data.mime_type,
		sizeBytes: parsed.data.size_bytes
	});
	if (!claim.allowed) return validationError({ [claim.field]: claim.reason });

	// An upload that names a record must name one of this organization's records.
	if (parsed.data.origin_type !== 'file_manager' && parsed.data.origin_id) {
		const belongs = await linkedEntityBelongsToOrganization(
			event.locals.supabase,
			organizationId,
			parsed.data.origin_type,
			parsed.data.origin_id
		);
		if (!belongs) return validationError({ origin_id: 'That record was not found.' });
	}

	// Minted here, from this organization's id, and never taken from the request: register_pending_file
	// re-checks the prefix, so a key cannot be aimed at another tenant even by a caller holding this route.
	const objectKey = buildFileObjectKey(organizationId, parsed.data.file_name);

	let uploadUrl: string;
	try {
		uploadUrl = await createPresignedUploadUrl(objectKey, parsed.data.mime_type);
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}

	// `authenticated` holds no INSERT on public.files, by design: every write is a checked server command.
	const { data, error } = await getOwnerSupabaseClient().rpc('register_pending_file', {
		target_organization_id: organizationId,
		target_uploaded_by: access.auth.user.id,
		target_display_name: parsed.data.file_name,
		target_mime_type: parsed.data.mime_type,
		target_size_bytes: parsed.data.size_bytes,
		target_object_key: objectKey,
		target_origin_type: parsed.data.origin_type,
		// The function defaults both to null; `undefined` is how the generated client omits an argument.
		target_origin_id: parsed.data.origin_id ?? undefined,
		target_folder_id: parsed.data.folder_id ?? undefined
	});
	if (error) {
		console.error('Could not register a pending file.', error);
		return databaseError();
	}

	return json({ file: data, upload_url: uploadUrl }, { status: 201 });
};
