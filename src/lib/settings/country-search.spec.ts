import { countryDisplayName, countryFlag } from './country-names';
import { describe, expect, it } from 'vitest';
import { allCountryOptions, normaliseCountryText, searchCountries } from './country-search';

const codes = (query: string) => searchCountries(query).map((country) => country.code);

describe('country search', () => {
	it('lists every country alphabetically for an empty search', () => {
		const all = allCountryOptions();
		expect(searchCountries('')).toHaveLength(all.length);
		expect(all.length).toBeGreaterThan(240);
		const names = all.map((country) => country.name);
		expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b)));
	});

	it('finds countries by the everyday names people type', () => {
		expect(codes('uk')[0]).toBe('GB');
		expect(codes('england')[0]).toBe('GB');
		expect(codes('usa')[0]).toBe('US');
		expect(codes('holland')[0]).toBe('NL');
		expect(codes('ivory')[0]).toBe('CI');
		expect(codes('uae')[0]).toBe('AE');
	});

	it('matches the ISO code exactly before names that merely start with it', () => {
		expect(codes('pk')[0]).toBe('PK');
		expect(codes('in')[0]).toBe('IN');
	});

	it('ranks names starting with the search above names merely containing it', () => {
		const results = codes('pak');
		expect(results[0]).toBe('PK');
		expect(codes('land').indexOf('FI')).toBeGreaterThan(-1);
		expect(codes('ger')[0]).toBe('DE');
		expect(codes('ger').indexOf('DE')).toBeLessThan(codes('ger').indexOf('NG'));
	});

	it('ignores accents and punctuation', () => {
		expect(codes('cote d ivoire')[0]).toBe('CI');
		expect(codes('reunion')[0]).toBe('RE');
		expect(codes('Turkiye')[0]).toBe('TR');
		expect(normaliseCountryText('Côte d’Ivoire')).toBe('cote d ivoire');
	});

	it('returns nothing for gibberish', () => {
		expect(codes('zzqx')).toEqual([]);
	});

	it('names and flags a saved code without building the list', () => {
		expect(countryDisplayName('pk')).toBe('Pakistan');
		expect(countryFlag('PK')).toBe('🇵🇰');
		expect(countryFlag('')).toBe('');
	});
});
