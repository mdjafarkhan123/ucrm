import { describe, it, expect } from 'vitest';
import { unzipSync, strFromU8 } from 'fflate';
import Papa from 'papaparse';
import {
	buildClientExportArchive,
	clientExportFileName,
	type ClientExportData
} from './client-export';

function sampleData(): ClientExportData {
	return {
		clients: [
			{
				id: 'c1',
				display_name: 'Acme Roofing',
				first_name: null,
				last_name: null,
				company_name: 'Acme Roofing',
				client_type: 'company',
				lifecycle_status: 'active',
				lead_source: 'referral',
				lead_temperature: null,
				next_follow_up_at: null,
				converted_to_customer_at: '2026-01-02T00:00:00Z',
				billing_address_line1: '1 Main St',
				billing_address_line2: null,
				billing_city: 'Springfield',
				billing_state_region: 'IL',
				billing_postal_code: '62701',
				billing_country: 'US',
				archived_at: null,
				created_at: '2026-01-01T00:00:00Z',
				// columns that must never appear in the export:
				organization_id: 'org-secret',
				billing_payment_term_id: 'term-1',
				deleted_at: null,
				updated_at: '2026-01-03T00:00:00Z'
			}
		],
		contacts: [
			{
				id: 'ct1',
				client_id: 'c1',
				first_name: 'Jane',
				last_name: 'Doe',
				role_label: 'Owner',
				is_primary: true,
				created_at: '2026-01-01T00:00:00Z',
				organization_id: 'org-secret'
			}
		],
		contactMethods: [
			{
				id: 'm1',
				client_id: 'c1',
				client_contact_id: 'ct1',
				kind: 'email',
				value: 'jane@example.com',
				label: 'work',
				is_primary: true,
				created_at: '2026-01-01T00:00:00Z',
				normalized_value: 'jane@example.com',
				organization_id: 'org-secret'
			}
		],
		properties: [
			{
				id: 'p1',
				client_id: 'c1',
				label: 'HQ',
				address_line1: '1 Main St',
				address_line2: null,
				city: 'Springfield',
				state_region: 'IL',
				postal_code: '62701',
				country: 'US',
				latitude: 39.8,
				longitude: -89.6,
				is_primary: true,
				is_billing_address: true,
				access_notes: null,
				archived_at: null,
				created_at: '2026-01-01T00:00:00Z',
				tax_rate_id: 'tax-1',
				geocode_status: 'succeeded',
				organization_id: 'org-secret'
			}
		],
		notes: [
			{
				id: 'n1',
				entity_type: 'client',
				entity_id: 'c1',
				body: 'Prefers morning visits, "no weekends".',
				pinned: false,
				created_at: '2026-01-01T00:00:00Z',
				edited_at: null
			}
		]
	};
}

function readCsv(archive: Record<string, Uint8Array>, name: string) {
	const text = strFromU8(archive[name]);
	return Papa.parse<Record<string, string>>(text, { header: true, skipEmptyLines: true });
}

describe('buildClientExportArchive', () => {
	const at = new Date('2026-09-13T12:00:00Z');
	const archive = unzipSync(buildClientExportArchive(sampleData(), at));

	it('contains one CSV per record type plus a manifest', () => {
		expect(Object.keys(archive).sort()).toEqual(
			[
				'clients.csv',
				'contact_methods.csv',
				'contacts.csv',
				'manifest.json',
				'notes.csv',
				'properties.csv'
			].sort()
		);
	});

	it('exports only the customer-facing client columns, never tenant/audit/internal ones', () => {
		const { data, meta } = readCsv(archive, 'clients.csv');
		expect(meta.fields).toContain('display_name');
		expect(meta.fields).toContain('billing_city');
		for (const forbidden of [
			'organization_id',
			'billing_payment_term_id',
			'deleted_at',
			'updated_at'
		]) {
			expect(meta.fields).not.toContain(forbidden);
		}
		expect(data[0].display_name).toBe('Acme Roofing');
	});

	it('drops the internal normalized_value from contact methods but keeps the real value', () => {
		const { data, meta } = readCsv(archive, 'contact_methods.csv');
		expect(meta.fields).not.toContain('normalized_value');
		expect(meta.fields).not.toContain('organization_id');
		expect(data[0].value).toBe('jane@example.com');
		expect(data[0].client_id).toBe('c1');
		expect(data[0].client_contact_id).toBe('ct1');
	});

	it('drops tax_rate_id and geocode_status from properties', () => {
		const { meta } = readCsv(archive, 'properties.csv');
		expect(meta.fields).not.toContain('tax_rate_id');
		expect(meta.fields).not.toContain('geocode_status');
		expect(meta.fields).not.toContain('organization_id');
	});

	it('carries the note link columns so a note can be rejoined to its client or property', () => {
		const { data, meta } = readCsv(archive, 'notes.csv');
		expect(meta.fields).toEqual([
			'id',
			'entity_type',
			'entity_id',
			'body',
			'pinned',
			'created_at',
			'edited_at'
		]);
		expect(data[0].entity_type).toBe('client');
		expect(data[0].entity_id).toBe('c1');
		// a value with a comma and quotes survives the round trip intact
		expect(data[0].body).toBe('Prefers morning visits, "no weekends".');
	});

	it('writes a manifest that names each file, its row count, key, and joins', () => {
		const manifest = JSON.parse(strFromU8(archive['manifest.json']));
		expect(manifest.export_type).toBe('client_book');
		expect(manifest.schema_version).toBe(1);
		expect(manifest.generated_at).toBe('2026-09-13T12:00:00.000Z');

		const clients = manifest.files.find((f: { name: string }) => f.name === 'clients.csv');
		expect(clients.rows).toBe(1);
		expect(clients.primary_key).toBe('id');

		const contacts = manifest.files.find((f: { name: string }) => f.name === 'contacts.csv');
		expect(contacts.links).toEqual([{ column: 'client_id', references: 'clients.csv:id' }]);
	});
});

describe('clientExportFileName', () => {
	it('is dated so two exports are told apart', () => {
		expect(clientExportFileName(new Date('2026-09-13T12:00:00Z'))).toBe(
			'clients-export-2026-09-13.zip'
		);
	});
});
