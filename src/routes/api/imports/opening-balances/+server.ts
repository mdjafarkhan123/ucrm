import { json } from '@sveltejs/kit';
import Papa from 'papaparse';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { buildOpeningBalanceImportObjectKey, putObject } from '$lib/server/storage/r2';

// Onboarding & Data Portability, Part 4, step 1: read an opening-balances CSV and remember it -- nothing is
// written to client_opening_balances yet. Mirrors the client importer's upload route exactly (same caps, same
// R2-then-batch-row shape); only the permission and destination differ, per the financial-reconciliation
// contract's write gate.
const MAX_FILE_BYTES = 2.5 * 1024 * 1024; // 2.5 MB
const MAX_DATA_ROWS = 5000;
const PREVIEW_ROW_COUNT = 20;
const UPLOAD_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `opening-balance-import-upload:${organizationId}`,
			...UPLOAD_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let form: FormData;
	try {
		form = await event.request.formData();
	} catch {
		return validationError({ form: 'Upload the file as form data.' });
	}

	const file = form.get('file');
	if (!(file instanceof File) || file.size === 0) {
		return validationError({ file: 'Choose a CSV file to import.' });
	}

	const isCsv =
		file.type === 'text/csv' ||
		file.type === 'application/vnd.ms-excel' ||
		file.name.toLowerCase().endsWith('.csv');
	if (!isCsv) {
		return validationError({
			file: 'That file is not a CSV. Export your opening balances as CSV and try again.'
		});
	}

	if (file.size > MAX_FILE_BYTES) {
		return validationError({
			file: 'That file is over 2.5 MB. Split it into smaller files and import them one at a time.'
		});
	}

	const text = await file.text();
	const parsed = Papa.parse<Record<string, string>>(text, {
		header: true,
		skipEmptyLines: 'greedy',
		transformHeader: (header) => header.trim()
	});

	const headers = parsed.meta.fields ?? [];
	if (headers.length === 0) {
		return validationError({
			file: 'That CSV has no header row. The first row must name the columns.'
		});
	}
	if (headers.some((header) => header.length === 0)) {
		return validationError({
			file: 'One of the columns has no name. Give every column a header and try again.'
		});
	}

	const rows = parsed.data;
	if (rows.length === 0) {
		return validationError({ file: 'That CSV has a header but no data rows.' });
	}
	if (rows.length > MAX_DATA_ROWS) {
		return validationError({
			file: `That file has ${rows.length.toLocaleString()} rows. Import at most ${MAX_DATA_ROWS.toLocaleString()} at a time — split it and import each part.`
		});
	}

	const objectKey = buildOpeningBalanceImportObjectKey(organizationId, file.name);
	try {
		await putObject(objectKey, new Uint8Array(await file.arrayBuffer()), 'text/csv');
	} catch {
		return json(
			{ error: 'File storage is not configured yet. Ask an admin to set up Cloudflare R2.' },
			{ status: 503 }
		);
	}

	const { data: batch, error } = await event.locals.supabase.rpc(
		'create_opening_balance_import_batch',
		{
			payload: {
				organization_id: organizationId,
				source_filename: file.name,
				storage_object_key: objectKey,
				file_row_count: rows.length
			}
		}
	);
	if (error) return databaseError();

	return json(
		{
			batch_id: batch.id,
			headers,
			preview_rows: rows.slice(0, PREVIEW_ROW_COUNT),
			row_count: rows.length
		},
		{ status: 201, headers: NO_STORE_HEADERS }
	);
};
