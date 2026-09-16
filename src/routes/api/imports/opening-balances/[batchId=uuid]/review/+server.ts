import { json } from '@sveltejs/kit';
import Papa from 'papaparse';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound, validationError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { getObjectBytes } from '$lib/server/storage/r2';
import { normalizeEmail } from '$lib/server/clients/duplicates';
import { organizationFormatting } from '$lib/server/requests/timezone';
import {
	runOpeningBalanceReview,
	type ActiveOpeningBalanceFact,
	type OpeningBalanceColumnMapping
} from '$lib/server/imports/opening-balance-review';

// Step 3 of the opening-balances import: the "Review" dry-run. Re-read the mapped file, resolve each row's
// client by email, work out row by row what WOULD happen (create / update-as-correction / hold / error), and
// save that decision -- nothing is written to client_opening_balances here (that is the shared step-4 worker).
const REVIEW_LIMIT = { windowSeconds: 60, maxAttempts: 10 };

type ClientMatchRow = { client_id: string; matched_kind: 'email' | 'phone'; matched_value: string };
type ActiveFactRow = {
	client_id: string;
	balance_type: 'receivable' | 'credit';
	opening_balance_id: string;
};

export const POST: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;
	const batchId = event.params.batchId;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `opening-balance-import-review:${organizationId}`,
			...REVIEW_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	const { data: batch, error: batchError } = await event.locals.supabase
		.from('import_batches')
		.select('id, storage_object_key, column_mapping, status')
		.eq('id', batchId)
		.eq('organization_id', organizationId)
		.eq('entity_type', 'opening_balance')
		.maybeSingle();
	if (batchError) return databaseError();
	if (!batch) return notFound('That import was not found.');
	if (batch.status !== 'mapped' && batch.status !== 'reviewed') {
		return validationError({ form: 'This import can no longer be reviewed.' });
	}

	const mapping = (batch.column_mapping ?? {}) as OpeningBalanceColumnMapping;
	if (Object.keys(mapping).length === 0) {
		return validationError({ form: 'Map at least one column before reviewing this import.' });
	}

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

	const emailHeaders = Object.entries(mapping)
		.filter(([, entry]) => entry.field === 'client_email')
		.map(([header]) => header);
	const emailSet = new Set<string>();
	for (const row of rows) {
		for (const header of emailHeaders) {
			const value = normalizeEmail(row[header]);
			if (value) emailSet.add(value);
		}
	}

	const emailToClientId = new Map<string, string>();
	const clientIds: string[] = [];
	if (emailSet.size > 0) {
		const { data: matches, error: matchError } = await event.locals.supabase.rpc(
			'match_import_clients',
			{ target_org: organizationId, emails: [...emailSet], phones: [] }
		);
		if (matchError) return databaseError();

		for (const match of (matches ?? []) as ClientMatchRow[]) {
			if (match.matched_kind !== 'email') continue;
			emailToClientId.set(match.matched_value, match.client_id);
			clientIds.push(match.client_id);
		}
	}

	let activeFacts: ActiveOpeningBalanceFact[] = [];
	if (clientIds.length > 0) {
		const { data: facts, error: factsError } = await event.locals.supabase.rpc(
			'match_active_opening_balances',
			{ target_org: organizationId, client_ids: clientIds }
		);
		if (factsError) return databaseError();
		activeFacts = ((facts ?? []) as ActiveFactRow[]).map((fact) => ({
			client_id: fact.client_id,
			balance_type: fact.balance_type,
			opening_balance_id: fact.opening_balance_id
		}));
	}

	const formatting = await organizationFormatting(event.locals.supabase, organizationId);
	const currencyCode = formatting.ok ? formatting.formatting.currency_code : 'USD';

	const { rows: reviewRows, summary } = runOpeningBalanceReview({
		rows,
		mapping,
		emailToClientId,
		activeFacts,
		currencyCode
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
