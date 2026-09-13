// Client import wizard: the browser side of the four API routes under /api/imports/clients. Upload a CSV,
// save the column mapping + match action, run the review dry-run, commit, then poll status while the
// background worker drains the queued rows.

// The fields a CSV column can map to. Values match the server enum in imports.schema.ts 1:1 (the server is the
// authority; this is the labelled UI mirror -- server code must never be imported into the browser). Order is
// the order the field picker lists them in.
export type ImportFieldTarget =
	| 'first_name'
	| 'last_name'
	| 'company_name'
	| 'email'
	| 'phone'
	| 'lead_source'
	| 'initial_note'
	| 'property.label'
	| 'property.address_line1'
	| 'property.address_line2'
	| 'property.city'
	| 'property.state_region'
	| 'property.postal_code'
	| 'property.country';

export const IMPORT_FIELD_OPTIONS: Array<{ value: ImportFieldTarget; label: string }> = [
	{ value: 'first_name', label: 'First name' },
	{ value: 'last_name', label: 'Last name' },
	{ value: 'company_name', label: 'Business name' },
	{ value: 'email', label: 'Email' },
	{ value: 'phone', label: 'Phone' },
	{ value: 'lead_source', label: 'Lead source' },
	{ value: 'initial_note', label: 'Client note' },
	{ value: 'property.label', label: 'Property · Label' },
	{ value: 'property.address_line1', label: 'Property · Street' },
	{ value: 'property.address_line2', label: 'Property · Street line 2' },
	{ value: 'property.city', label: 'Property · City' },
	{ value: 'property.state_region', label: 'Property · State / region' },
	{ value: 'property.postal_code', label: 'Property · Postal code' },
	{ value: 'property.country', label: 'Property · Country' }
];

export type MatchAction = 'skip' | 'update';

export type ColumnMappingEntry = { field: ImportFieldTarget; dont_overwrite: boolean };
// file column header -> mapping entry. A column the office chose not to import is simply absent.
export type ColumnMapping = Record<string, ColumnMappingEntry>;

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

// A failed import call as the browser sees it: the server's message plus any per-field messages so the wizard
// can point at the offending control (e.g. the file input or the consent checkbox).
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

// The polled status lives under this key; it is scoped by batch so two imports never share a cache entry.
export const importStatusKey = (batchId: string) =>
	['imports', 'clients', 'status', batchId] as const;

export async function uploadClientImport(file: File): Promise<UploadResult> {
	const form = new FormData();
	form.set('file', file);
	const response = await fetch('/api/imports/clients', { method: 'POST', body: form });
	if (!response.ok) throw await importError(response, 'That file could not be uploaded.');
	return response.json();
}

export async function setImportMapping(
	batchId: string,
	input: { column_mapping: ColumnMapping; match_action: MatchAction }
): Promise<{ batch_id: string; status: ImportStatus }> {
	const response = await fetch(`/api/imports/clients/${batchId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await importError(response, 'That mapping could not be saved.');
	return response.json();
}

export async function reviewImport(
	batchId: string
): Promise<{ batch_id: string; status: ImportStatus; summary: ReviewSummary }> {
	const response = await fetch(`/api/imports/clients/${batchId}/review`, { method: 'POST' });
	if (!response.ok) throw await importError(response, 'That import could not be reviewed.');
	return response.json();
}

export async function commitImport(
	batchId: string
): Promise<{ batch_id: string; status: ImportStatus; counts: ImportCounts }> {
	const response = await fetch(`/api/imports/clients/${batchId}/commit`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ consent_affirmed: true })
	});
	if (!response.ok) throw await importError(response, 'That import could not be started.');
	return response.json();
}

export async function fetchImportStatus(batchId: string): Promise<StatusResult> {
	const response = await fetch(`/api/imports/clients/${batchId}`);
	if (!response.ok) throw await importError(response, 'We could not check the import.');
	return response.json();
}

// --- Auto-mapping --------------------------------------------------------------------------------------

// Common spreadsheet/CRM header spellings -> our field. Compared after stripping to lowercase letters and
// digits, so "First Name", "first_name" and "FIRSTNAME" all collapse to the same key. Only high-confidence
// matches live here; anything unrecognised is left for the office to pick, exactly like a mature importer.
const HEADER_ALIASES: Record<string, ImportFieldTarget> = {
	firstname: 'first_name',
	givenname: 'first_name',
	fname: 'first_name',
	lastname: 'last_name',
	surname: 'last_name',
	familyname: 'last_name',
	lname: 'last_name',
	fullname: 'first_name',
	name: 'first_name',
	company: 'company_name',
	companyname: 'company_name',
	business: 'company_name',
	businessname: 'company_name',
	organization: 'company_name',
	organisation: 'company_name',
	email: 'email',
	emailaddress: 'email',
	phone: 'phone',
	phonenumber: 'phone',
	mobile: 'phone',
	mobilephone: 'phone',
	cell: 'phone',
	telephone: 'phone',
	leadsource: 'lead_source',
	source: 'lead_source',
	notes: 'initial_note',
	note: 'initial_note',
	comment: 'initial_note',
	comments: 'initial_note',
	street: 'property.address_line1',
	address: 'property.address_line1',
	addressline1: 'property.address_line1',
	streetaddress: 'property.address_line1',
	address1: 'property.address_line1',
	addressline2: 'property.address_line2',
	address2: 'property.address_line2',
	unit: 'property.address_line2',
	apt: 'property.address_line2',
	city: 'property.city',
	town: 'property.city',
	state: 'property.state_region',
	stateregion: 'property.state_region',
	province: 'property.state_region',
	region: 'property.state_region',
	county: 'property.state_region',
	postalcode: 'property.postal_code',
	postcode: 'property.postal_code',
	zip: 'property.postal_code',
	zipcode: 'property.postal_code',
	country: 'property.country',
	countryregion: 'property.country'
};

function canonicalHeader(header: string): string {
	return header.toLowerCase().replace(/[^a-z0-9]/g, '');
}

// Guess a mapping from the file's headers. A field is claimed by the first header that wants it, so two
// columns never map to the same field (which the server rejects anyway). Returns only the columns we matched;
// the rest stay unset for the office to fill in.
export function autoMapHeaders(headers: string[]): ColumnMapping {
	const mapping: ColumnMapping = {};
	const claimed = new Set<ImportFieldTarget>();
	for (const header of headers) {
		const field = HEADER_ALIASES[canonicalHeader(header)];
		if (field && !claimed.has(field)) {
			mapping[header] = { field, dont_overwrite: false };
			claimed.add(field);
		}
	}
	return mapping;
}
