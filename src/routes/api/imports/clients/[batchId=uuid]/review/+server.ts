import { json } from '@sveltejs/kit';
import Papa from 'papaparse';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { getObjectBytes } from '$lib/server/storage/r2';
import { normalizeEmail, normalizePhone } from '$lib/server/clients/duplicates';
import {
	runReview,
	type ExistingClient,
	type ImportColumnMapping,
	type ReviewMatchAction
} from '$lib/server/imports/review';

// Step 4 of the client import: the "Review" dry-run. Re-read the mapped file, work out row by row what WOULD
// happen (create / update / skip / hold / error), and save that decision -- nothing is written to `clients`
// here (that is step 5's worker). The [batchId=uuid] matcher rejects a non-uuid path with a 404 before we run.
//
// Re-reading and deduping a whole file is heavier than an ordinary write, so it gets its own rate-limit
// counter, like the upload step.
const REVIEW_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

// match_import_clients takes the file's emails/phones as array params -- one round trip, no URL-length ceiling.
// A single row per matched contact method comes back; the route folds them into lookup maps.
type MatchRow = {
	client_id: string;
	matched_kind: 'email' | 'phone';
	matched_value: string;
	client_type: 'person' | 'company';
	first_name: string | null;
	last_name: string | null;
	company_name: string | null;
	lead_source: string | null;
	has_email: boolean;
	has_phone: boolean;
	has_property: boolean;
};

export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.create');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const batchId = event.params.batchId;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `client-import-review:${organizationId}`,
			...REVIEW_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	// Load the batch under RLS, scoped to the caller's active org so it can only review its own import.
	const { data: batch, error: batchError } = await event.locals.supabase
		.from('import_batches')
		.select('id, storage_object_key, column_mapping, match_action, status')
		.eq('id', batchId)
		.eq('organization_id', organizationId)
		.maybeSingle();
	if (batchError) return databaseError();
	if (!batch) return notFound('That import was not found.');
	if (batch.status !== 'mapped' && batch.status !== 'reviewed') {
		return validationError({ form: 'This import can no longer be reviewed.' });
	}

	const mapping = (batch.column_mapping ?? {}) as ImportColumnMapping;
	if (Object.keys(mapping).length === 0) {
		return validationError({ form: 'Map at least one column before reviewing this import.' });
	}
	const matchAction = (batch.match_action ?? 'skip') as ReviewMatchAction;

	// Re-read the exact file we stored, and parse it the same way the upload step did so headers and cells line
	// up with the saved mapping.
	let text: string;
	try {
		const bytes = await getObjectBytes(batch.storage_object_key);
		text = new TextDecoder().decode(bytes);
	} catch {
		return json(
			{ error: 'We could not re-open that file. Please upload it again.' },
			{ status: 503, headers: NO_STORE_HEADERS }
		);
	}

	const parsed = Papa.parse<Record<string, string>>(text, {
		header: true,
		skipEmptyLines: 'greedy',
		transformHeader: (header) => header.trim()
	});
	const rows = parsed.data;
	if (rows.length === 0) {
		return validationError({ form: 'That file has no data rows to review.' });
	}

	// Collect the file's normalized emails/phones once, so the dedupe lookup is one batched call rather than one
	// per row. Only columns the office actually mapped to email/phone contribute.
	const emailHeaders: string[] = [];
	const phoneHeaders: string[] = [];
	for (const [header, entry] of Object.entries(mapping)) {
		if (entry.field === 'email') emailHeaders.push(header);
		if (entry.field === 'phone') phoneHeaders.push(header);
	}
	const emailSet = new Set<string>();
	const phoneSet = new Set<string>();
	for (const row of rows) {
		for (const header of emailHeaders) {
			const value = normalizeEmail(row[header]);
			if (value) emailSet.add(value);
		}
		for (const header of phoneHeaders) {
			const value = normalizePhone(row[header]);
			if (value) phoneSet.add(value);
		}
	}

	const emailToClientId = new Map<string, string>();
	const phoneToClientId = new Map<string, string>();
	const clientsById = new Map<string, ExistingClient>();

	// Skip the lookup entirely when the file carries no contact values -- there is nothing an existing client
	// could match on.
	if (emailSet.size > 0 || phoneSet.size > 0) {
		const { data: matches, error: matchError } = await event.locals.supabase.rpc(
			'match_import_clients',
			{
				target_org: organizationId,
				emails: [...emailSet],
				phones: [...phoneSet]
			}
		);
		if (matchError) return databaseError();

		for (const match of (matches ?? []) as MatchRow[]) {
			if (match.matched_kind === 'email') emailToClientId.set(match.matched_value, match.client_id);
			else phoneToClientId.set(match.matched_value, match.client_id);
			if (!clientsById.has(match.client_id)) {
				clientsById.set(match.client_id, {
					id: match.client_id,
					client_type: match.client_type,
					first_name: match.first_name,
					last_name: match.last_name,
					company_name: match.company_name,
					lead_source: match.lead_source,
					has_email: match.has_email,
					has_phone: match.has_phone,
					has_property: match.has_property
				});
			}
		}
	}

	const { rows: reviewRows, summary } = runReview({
		rows,
		mapping,
		matchAction,
		emailToClientId,
		phoneToClientId,
		clientsById
	});

	const { data: reviewed, error: reviewError } = await event.locals.supabase.rpc(
		'review_import_batch',
		{
			payload: {
				batch_id: batchId,
				rows: reviewRows.map((row) => ({
					source_row_number: row.source_row_number,
					raw: row.raw,
					planned_action: row.planned_action,
					resolved_payload: row.resolved_payload,
					match_client_id: row.match_client_id,
					match_reason: row.match_reason,
					flags: row.flags,
					error_message: row.error_message
				}))
			}
		}
	);
	if (reviewError) {
		if (reviewError.code === 'P0002') return notFound('That import was not found.');
		if (reviewError.code === '42501') {
			return json(
				{ error: 'You do not have permission to change this import.' },
				{ status: 403, headers: NO_STORE_HEADERS }
			);
		}
		if (reviewError.code === '22023') {
			return validationError({ form: 'This import can no longer be reviewed.' });
		}
		return databaseError();
	}

	return json(
		{ batch_id: reviewed.id, status: reviewed.status, summary },
		{ status: 200, headers: NO_STORE_HEADERS }
	);
};
