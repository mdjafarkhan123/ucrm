import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	validationError
} from '$lib/server/api/errors';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { checkUploadClaim } from '$lib/server/files/upload-policy';
import { readOrganizationSetupCatalogue } from '$lib/server/setup/catalogue';
import {
	requireSetupEditor,
	requireSetupReader,
	setupWriteLimited
} from '$lib/server/setup/access';
import { readSetupFiles } from '$lib/server/setup/files';
import { buildFileObjectKey, createPresignedUploadUrl } from '$lib/server/storage/r2';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setupFileIdsSchema, setupFileUploadSchema } from '$lib/server/validation/setup.schema';
import { catalogueFacts } from '$lib/setup/catalogue';
import {
	setupFileFormats,
	setupFileKindsPhrase,
	setupFileType,
	setupFileTypes
} from '$lib/setup/files';

// Client onboarding A5c: the files of a photo or file answer, shown on the setup page. Polled while one is
// still being checked.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const ids = setupFileIdsSchema.safeParse(event.url.searchParams.get('ids') ?? '');
	if (!ids.success) return validationError({ ids: 'Name up to 20 files.' });

	try {
		const files = await readSetupFiles(check.auth.organization.id, ids.data);
		return json({ files }, { headers: PRIVATE_READ_HEADERS });
	} catch (error) {
		console.error('Could not read setup files.', error);
		return databaseError();
	}
};

// Step one of adding a file to a photo or file answer: the same handshake as the File library's upload
// (reserve a pending File, hand back a short-lived URL for the bytes), with the question's own rules in place
// of the library's. The answer names the File once the bytes have landed; the processing worker checks them.
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
	const parsed = setupFileUploadSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// The question as this client is asked it now, so a removed question or one outside their package takes nothing.
	const catalogue = await readOrganizationSetupCatalogue(event.locals.supabase, organizationId);
	if (!catalogue) return databaseError();
	const fact = catalogueFacts(catalogue).get(parsed.data.fact_key);
	if (!fact || fact.kind !== 'file')
		return validationError({ fact_key: 'This question does not take files.' });

	const kinds = fact.fileKinds ?? [];
	const type = setupFileType(parsed.data.file_name, kinds);
	if (!type)
		return validationError({
			file_name: `This question takes ${setupFileKindsPhrase(kinds)}: ${setupFileFormats(kinds)}.`
		});

	// One stored type per kind of file, whatever name this browser gives it; the bytes are checked later anyway.
	const claimed = parsed.data.mime_type.toLowerCase();
	if (claimed && !type.mimeTypes.includes(claimed))
		return validationError({ mime_type: 'That file type does not match the file name.' });
	const mimeType = type.mimeTypes[0];

	const verdict = checkUploadClaim(
		{ fileName: parsed.data.file_name, mimeType, sizeBytes: parsed.data.size_bytes },
		setupFileTypes(kinds)
	);
	if (!verdict.allowed) return validationError({ [verdict.field]: verdict.reason });

	const objectKey = buildFileObjectKey(organizationId, parsed.data.file_name);
	let uploadUrl: string;
	try {
		uploadUrl = await createPresignedUploadUrl(objectKey, mimeType);
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('register_pending_file', {
		target_organization_id: organizationId,
		target_uploaded_by: check.auth.user.id,
		target_display_name: parsed.data.file_name,
		target_mime_type: mimeType,
		target_size_bytes: parsed.data.size_bytes,
		target_object_key: objectKey,
		target_origin_type: 'organization',
		target_origin_id: organizationId,
		target_origin_role: 'setup_answer'
	});
	if (error || !data) {
		console.error('Could not register a setup file.', error);
		return databaseError();
	}

	// The browser sends the bytes with exactly this type, or storage refuses the signed upload.
	return json(
		{ file_id: data.id, mime_type: mimeType, upload_url: uploadUrl },
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};
