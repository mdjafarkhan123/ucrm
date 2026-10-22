import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import {
	chosenDocumentKinds,
	PAPERWORK_FILE_TYPES,
	PAPERWORK_MAX_FILE_BYTES,
	resolveDocumentChoices
} from '$lib/communications/number-paperwork';
import { allowedTypeFor } from '$lib/files/allowlist';
import { getSmsCountryCatalog } from '$lib/server/communications/sms-country-catalog';
import { loadPaperworkForm } from '$lib/server/communications/sms-number-paperwork';
import { readPaperwork } from '$lib/server/communications/sms-number-paperwork-api';
import { buildProtectedDocumentObjectKey, createPresignedUploadUrl } from '$lib/server/storage/r2';
import {
	paperworkFieldErrors,
	paperworkUploadSchema
} from '$lib/server/validation/communications-sms-paperwork.schema';

// Every paperwork file is a protected document under this one question key: private, virus-checked, and held
// by the paperwork document that names it (20261223090000).
const FACT_KEY = 'texting.number_paperwork';

// Step one of adding a document file: reserve it under the business's protected prefix and hand back a
// short-lived upload URL. The browser then reports the upload finished (documents/[fileId]/complete) and the
// virus check takes it from there. A new file replaces the document's old one.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationAdmin(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;
	const id = z.uuid().safeParse(event.params.paperworkId);
	if (!id.success) {
		return json(
			{ error: 'That paperwork was not found.' },
			{ status: 404, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}
	const parsed = paperworkUploadSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{ error: 'Please review the file.', field_errors: paperworkFieldErrors(parsed.error) },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const organizationId = check.auth.organization.id;
	const client = getOwnerSupabaseClient();
	const loaded = await readPaperwork(client, organizationId, id.data).catch(() => null);
	if (!loaded) {
		return json(
			{ error: 'That paperwork was not found.' },
			{ status: 404, headers: NO_STORE_HEADERS }
		);
	}
	const { paperwork } = loaded;
	if (paperwork.status !== 'draft' && paperwork.status !== 'needs_fix') {
		return json(
			{ error: 'This paperwork is with the phone company and can’t be changed now.' },
			{ status: 409, headers: NO_STORE_HEADERS }
		);
	}

	let form;
	try {
		form = (
			await loadPaperworkForm(getSmsCountryCatalog(), {
				countryCode: paperwork.countryCode,
				numberType: paperwork.numberType,
				endUserType: paperwork.endUserType
			})
		).form;
	} catch {
		return json(
			{ error: 'We couldn’t reach the phone company. Try again in a minute.' },
			{ status: 503, headers: NO_STORE_HEADERS }
		);
	}
	const choices = resolveDocumentChoices(form.requirements, paperwork.documentChoices);
	const kind = chosenDocumentKinds(form.requirements, choices).find(
		(candidate) => candidate.documentType === parsed.data.document_type
	);
	if (!kind?.needsFile) return validationError({ document_type: 'This document takes no file.' });

	const type = allowedTypeFor(parsed.data.file_name, PAPERWORK_FILE_TYPES);
	if (!type) return validationError({ file_name: 'Add a PDF, JPG or PNG.' });
	const claimed = parsed.data.mime_type.toLowerCase();
	if (claimed && !type.mimeTypes.includes(claimed)) {
		return validationError({ mime_type: 'That file type does not match the file name.' });
	}
	if (parsed.data.size_bytes > PAPERWORK_MAX_FILE_BYTES) {
		return validationError({ size_bytes: 'The phone company takes files up to 5 MB.' });
	}
	const mimeType = type.mimeTypes[0];

	const objectKey = buildProtectedDocumentObjectKey(organizationId, parsed.data.file_name);
	let uploadUrl: string;
	try {
		uploadUrl = await createPresignedUploadUrl(objectKey, mimeType);
	} catch {
		return json(
			{ error: 'File storage is not available right now. Try again in a moment.' },
			{ status: 503, headers: NO_STORE_HEADERS }
		);
	}

	const { data: file, error } = await client.rpc('register_setup_protected_document', {
		target_organization_id: organizationId,
		target_uploaded_by: check.auth.user.id,
		target_fact_key: FACT_KEY,
		target_display_name: parsed.data.file_name,
		target_mime_type: mimeType,
		target_size_bytes: parsed.data.size_bytes,
		target_object_key: objectKey
	});
	if (error || !file) {
		if (error?.code === '23514') return validationError({ file_name: error.message });
		console.error('Could not register a paperwork file.', error);
		return databaseError();
	}

	const { error: linkError } = await client
		.from('communication_sms_number_paperwork_documents')
		.upsert(
			{
				organization_id: organizationId,
				paperwork_id: paperwork.id,
				document_type: kind.documentType,
				protected_document_id: file.id,
				updated_at: new Date().toISOString()
			},
			{ onConflict: 'paperwork_id,document_type' }
		);
	if (linkError) {
		console.error('Could not link a paperwork file.', linkError);
		return databaseError();
	}

	// The browser sends the bytes with exactly this type, or storage refuses the signed upload.
	return json(
		{ file_id: file.id, mime_type: mimeType, upload_url: uploadUrl },
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};
