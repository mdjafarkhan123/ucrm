// Opening-balances import wizard: the browser side of the four API routes under /api/imports/opening-balances.
// Upload a CSV, save the column mapping, run the review dry-run, commit, then poll status while the shared
// background worker drains the queued rows. Mirrors $lib/imports/api.ts (the client importer); the differences
// are the fields on offer (no "don't overwrite" toggle, no match action -- a match is always a correction) and
// the endpoints.

export type OpeningBalanceFieldTarget =
	'client_email' | 'balance_type' | 'amount' | 'as_of_date' | 'source_note';

export const OPENING_BALANCE_FIELD_OPTIONS: Array<{
	value: OpeningBalanceFieldTarget;
	label: string;
}> = [
	{ value: 'client_email', label: 'Client email' },
	{ value: 'balance_type', label: 'Balance type ("receivable" or "credit")' },
	{ value: 'amount', label: 'Amount' },
	{ value: 'as_of_date', label: 'As-of date (YYYY-MM-DD)' },
	{ value: 'source_note', label: 'Note' }
];

export type OpeningBalanceColumnMapping = Record<string, { field: OpeningBalanceFieldTarget }>;

export type UploadResult = {
	batch_id: string;
	headers: string[];
	preview_rows: Record<string, string>[];
	row_count: number;
};

export type ReviewSummary = {
	total: number;
	create: number;
	update: number;
	skip: number;
	hold: number;
	error: number;
};

export type ImportCounts = {
	created: number;
	updated: number;
	skipped: number;
	held: number;
	error: number;
};

export type ImportStatus =
	'uploaded' | 'mapped' | 'reviewed' | 'importing' | 'completed' | 'failed' | 'canceled';

export type StatusResult = {
	batch_id: string;
	source_filename: string;
	row_count: number | null;
	status: ImportStatus;
	counts: ImportCounts;
	has_error_file: boolean;
};

export class ImportError extends Error {
	fieldErrors: Record<string, string>;
	status: number;
	constructor(message: string, fieldErrors: Record<string, string>, status: number) {
		super(message);
		this.name = 'ImportError';
		this.fieldErrors = fieldErrors;
		this.status = status;
	}
}

async function importError(response: Response, fallback: string): Promise<ImportError> {
	const body = (await response.json().catch(() => ({}))) as {
		error?: string;
		field_errors?: Record<string, string>;
	};
	return new ImportError(body.error ?? fallback, body.field_errors ?? {}, response.status);
}

export const openingBalanceImportStatusKey = (batchId: string) =>
	['imports', 'opening-balances', 'status', batchId] as const;

export async function uploadOpeningBalanceImport(file: File): Promise<UploadResult> {
	const form = new FormData();
	form.set('file', file);
	const response = await fetch('/api/imports/opening-balances', { method: 'POST', body: form });
	if (!response.ok) throw await importError(response, 'That file could not be uploaded.');
	return response.json();
}

export async function setOpeningBalanceImportMapping(
	batchId: string,
	input: { column_mapping: OpeningBalanceColumnMapping }
): Promise<{ batch_id: string; status: ImportStatus }> {
	const response = await fetch(`/api/imports/opening-balances/${batchId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await importError(response, 'That mapping could not be saved.');
	return response.json();
}

export async function reviewOpeningBalanceImport(
	batchId: string
): Promise<{ batch_id: string; status: ImportStatus; summary: ReviewSummary }> {
	const response = await fetch(`/api/imports/opening-balances/${batchId}/review`, {
		method: 'POST'
	});
	if (!response.ok) throw await importError(response, 'That import could not be reviewed.');
	return response.json();
}

export async function commitOpeningBalanceImport(
	batchId: string
): Promise<{ batch_id: string; status: ImportStatus; counts: ImportCounts }> {
	const response = await fetch(`/api/imports/opening-balances/${batchId}/commit`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({})
	});
	if (!response.ok) throw await importError(response, 'That import could not be started.');
	return response.json();
}

export async function fetchOpeningBalanceImportStatus(batchId: string): Promise<StatusResult> {
	const response = await fetch(`/api/imports/opening-balances/${batchId}`);
	if (!response.ok) throw await importError(response, 'We could not check the import.');
	return response.json();
}

// --- Auto-mapping --------------------------------------------------------------------------------------

const HEADER_ALIASES: Record<string, OpeningBalanceFieldTarget> = {
	email: 'client_email',
	clientemail: 'client_email',
	customeremail: 'client_email',
	balancetype: 'balance_type',
	type: 'balance_type',
	amount: 'amount',
	balance: 'amount',
	openingbalance: 'amount',
	asofdate: 'as_of_date',
	date: 'as_of_date',
	note: 'source_note',
	notes: 'source_note',
	sourcenote: 'source_note'
};

function canonicalHeader(header: string): string {
	return header.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function autoMapOpeningBalanceHeaders(headers: string[]): OpeningBalanceColumnMapping {
	const mapping: OpeningBalanceColumnMapping = {};
	const claimed = new Set<OpeningBalanceFieldTarget>();
	for (const header of headers) {
		const field = HEADER_ALIASES[canonicalHeader(header)];
		if (field && !claimed.has(field)) {
			mapping[header] = { field };
			claimed.add(field);
		}
	}
	return mapping;
}
