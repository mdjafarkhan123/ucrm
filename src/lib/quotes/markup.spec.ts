import { describe, it, expect } from 'vitest';
import { markupPercentFrom, priceFromMarkup } from './markup';

describe('markupPercentFrom', () => {
	it('reads the percentage between a cost and a price', () => {
		expect(markupPercentFrom(1000, 1500)).toBe('50');
		expect(markupPercentFrom(4000, 5000)).toBe('25');
	});

	it('keeps one decimal and drops a trailing zero', () => {
		expect(markupPercentFrom(3000, 3999)).toBe('33.3');
		expect(markupPercentFrom(2000, 3000)).toBe('50');
	});

	it('reads a price below cost as a negative markup', () => {
		expect(markupPercentFrom(2000, 1500)).toBe('-25');
	});

	it('has nothing to show until both a cost and a price are set', () => {
		expect(markupPercentFrom(0, 5000)).toBe('');
		expect(markupPercentFrom(-100, 5000)).toBe('');
		expect(markupPercentFrom(8000, 0)).toBe('');
	});
});

describe('priceFromMarkup', () => {
	it('marks a cost up to a whole minor unit', () => {
		expect(priceFromMarkup(1000, 50)).toBe(1500);
		expect(priceFromMarkup(3333, 33.3)).toBe(4443);
	});

	it('leaves a cost alone at zero markup', () => {
		expect(priceFromMarkup(4550, 0)).toBe(4550);
	});

	it('never lands below zero', () => {
		expect(priceFromMarkup(1000, -250)).toBe(0);
	});
});
