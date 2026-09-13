import { json } from '@sveltejs/kit';
import Papa from 'papaparse';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';

// Onboarding & Data Portability, Part 3, step 1: read a Price Book CSV and hand its rows straight back.
//
// No R2 storage and no batch row -- unlike the client importer, there is nothing to resume later. The
// browser holds the parsed rows in memory for the rest of the wizard and sends them back whole to Review and
// Commit. The size caps mirror Part 1's (same load boundary reasoning), even though a real price book is far
// smaller.
const MAX_FILE_BYTES = 2.5 * 1024 * 1024; // 2.5 MB
const MAX_DATA_ROWS = 5000;
const UPLOAD_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.price_book.manage');
	if ('response' in check) return check.response;

	const organizationId = check.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `price-book-import-upload:${organizationId}`,
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
			file: 'That file is not a CSV. Export your Price Book as CSV and try again.'
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

	return json({ headers, rows, row_count: rows.length }, { headers: NO_STORE_HEADERS });
};
