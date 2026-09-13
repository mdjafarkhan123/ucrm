// Price Book import wizard: the browser side of the three stateless API routes under /api/imports/price-book.
// Unlike the client importer there is no batch id -- Upload just parses the file, and Review/Commit each take
// the whole (rows, mapping, match action) and recompute fresh. The browser is what carries the rows between
// steps.

import { ImportError } from '$lib/imports/api';

export { ImportError };

export type CatalogFieldTarget =
	| 'name'
	| 'category'
	| 'description'
	| 'unit_label'
	| 'unit_price'
	| 'unit_cost'
	| 'is_taxable'
	| 'is_labor';

export const IMPORT_CATALOG_FIELD_OPTIONS: Array<{ value: CatalogFieldTarget; label: string }> = [
	{ value: 'name', label: 'Name' },
	{ value: 'category', label: 'Type (Product or Service)' },
	{ value: 'description', label: 'Description' },
	{ value: 'unit_label', label: 'Unit label' },
	{ value: 'unit_price', label: 'Price' },
	{ value: 'unit_cost', label: 'Cost' },
	{ value: 'is_taxable', label: 'Taxable (Yes/No)' },
	{ value: 'is_labor', label: 'Labor (Yes/No)' }
];

export type CatalogMatchAction = 'skip' | 'update';

export type CatalogColumnMappingEntry = { field: CatalogFieldTarget; dont_overwrite: boolean };
export type CatalogColumnMapping = Record<string, CatalogColumnMappingEntry>;

export type CatalogUploadResult = {
	headers: string[];
	rows: Record<string, string>[];
	row_count: number;
};

export type CatalogReviewSummary = {
	total: number;
	create: number;
	update: number;
	skip: number;
	hold: number;
	error: number;
};

export type CatalogImportCounts = {
	created: number;
	updated: number;
	skipped: number;
	held: number;
	error: number;
};

export type CatalogErrorRow = { source_row_number: number; reason: string };

export type CatalogCommitResult = {
	counts: CatalogImportCounts;
	error_rows: CatalogErrorRow[];
};

async function importError(response: Response, fallback: string): Promise<ImportError> {
	const body = (await response.json().catch(() => ({}))) as {
		error?: string;
		field_errors?: Record<string, string>;
	};
	return new ImportError(body.error ?? fallback, body.field_errors ?? {}, response.status);
}

export async function uploadCatalogImport(file: File): Promise<CatalogUploadResult> {
	const form = new FormData();
	form.set('file', file);
	const response = await fetch('/api/imports/price-book', { method: 'POST', body: form });
	if (!response.ok) throw await importError(response, 'That file could not be uploaded.');
	return response.json();
}

type ReviewInput = {
	rows: Record<string, string>[];
	column_mapping: CatalogColumnMapping;
	match_action: CatalogMatchAction;
};

export async function reviewCatalogImport(
	input: ReviewInput
): Promise<{ summary: CatalogReviewSummary }> {
	const response = await fetch('/api/imports/price-book/review', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await importError(response, 'That import could not be reviewed.');
	return response.json();
}

export async function commitCatalogImport(input: ReviewInput): Promise<CatalogCommitResult> {
	const response = await fetch('/api/imports/price-book/commit', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await importError(response, 'That import could not be started.');
	return response.json();
}

// --- Auto-mapping --------------------------------------------------------------------------------------

const HEADER_ALIASES: Record<string, CatalogFieldTarget> = {
	name: 'name',
	itemname: 'name',
	productname: 'name',
	servicename: 'name',
	type: 'category',
	category: 'category',
	itemtype: 'category',
	description: 'description',
	desc: 'description',
	unit: 'unit_label',
	unitlabel: 'unit_label',
	units: 'unit_label',
	price: 'unit_price',
	unitprice: 'unit_price',
	saleprice: 'unit_price',
	rate: 'unit_price',
	cost: 'unit_cost',
	unitcost: 'unit_cost',
	taxable: 'is_taxable',
	tax: 'is_taxable',
	labor: 'is_labor',
	islabor: 'is_labor'
};

function canonicalHeader(header: string): string {
	return header.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function autoMapCatalogHeaders(headers: string[]): CatalogColumnMapping {
	const mapping: CatalogColumnMapping = {};
	const claimed = new Set<CatalogFieldTarget>();
	for (const header of headers) {
		const field = HEADER_ALIASES[canonicalHeader(header)];
		if (field && !claimed.has(field)) {
			mapping[header] = { field, dont_overwrite: false };
			claimed.add(field);
		}
	}
	return mapping;
}
