import { describe, expect, it } from 'vitest';
import {
	BRAND_QUICK_PICKS,
	normaliseColourCode,
	readsClearlyWithWhite,
	whiteContrast
} from './brand-colour';

describe('normaliseColourCode', () => {
	it('accepts six digits with or without the hash, in any case', () => {
		expect(normaliseColourCode('#0F766E')).toBe('#0f766e');
		expect(normaliseColourCode(' 0f766e ')).toBe('#0f766e');
	});
	it('expands three digits', () => {
		expect(normaliseColourCode('#0f6')).toBe('#00ff66');
	});
	it('refuses anything else', () => {
		expect(normaliseColourCode('')).toBeNull();
		expect(normaliseColourCode('#12345')).toBeNull();
		expect(normaliseColourCode('green')).toBeNull();
	});
});

describe('white words on a colour', () => {
	it('puts black at 21 and white at 1', () => {
		expect(Math.round(whiteContrast('#000000'))).toBe(21);
		expect(Math.round(whiteContrast('#ffffff'))).toBe(1);
	});
	it('flags a pale colour and passes a deep one', () => {
		expect(readsClearlyWithWhite('#fde68a')).toBe(false);
		expect(readsClearlyWithWhite('#0f766e')).toBe(true);
	});
	it('keeps every quick pick readable', () => {
		for (const pick of BRAND_QUICK_PICKS) expect(readsClearlyWithWhite(pick)).toBe(true);
	});
});
