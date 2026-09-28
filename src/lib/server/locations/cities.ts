import { City } from 'country-state-city';

export type CityMatch = { name: string; stateCode: string };

type IndexedCity = CityMatch & { search: string };

const MAX_RESULTS = 50;
const citiesByCountry = new Map<string, IndexedCity[]>();

function citiesOf(countryCode: string): IndexedCity[] {
	let cities = citiesByCountry.get(countryCode);
	if (cities) return cities;

	const seen = new Set<string>();
	cities = [];
	for (const city of City.getCitiesOfCountry(countryCode) ?? []) {
		const key = `${city.name}|${city.stateCode}`;
		if (seen.has(key)) continue;
		seen.add(key);
		cities.push({ name: city.name, stateCode: city.stateCode, search: city.name.toLowerCase() });
	}
	citiesByCountry.set(countryCode, cities);
	return cities;
}

export function searchCities(countryCode: string, query: string): CityMatch[] {
	const needle = query.trim().toLowerCase();
	const startsWith: IndexedCity[] = [];
	const contains: IndexedCity[] = [];

	for (const city of citiesOf(countryCode)) {
		if (!needle || city.search.startsWith(needle)) startsWith.push(city);
		else if (city.search.includes(needle)) contains.push(city);
		if (startsWith.length >= MAX_RESULTS) break;
	}

	return [...startsWith, ...contains]
		.slice(0, MAX_RESULTS)
		.map(({ name, stateCode }) => ({ name, stateCode }));
}
