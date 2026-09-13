import { describe, expect, it } from 'vitest';
import Papa from 'papaparse';
import { buildCatalogExportCsv, catalogExportFileName } from './catalog-export';

describe('buildCatalogExportCsv', () => {
	it('writes minor-unit money as plain dollars and flags as Yes/No', () => {
		const csv = buildCatalogExportCsv([
			{
				category: 'service',
				name: 'Lawn Mowing',
				description: 'Standard mow',
				unit_label: 'visit',
				unit_price_minor: 4500,
				unit_cost_minor: 1200,
				is_taxable: true,
				is_labor: true,
				archived_at: null
			}
		]);
		const { data, meta } = Papa.parse<Record<string, string>>(csv, {
			header: true,
			skipEmptyLines: true
		});
		expect(meta.fields).toEqual([
			'Name',
			'Type',
			'Description',
			'Unit label',
			'Price',
			'Cost',
			'Taxable',
			'Labor',
			'Archived'
		]);
		expect(data[0]).toMatchObject({
			Name: 'Lawn Mowing',
			Type: 'Service',
			Price: '45.00',
			Cost: '12.00',
			Taxable: 'Yes',
			Labor: 'Yes',
			Archived: 'No'
		});
	});

	it('flags an archived item as Archived: Yes', () => {
		const csv = buildCatalogExportCsv([
			{
				category: 'product',
				name: 'Old Widget',
				description: null,
				unit_label: null,
				unit_price_minor: 0,
				unit_cost_minor: 0,
				is_taxable: false,
				is_labor: false,
				archived_at: '2026-01-01T00:00:00Z'
			}
		]);
		const { data } = Papa.parse<Record<string, string>>(csv, {
			header: true,
			skipEmptyLines: true
		});
		expect(data[0].Type).toBe('Product');
		expect(data[0].Archived).toBe('Yes');
	});
});

describe('catalogExportFileName', () => {
	it('is dated so two exports are told apart', () => {
		expect(catalogExportFileName(new Date('2026-09-13T12:00:00Z'))).toBe(
			'price-book-export-2026-09-13.csv'
		);
	});
});
