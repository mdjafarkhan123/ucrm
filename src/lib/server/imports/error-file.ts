// Onboarding & Data Portability, Part 1, step 5b: the per-row import error file.
//
// When a batch finishes, the office needs to see -- in one downloadable file -- exactly which rows did NOT
// become clients and why, so they can fix them and re-upload. Following how mature bulk importers (Salesforce
// Data Loader, HubSpot) do it, the file lists the rows that need a person to act: rows the worker could not
// write ('failed') and rows Review held for a human decision ('held'). Rows that were intentionally skipped by
// the office's own dedupe choice are a successful outcome, not an error, and belong in the Done-screen counts
// rather than this file.
//
// The CSV echoes each row's original cells (so the office recognizes it) plus a plain-English result and
// reason. It is built and uploaded by the worker's service_role layer; the RPC only stamps the resulting R2
// key onto the batch.

import { buildClientImportErrorObjectKey, putObject } from '$lib/server/storage/r2';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';

export type ImportErrorRow = {
	source_row_number: number;
	status: 'failed' | 'held';
	raw: Record<string, unknown> | null;
	match_reason: string | null;
	error_message: string | null;
};

const RESULT_LABEL: Record<ImportErrorRow['status'], string> = {
	failed: 'Not imported',
	held: 'Needs review'
};

// A held row carries a Review match_reason, not a free-text message; turn the one reachable reason into plain
// words. A failed row already carries a plain error_message from the worker.
function reasonFor(row: ImportErrorRow): string {
	if (row.status === 'held') {
		if (row.match_reason === 'email_phone_conflict') {
			return 'This contact matched two different existing clients (one by email, one by phone), so it needs a person to decide.';
		}
		return 'This contact needs a person to review before it can be imported.';
	}
	return row.error_message?.trim() || 'This row could not be imported.';
}

function csvCell(value: unknown): string {
	const text = value === null || value === undefined ? '' : String(value);
	// Quote whenever the value could otherwise break the row/column structure; double embedded quotes.
	if (/[",\r\n]/.test(text)) return `"${text.replace(/"/g, '""')}"`;
	return text;
}

// Pure builder, unit-tested on its own. Columns: Row, Result, Reason, then every original column that appears
// in any listed row (first-seen order across rows, so the file mirrors the uploaded file's own columns).
export function buildImportErrorCsv(rows: ImportErrorRow[]): string {
	const sorted = [...rows].sort((a, b) => a.source_row_number - b.source_row_number);

	const originalColumns: string[] = [];
	const seen = new Set<string>();
	for (const row of sorted) {
		for (const key of Object.keys(row.raw ?? {})) {
			if (!seen.has(key)) {
				seen.add(key);
				originalColumns.push(key);
			}
		}
	}

	const header = ['Row', 'Result', 'Reason', ...originalColumns];
	const lines = [header.map(csvCell).join(',')];
	for (const row of sorted) {
		const cells = [
			row.source_row_number,
			RESULT_LABEL[row.status],
			reasonFor(row),
			...originalColumns.map((col) => (row.raw ?? {})[col])
		];
		lines.push(cells.map(csvCell).join(','));
	}
	// A trailing newline keeps the file well-formed for spreadsheet tools.
	return lines.join('\r\n') + '\r\n';
}

type SupabaseLike = {
	from(table: string): {
		select(columns: string): {
			eq(
				column: string,
				value: string
			): {
				in(
					column: string,
					values: string[]
				): {
					order(
						column: string,
						options: { ascending: boolean }
					): Promise<{
						data: unknown[] | null;
						error: { message: string } | null;
					}>;
				};
			};
		};
	};
	rpc(name: string, args: Record<string, unknown>): Promise<{ error: { message: string } | null }>;
};

type GenerateDeps = {
	client?: SupabaseLike;
	organizationId: string;
	batchId: string;
	putObjectFn?: (objectKey: string, body: Uint8Array, mimeType: string) => Promise<void>;
};

// Build the error file for one completed batch and record its key. Returns the object key, or null when the
// batch had no failed/held rows (nothing to explain -- error_file_object_key stays null, as the schema
// documents). Idempotent: the key is deterministic per batch, so a re-run overwrites in place.
export async function generateImportErrorFile(
	deps: GenerateDeps
): Promise<{ objectKey: string | null }> {
	const client = (deps.client ?? getOwnerSupabaseClient()) as unknown as SupabaseLike;
	const put = deps.putObjectFn ?? putObject;

	const { data, error } = await client
		.from('import_rows')
		.select('source_row_number, status, raw, match_reason, error_message')
		.eq('batch_id', deps.batchId)
		.in('status', ['failed', 'held'])
		.order('source_row_number', { ascending: true });

	if (error) throw new Error(`Could not read import rows for the error file: ${error.message}`);

	const rows = (data ?? []) as ImportErrorRow[];
	if (rows.length === 0) return { objectKey: null };

	const objectKey = buildClientImportErrorObjectKey(deps.organizationId, deps.batchId);
	const csv = buildImportErrorCsv(rows);
	await put(objectKey, new TextEncoder().encode(csv), 'text/csv');

	const stamp = await client.rpc('set_import_batch_error_file', {
		target_batch_id: deps.batchId,
		object_key: objectKey
	});
	if (stamp.error)
		throw new Error(`Could not record the import error file: ${stamp.error.message}`);

	return { objectKey };
}
