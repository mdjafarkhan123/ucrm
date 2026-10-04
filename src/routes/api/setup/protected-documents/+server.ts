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
import { readProtectedDocuments } from '$lib/server/setup/protected-documents';
import { buildProtectedDocumentObjectKey, createPresignedUploadUrl } from '$lib/server/storage/r2';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import {
	protectedDocumentUploadSchema,
	setupFileIdsSchema
} from '$lib/server/validation/setup.schema';
import { catalogueFacts } from '$lib/setup/catalogue';
import {
	PROTECTED_FILE_KINDS,
	setupFileFormats,
	setupFileKindsPhrase,
	setupFileType,
	setupFileTypes
} from '$lib/setup/files';

// Client onboarding B9a: the protected documents of a setup answer — a phone bill, a tax letter. Anyone who
// can see setup sees that each one arrived and whether it passed its checks; `can_open` says whether this
// person may open them, which only the business owner may (Jafar, 2026-10-04). Polled while one is checked.
export const GET: RequestHandler = async (event) => {
	const check = await requireSetupReader(event);
	if ('response' in check) return check.response;

	const ids = setupFileIdsSchema.safeParse(event.url.searchParams.get('ids') ?? '');
	if (!ids.success) return validationError({ ids: 'Name up to 20 files.' });

	try {
		const documents = await readProtectedDocuments(check.auth.organization.id, ids.data);
		return json(
			{ documents, can_open: check.auth.organization.role === 'owner' },
			{ headers: PRIVATE_READ_HEADERS }
		);
	} catch (error) {
		console.error('Could not read protected setup documents.', error);
		return databaseError();
	}
};

// Step one of adding a protected document: reserve it and hand back a short-lived URL for the bytes, under
// the organization's own protected prefix. The browser then reports the upload finished, and the virus check
// takes it from there.
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
	const parsed = protectedDocumentUploadSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	// The question as this client is asked it now, so a removed question or one outside their package takes nothing.
	const catalogue = await readOrganizationSetupCatalogue(event.locals.supabase, organizationId);
	if (!catalogue) return databaseError();
	const fact = catalogueFacts(catalogue).get(parsed.data.fact_key);
	if (fact?.kind !== 'protected_file')
		return validationError({ fact_key: 'This question does not take protected files.' });

	const type = setupFileType(parsed.data.file_name, PROTECTED_FILE_KINDS);
	if (!type)
		return validationError({
			file_name: `This question takes ${setupFileKindsPhrase(PROTECTED_FILE_KINDS)}: ${setupFileFormats(PROTECTED_FILE_KINDS)}.`
		});

	// One stored type per kind of file, whatever name this browser gives it; the bytes are checked later anyway.
	const claimed = parsed.data.mime_type.toLowerCase();
	if (claimed && !type.mimeTypes.includes(claimed))
		return validationError({ mime_type: 'That file type does not match the file name.' });
	const mimeType = type.mimeTypes[0];

	const verdict = checkUploadClaim(
		{ fileName: parsed.data.file_name, mimeType, sizeBytes: parsed.data.size_bytes },
		setupFileTypes(PROTECTED_FILE_KINDS)
	);
	if (!verdict.allowed) return validationError({ [verdict.field]: verdict.reason });

	const objectKey = buildProtectedDocumentObjectKey(organizationId, parsed.data.file_name);
	let uploadUrl: string;
	try {
		uploadUrl = await createPresignedUploadUrl(objectKey, mimeType);
	} catch {
		return json(
			{ error: 'File storage is not available right now. Try again in a moment.' },
			{ status: 503 }
		);
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('register_setup_protected_document', {
		target_organization_id: organizationId,
		target_uploaded_by: check.auth.user.id,
		target_fact_key: parsed.data.fact_key,
		target_display_name: parsed.data.file_name,
		target_mime_type: mimeType,
		target_size_bytes: parsed.data.size_bytes,
		target_object_key: objectKey
	});
	if (error || !data) {
		if (error?.code === '23514') return validationError({ fact_key: error.message });
		console.error('Could not register a protected setup document.', error);
		return databaseError();
	}

	// The browser sends the bytes with exactly this type, or storage refuses the signed upload.
	return json(
		{ document_id: data.id, mime_type: mimeType, upload_url: uploadUrl },
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};
