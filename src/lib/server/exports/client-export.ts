// Onboarding & Data Portability, Part 2: the client-book export. The mirror of the Part 1 import -- a
// contractor takes their own clients out as one structured, self-contained package.
//
// Records only (attachments are a later part), built in memory and streamed straight down: for one
// organization the client book is bounded (the import caps a single file at 5,000 rows), so there is no
// job queue, no stored object, and no expiring link to break -- the customer keeps the file they download.
//
// The package is a zip of one CSV per record type plus a manifest.json that names each file, its row count,
// its primary key, and which columns join it back to the others -- so an outside reader can rejoin the
// records without our schema. Every query is scoped to the caller's organization_id (defence in depth behind
// RLS), and only the customer's own business data is exported: tenant, audit, soft-delete and internal-FK
// columns are left out on purpose (see the column lists below).

import type { SupabaseClient } from '@supabase/supabase-js';
import Papa from 'papaparse';
import { zipSync, strToU8 } from 'fflate';
import type { Database } from '$lib/database.types';

type Supabase = SupabaseClient<Database>;

// Bumped only when the shape of the package changes, so a future importer can tell the versions apart.
const SCHEMA_VERSION = 1;

// The customer's own business data, in a stable column order. Deliberately excluded everywhere:
// organization_id (our tenant key), created_by/edited_by (internal user ids), updated_at (audit),
// deleted_at (soft-delete internal -- deleted rows are filtered out, not exported), and internal foreign
// keys to our own config rows that mean nothing outside our schema (billing_payment_term_id, tax_rate_id,
// geocode_status, normalized_value).
const CLIENT_COLUMNS = [
	'id',
	'display_name',
	'first_name',
	'last_name',
	'company_name',
	'client_type',
	'lifecycle_status',
	'lead_source',
	'lead_temperature',
	'next_follow_up_at',
	'converted_to_customer_at',
	'billing_address_line1',
	'billing_address_line2',
	'billing_city',
	'billing_state_region',
	'billing_postal_code',
	'billing_country',
	'archived_at',
	'created_at'
] as const;

const CONTACT_COLUMNS = [
	'id',
	'client_id',
	'first_name',
	'last_name',
	'role_label',
	'is_primary',
	'created_at'
] as const;

const CONTACT_METHOD_COLUMNS = [
	'id',
	'client_id',
	'client_contact_id',
	'kind',
	'value',
	'label',
	'is_primary',
	'created_at'
] as const;

const PROPERTY_COLUMNS = [
	'id',
	'client_id',
	'label',
	'address_line1',
	'address_line2',
	'city',
	'state_region',
	'postal_code',
	'country',
	'latitude',
	'longitude',
	'is_primary',
	'is_billing_address',
	'access_notes',
	'archived_at',
	'created_at'
] as const;

// Notes are polymorphic (note_links: entity_type + entity_id). We export only notes attached to a client or
// a property, carrying the link columns so a reader can see what each note is about and rejoin it.
const NOTE_COLUMNS = [
	'id',
	'entity_type',
	'entity_id',
	'body',
	'pinned',
	'created_at',
	'edited_at'
] as const;

type Row = Record<string, unknown>;

export type ClientExportData = {
	clients: Row[];
	contacts: Row[];
	contactMethods: Row[];
	properties: Row[];
	notes: Row[];
};

type ExportFile = {
	name: string;
	primaryKey: string;
	links?: { column: string; references: string }[];
};

// The files in the package and how they join. Order here is the order they appear in the manifest.
const EXPORT_FILES: {
	file: ExportFile;
	columns: readonly string[];
	key: keyof ClientExportData;
}[] = [
	{ file: { name: 'clients.csv', primaryKey: 'id' }, columns: CLIENT_COLUMNS, key: 'clients' },
	{
		file: {
			name: 'contacts.csv',
			primaryKey: 'id',
			links: [{ column: 'client_id', references: 'clients.csv:id' }]
		},
		columns: CONTACT_COLUMNS,
		key: 'contacts'
	},
	{
		file: {
			name: 'contact_methods.csv',
			primaryKey: 'id',
			links: [
				{ column: 'client_id', references: 'clients.csv:id' },
				{ column: 'client_contact_id', references: 'contacts.csv:id' }
			]
		},
		columns: CONTACT_METHOD_COLUMNS,
		key: 'contactMethods'
	},
	{
		file: {
			name: 'properties.csv',
			primaryKey: 'id',
			links: [{ column: 'client_id', references: 'clients.csv:id' }]
		},
		columns: PROPERTY_COLUMNS,
		key: 'properties'
	},
	{
		file: {
			name: 'notes.csv',
			primaryKey: 'id',
			// entity_id points at clients.csv:id or properties.csv:id depending on entity_type.
			links: [{ column: 'entity_id', references: 'clients.csv:id | properties.csv:id' }]
		},
		columns: NOTE_COLUMNS,
		key: 'notes'
	}
];

