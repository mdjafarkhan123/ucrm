import { describe, expect, it } from 'vitest';
import {
	normalizeCatalogName,
	runCatalogReview,
	type CatalogReviewInputs,
	type ExistingCatalogItem
} from './catalog-review';

const MAPPING: CatalogReviewInputs['mapping'] = {
	Name: { field: 'name' },
	Type: { field: 'category' },
	Description: { field: 'description' },
	Unit: { field: 'unit_label' },
	Price: { field: 'unit_price' },
	Cost: { field: 'unit_cost' },
	Taxable: { field: 'is_taxable' },
	Labor: { field: 'is_labor' }
};

// Assemble runCatalogReview inputs, letting each test override only what it cares about.
function review(
	rows: Record<string, string>[],
	overrides: Partial<CatalogReviewInputs> = {}
): ReturnType<typeof runCatalogReview> {
	return runCatalogReview({
		rows,
		mapping: MAPPING,
		matchAction: 'skip',
		existingByName: new Map(),
		...overrides
	});
}

function existing(
	partial: Partial<ExistingCatalogItem> & { id: string; name: string }
): ExistingCatalogItem {
	return {
		revision: 1,
		category: 'service',
		description: null,
		unit_label: null,
		unit_price_minor: 0,
		unit_cost_minor: 0,
		is_taxable: true,
		is_labor: false,
		...partial
	};
}

describe('runCatalogReview — create', () => {
	it('creates a new item with cost, defaulting taxable to yes and labor to no', () => {
		const { rows, summary } = review([
			{ Name: 'Lawn Mowing', Type: 'Service', Price: '45.00', Cost: '12.00' }
		]);
		expect(summary.create).toBe(1);
		expect(rows[0].planned_action).toBe('create');
		expect(rows[0].resolved_item).toMatchObject({
			name: 'Lawn Mowing',
			category: 'service',
			unit_price_minor: 4500,
			unit_cost_minor: 1200,
			is_taxable: true,
			is_labor: false
		});
	});

	it('accepts plural Product/Service aliases and Yes/No flags', () => {
		const { rows } = review([
			{ Name: 'Mulch', Type: 'products', Taxable: 'no', Labor: 'yes', Price: '', Cost: '' }
		]);
		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].error_message).toBe('Labor is always a service.');
	});

	it('defaults price and cost to zero when left blank', () => {
		const { rows } = review([{ Name: 'Consultation', Type: 'Service' }]);
		expect(rows[0].resolved_item).toMatchObject({ unit_price_minor: 0, unit_cost_minor: 0 });
	});
});

describe('runCatalogReview — errors', () => {
	it('requires a name', () => {
		const { rows, summary } = review([{ Type: 'Service' }]);
		expect(summary.error).toBe(1);
		expect(rows[0].planned_action).toBe('error');
	});

	it('requires a category on create', () => {
		const { rows } = review([{ Name: 'Nameless Thing' }]);
		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].error_message).toBe('Choose Product or Service for this item.');
	});

	it('rejects a category that is not Product or Service', () => {
		const { rows } = review([{ Name: 'Widget', Type: 'Gadget' }]);
		expect(rows[0].planned_action).toBe('error');
	});

	it('rejects an unparsable price', () => {
		const { rows } = review([{ Name: 'Widget', Type: 'Product', Price: 'a lot' }]);
		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].error_message).toBe('"a lot" is not a valid price.');
	});

	it('rejects an unparsable cost', () => {
		const { rows } = review([{ Name: 'Widget', Type: 'Product', Cost: 'free-ish' }]);
		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].error_message).toBe('"free-ish" is not a valid cost.');
	});
});

describe('runCatalogReview — matching', () => {
	it('skips a row that matches an active item by name when the action is skip', () => {
		const { rows, summary } = review([{ Name: 'Lawn Mowing', Type: 'Service' }], {
			existingByName: new Map([
				[normalizeCatalogName('Lawn Mowing'), existing({ id: 'item-a', name: 'Lawn Mowing' })]
			])
		});
		expect(summary.skip).toBe(1);
		expect(rows[0].planned_action).toBe('skip');
		expect(rows[0].match_item_id).toBe('item-a');
	});

	it('matches case- and whitespace-insensitively', () => {
		const { rows } = review([{ Name: '  lawn   mowing ', Type: 'Service' }], {
			existingByName: new Map([
				[normalizeCatalogName('Lawn Mowing'), existing({ id: 'item-a', name: 'Lawn Mowing' })]
			])
		});
		expect(rows[0].planned_action).toBe('skip');
	});

	it('updates only the changed fields when the action is update', () => {
		const { rows, summary } = review([{ Name: 'Lawn Mowing', Price: '50.00' }], {
			matchAction: 'update',
			existingByName: new Map([
				[
					normalizeCatalogName('Lawn Mowing'),
					existing({ id: 'item-a', name: 'Lawn Mowing', unit_price_minor: 4500 })
				]
			])
		});
		expect(summary.update).toBe(1);
		expect(rows[0].resolved_item).toMatchObject({ unit_price_minor: 5000, category: 'service' });
	});

	it('respects "don\'t overwrite" and skips as already up to date when nothing changes', () => {
		const mapping: CatalogReviewInputs['mapping'] = {
			Name: { field: 'name' },
			Price: { field: 'unit_price', dont_overwrite: true }
		};
		const { rows } = runCatalogReview({
			rows: [{ Name: 'Lawn Mowing', Price: '999.00' }],
			mapping,
			matchAction: 'update',
			existingByName: new Map([
				[
					normalizeCatalogName('Lawn Mowing'),
					existing({ id: 'item-a', name: 'Lawn Mowing', unit_price_minor: 4500 })
				]
			])
		});
		expect(rows[0].planned_action).toBe('skip');
		expect(rows[0].flags).toContain('already_up_to_date');
	});

	it('refuses an update that would make a labor item a product', () => {
		const mapping: CatalogReviewInputs['mapping'] = {
			Name: { field: 'name' },
			Type: { field: 'category' }
		};
		const { rows } = runCatalogReview({
			rows: [{ Name: 'Lawn Mowing', Type: 'Product' }],
			mapping,
			matchAction: 'update',
			existingByName: new Map([
				[
					normalizeCatalogName('Lawn Mowing'),
					existing({ id: 'item-a', name: 'Lawn Mowing', is_labor: true })
				]
			])
		});
		expect(rows[0].planned_action).toBe('error');
		expect(rows[0].error_message).toBe('Labor is always a service.');
	});
});

describe('runCatalogReview — in-file first wins', () => {
	it('lets the first row claim a name and holds a later row with the same name', () => {
		const { rows, summary } = review([
			{ Name: 'Lawn Mowing', Type: 'Service' },
			{ Name: 'lawn  mowing', Type: 'Service' }
		]);
		expect(rows[0].planned_action).toBe('create');
		expect(rows[1].planned_action).toBe('hold');
		expect(rows[1].flags).toContain('duplicate_name_in_file');
		expect(summary.hold).toBe(1);
	});
});
