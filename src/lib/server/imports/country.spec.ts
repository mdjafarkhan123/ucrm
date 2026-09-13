import { describe, expect, it } from 'vitest';
import { normalizeCountryToIso2 } from './country';

describe('normalizeCountryToIso2', () => {
	it('converts full country names to their ISO alpha-2 code', () => {
		expect(normalizeCountryToIso2('United States')).toBe('US');
		expect(normalizeCountryToIso2('Canada')).toBe('CA');
		expect(normalizeCountryToIso2('United Kingdom')).toBe('GB');
		expect(normalizeCountryToIso2('Australia')).toBe('AU');
	});

	it('accepts common aliases, case-insensitively', () => {
		expect(normalizeCountryToIso2('USA')).toBe('US');
		expect(normalizeCountryToIso2('  united states of america ')).toBe('US');
		expect(normalizeCountryToIso2('Great Britain')).toBe('GB');
		expect(normalizeCountryToIso2('England')).toBe('GB');
	});

	it('passes an existing 2-letter code through, upper-cased', () => {
		expect(normalizeCountryToIso2('us')).toBe('US');
		expect(normalizeCountryToIso2('FR')).toBe('FR');
	});

	it('leaves an unrecognised name unchanged so validation reports it as a fixable error', () => {
		expect(normalizeCountryToIso2('Freedonia')).toBe('Freedonia');
	});

	it('returns empty for an empty cell so the schema default can apply', () => {
		expect(normalizeCountryToIso2('')).toBe('');
		expect(normalizeCountryToIso2(null)).toBe('');
		expect(normalizeCountryToIso2(undefined)).toBe('');
	});
});