// papaparse writes the CSV; passing an explicit column list keeps the order stable and includes a column even
// when every value in it is null, so the header shape never shifts between exports.
function toCsv(rows: Row[], columns: readonly string[]): string {
	return Papa.unparse(
		rows.map((row) => {
			const projected: Row = {};
			for (const column of columns) projected[column] = row[column] ?? '';
			return projected;
		}),
		{ columns: [...columns] }
	);
}

// Pure: turn already-fetched rows into the zip bytes. Kept separate from the queries so it can be tested by
// unzipping the result -- no database needed.
export function buildClientExportArchive(
	data: ClientExportData,
	generatedAt = new Date()
): Uint8Array {
	const files: Record<string, Uint8Array> = {};

	for (const { file, columns, key } of EXPORT_FILES) {
		files[file.name] = strToU8(toCsv(data[key], columns));
	}

	const manifest = {
		export_type: 'client_book',
		schema_version: SCHEMA_VERSION,
		generated_at: generatedAt.toISOString(),
		files: EXPORT_FILES.map(({ file, key }) => ({
			name: file.name,
			rows: data[key].length,
			primary_key: file.primaryKey,
			...(file.links ? { links: file.links } : {})
		}))
	};
	files['manifest.json'] = strToU8(JSON.stringify(manifest, null, 2));

	return zipSync(files);
}

// A stable, human-readable download name; the date is enough to tell two exports apart in a downloads folder.
export function clientExportFileName(generatedAt = new Date()): string {
	const date = generatedAt.toISOString().slice(0, 10);
	return `clients-export-${date}.zip`;
}

type ExportTable = 'clients' | 'client_contacts' | 'client_contact_methods' | 'properties';

async function selectAll(
	supabase: Supabase,
	table: ExportTable,
	columns: string,
	organizationId: string
) {
	const { data, error } = await supabase
		.from(table)
		.select(columns)
		.eq('organization_id', organizationId);
	if (error) throw new Error(`Could not read ${table} for export: ${error.message}`);
	return (data ?? []) as unknown as Row[];
}

// Fetch every record type for one organization. RLS already scopes reads to the caller's organization; the
// explicit organization_id filter is defence in depth and keeps deleted rows out where the table soft-deletes.
export async function fetchClientExportData(
	supabase: Supabase,
	organizationId: string
): Promise<ClientExportData> {
	const [clients, contacts, contactMethods, properties, noteLinks] = await Promise.all([
		selectAll(
			supabase,
			'clients',
			CLIENT_COLUMNS.join(',') + ',deleted_at,organization_id',
			organizationId
		).then((rows) => rows.filter((row) => row.deleted_at == null)),
		selectAll(supabase, 'client_contacts', CONTACT_COLUMNS.join(','), organizationId),
		selectAll(supabase, 'client_contact_methods', CONTACT_METHOD_COLUMNS.join(','), organizationId),
		selectAll(
			supabase,
			'properties',
			PROPERTY_COLUMNS.join(',') + ',deleted_at,organization_id',
			organizationId
		).then((rows) => rows.filter((row) => row.deleted_at == null)),
		// notes are reached through their link rows so each carries what it is attached to.
		(async () => {
			const { data, error } = await supabase
				.from('note_links')
				.select('entity_type, entity_id, notes(id, body, pinned, created_at, edited_at)')
				.eq('organization_id', organizationId)
				.in('entity_type', ['client', 'property']);
			if (error) throw new Error(`Could not read notes for export: ${error.message}`);
			return (data ?? []) as unknown as {
				entity_type: string;
				entity_id: string;
				notes: Row | null;
			}[];
		})()
	]);

	const notes: Row[] = noteLinks
		.filter((link) => link.notes != null)
		.map((link) => ({
			id: link.notes!.id,
			entity_type: link.entity_type,
			entity_id: link.entity_id,
			body: link.notes!.body,
			pinned: link.notes!.pinned,
			created_at: link.notes!.created_at,
			edited_at: link.notes!.edited_at
		}));

	return { clients, contacts, contactMethods, properties, notes };
}
