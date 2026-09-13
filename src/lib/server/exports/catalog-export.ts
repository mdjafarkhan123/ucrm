// Onboarding & Data Portability, Part 3: the Price Book export. Unlike the client-book export (Part 2), a
// price book is one flat table, so the package is a single CSV -- no zip, no manifest. Prices are written as
// plain dollars, and the two flags as Yes/No, because this file is meant to be opened in a spreadsheet and
// re-imported, not read as a raw database dump.

import type { SupabaseClient } from '@supabase/supabase-js';
import Papa from 'papaparse';
import type { Database } from '$lib/database.types';

type Supabase = SupabaseClient<Database>;

const EXPORT_COLUMNS = [
	'Name',
	'Type',
	'Description',
	'Unit label',
	'Price',
	'Cost',
	'Taxable',
	'Labor',
	'Archived'
] as const;

type CatalogExportRow = {
	category: 'product' | 'service';
	name: string;
	description: string | null;
	unit_label: string | null;
	unit_price_minor: number;
	unit_cost_minor: number;
	is_taxable: boolean;
	is_labor: boolean;
	archived_at: string | null;
};

function minorToDollars(minor: number): string {
	return (minor / 100).toFixed(2);
}

function yesNo(value: boolean): string {
	return value ? 'Yes' : 'No';
}

// Pure: turn already-fetched rows into the CSV text. Kept separate from the query so it can be tested without
// a database.
export function buildCatalogExportCsv(items: CatalogExportRow[]): string {
	return Papa.unparse(
		items.map((item) => ({
			Name: item.name,
			Type: item.category === 'product' ? 'Product' : 'Service',
			Description: item.description ?? '',
			'Unit label': item.unit_label ?? '',
			Price: minorToDollars(item.unit_price_minor),
			Cost: minorToDollars(item.unit_cost_minor),
			Taxable: yesNo(item.is_taxable),
			Labor: yesNo(item.is_labor),
			Archived: yesNo(item.archived_at !== null)
		})),
		{ columns: [...EXPORT_COLUMNS] }
	);
}

export function catalogExportFileName(generatedAt = new Date()): string {
	const date = generatedAt.toISOString().slice(0, 10);
	return `price-book-export-${date}.csv`;
}

// Every item for the organization, including archived ones (flagged in the Archived column) -- the same
// choice Part 2 makes for clients/properties. Name order matches the Settings list's default sort.
export async function fetchCatalogExportData(
	supabase: Supabase,
	organizationId: string
): Promise<CatalogExportRow[]> {
	const { data, error } = await supabase.rpc('catalog_items_for_price_book_export', {
		target_organization_id: organizationId
	});
	if (error) throw new Error(`Could not read the Price Book for export: ${error.message}`);
	return (data ?? []) as unknown as CatalogExportRow[];
}
