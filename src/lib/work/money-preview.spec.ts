import { describe, expect, it } from 'vitest';
import { previewMoney } from './money-preview';

describe('previewMoney', () => {
	it('takes a percentage discount off the subtotal and taxes what is left', () => {
		// The edit drawing's figures: $4,360.00, 5% off, 8% tax.
		const result = previewMoney(
			[
				{ line_total_minor: 216000, is_taxable: true },
				{ line_total_minor: 35000, is_taxable: true },
				{ line_total_minor: 185000, is_taxable: true }
			],
			{ type: 'percentage', value: 500 },
			800
		);
		expect(result).toEqual({
			subtotal_minor: 436000,
			discount_minor: 21800,
			tax_minor: 33136,
			total_minor: 447336
		});
	});

	it('takes the discount from untaxed lines first', () => {
		const result = previewMoney(
			[
				{ line_total_minor: 10000, is_taxable: true },
				{ line_total_minor: 3000, is_taxable: false }
			],
			{ type: 'fixed', value: 5000 },
			1000
		);
		// $30 comes off the untaxed line, $20 off the taxed one, so tax is 10% of $80.
		expect(result.discount_minor).toBe(5000);
		expect(result.tax_minor).toBe(800);
		expect(result.total_minor).toBe(13000 - 5000 + 800);
	});

	it('never discounts more than the subtotal', () => {
		const result = previewMoney(
			[{ line_total_minor: 2000, is_taxable: true }],
			{ type: 'fixed', value: 9000 },
			0
		);
		expect(result.discount_minor).toBe(2000);
		expect(result.total_minor).toBe(0);
	});

	it('rounds tax per line, giving leftover discount cents to the earliest lines', () => {
		const result = previewMoney(
			[
				{ line_total_minor: 1, is_taxable: true },
				{ line_total_minor: 1, is_taxable: true },
				{ line_total_minor: 1, is_taxable: true }
			],
			{ type: 'fixed', value: 1 },
			5000
		);
		// The one cent off lands on the first line: tax is 0 + round(0.5) + round(0.5) = 2.
		expect(result.tax_minor).toBe(2);
	});

	it('charges nothing extra with no discount and no tax', () => {
		expect(previewMoney([{ line_total_minor: 4500, is_taxable: true }], null, 0)).toEqual({
			subtotal_minor: 4500,
			discount_minor: 0,
			tax_minor: 0,
			total_minor: 4500
		});
	});
});
