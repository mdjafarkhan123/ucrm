import { describe, expect, it } from 'vitest';
import { searchCities } from './cities';

describe('searchCities', () => {
	it('puts names that start with the search before names that only contain it', () => {
		const results = searchCities('GB', 'lon');
		expect(results[0].name.toLowerCase().startsWith('lon')).toBe(true);
		expect(results.some((city) => city.name === 'London')).toBe(true);
	});

	it('only returns cities in the chosen country, capped at 50', () => {
		expect(searchCities('US', '')).toHaveLength(50);
		expect(searchCities('GB', 'Chicago')).toEqual([]);
	});

	it('lists each name and state once', () => {
		const keys = searchCities('US', 'spring').map((city) => `${city.name}|${city.stateCode}`);
		expect(new Set(keys).size).toBe(keys.length);
	});
});
