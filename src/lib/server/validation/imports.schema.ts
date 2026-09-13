import { z } from 'zod';

// The fields a CSV column may be mapped to on the "Map columns" step. Flat list, dot-notation for the
// property sub-fields, so it lines up 1:1 with the resolved_payload contract the import worker writes
// (see the column comment on import_rows.resolved_payload). Every entry is a real client field that already
// exists in clientWriteSchema; "Don't import this column" is expressed by leaving the column out of the map.
export const IMPORT_CLIENT_TARGETS = [
	'first_name',
	'last_name',
	'company_name',
	'email',
	'phone',
	'lead_source',
	'initial_note',
	'property.label',
	'property.address_line1',
	'property.address_line2',
	'property.city',
	'property.state_region',
	'property.postal_code',
	'property.country'
] as const;

const importClientTargetSchema = z.enum(IMPORT_CLIENT_TARGETS);

export type ImportClientTarget = (typeof IMPORT_CLIENT_TARGETS)[number];

// One mapped column: which of our fields it feeds, and (only meaningful when match_action is 'update')
// whether to leave an already-filled value alone rather than overwrite it.
const columnMappingEntrySchema = z.object({
	field: importClientTargetSchema,
	dont_overwrite: z.boolean().default(false)
});

export const importClientsMappingSchema = z.object({
	// Skip = leave a matched client untouched; update = write the mapped fields onto it. A match is never
	// imported as a second client either way -- that is enforced by our dedupe rules and the hard unique index.
	match_action: z.enum(['skip', 'update']),
	// file column header -> mapping entry. Columns the office chose not to import are simply absent.
	column_mapping: z
		.record(z.string().min(1), columnMappingEntrySchema)
		.refine((mapping) => Object.keys(mapping).length > 0, {
			message: 'Match at least one column to one of our fields.'
		})
		// Two columns feeding the same field would make the last one silently win, so we reject it and let the
		// office fix the mapping instead of guessing which column they meant.
		.refine(
			(mapping) => {
				const targets = Object.values(mapping).map((entry) => entry.field);
				return new Set(targets).size === targets.length;
			},
			{ message: 'Two columns are mapped to the same field. Each field can only be used once.' }
		)
});

export type ImportClientsMappingInput = z.infer<typeof importClientsMappingSchema>;

// The Commit step's one input: the office must affirm consent (HubSpot's own gate) before any client is
// written. Nothing else is sent -- the rows and their decisions already live on the batch from Review. A
// missing or false flag fails here rather than reaching the RPC, so the office sees a clear field message.
export const importClientsCommitSchema = z.object({
	consent_affirmed: z.literal(true, {
		message: 'Confirm these contacts agreed to hear from you before importing.'
	})
});

export type ImportClientsCommitInput = z.infer<typeof importClientsCommitSchema>;

// Onboarding & Data Portability, Part 3: the Price Book import. Unlike the client importer, this one has no
// batch/worker -- a price book is one flat table and realistically dozens to a few hundred rows, so Review and
// Commit both recompute the plan fresh from whatever (rows, mapping, match_action) the browser sends, straight
// from the CSV it parsed at Upload. Nothing is persisted between steps.
export const IMPORT_CATALOG_TARGETS = [
	'name',
	'category',
	'description',
	'unit_label',
	'unit_price',
	'unit_cost',
	'is_taxable',
	'is_labor'
] as const;

const importCatalogTargetSchema = z.enum(IMPORT_CATALOG_TARGETS);

export type ImportCatalogTarget = (typeof IMPORT_CATALOG_TARGETS)[number];

const catalogColumnMappingEntrySchema = z.object({
	field: importCatalogTargetSchema,
	dont_overwrite: z.boolean().default(false)
});

export const importCatalogMappingSchema = z.object({
	match_action: z.enum(['skip', 'update']),
	column_mapping: z
		.record(z.string().min(1), catalogColumnMappingEntrySchema)
		.refine((mapping) => Object.keys(mapping).length > 0, {
			message: 'Match at least one column to one of our fields.'
		})
		.refine(
			(mapping) => {
				const targets = Object.values(mapping).map((entry) => entry.field);
				return new Set(targets).size === targets.length;
			},
			{ message: 'Two columns are mapped to the same field. Each field can only be used once.' }
		)
});

// A parsed CSV data row, kept exactly as the browser read it (header -> cell text). Review and Commit share
// this shape: both take the whole file plus the mapping and recompute the plan, rather than trusting a
// client-echoed decision.
const importCatalogRowSchema = z.record(z.string().min(1).max(200), z.string().max(2000));

export const importCatalogReviewSchema = z.object({
	rows: z.array(importCatalogRowSchema).min(1).max(5000),
	...importCatalogMappingSchema.shape
});

export type ImportCatalogReviewInput = z.infer<typeof importCatalogReviewSchema>;
