import { Country } from 'country-state-city';

// The searchable country list behind CountryPicker. It follows GOV.UK's accessible-autocomplete country
// picker: match the official name, the ISO code, and the everyday names people actually type ("UK", "USA",
// "Holland"), ignore accents, and rank whole-name and starts-with matches above loose ones.

export type CountryOption = {
	/** ISO 3166-1 alpha-2 code — what forms save. */
	code: string;
	/** The name shown, from the browser's own (CLDR) country names when it has one. */
	name: string;
	flag: string;
};

type IndexedCountry = CountryOption & {
	/** Every name a person might type for this country, normalised. The first is the shown name. */
	names: string[];
	/** Each word of those names, for "word starts with" matches like "rica" in "Costa Rica". */
	words: string[];
};

// Everyday names the official and library names leave out.
const ALIASES: Record<string, string[]> = {
	AE: ['UAE', 'Emirates', 'Dubai', 'Abu Dhabi'],
	BA: ['Bosnia'],
	CD: ['DRC', 'DR Congo', 'Congo Kinshasa', 'Zaire'],
	CG: ['Congo Brazzaville', 'Republic of the Congo'],
	CI: ['Ivory Coast'],
	CV: ['Cape Verde'],
	CZ: ['Czech Republic'],
	GB: ['UK', 'Britain', 'Great Britain', 'England', 'Scotland', 'Wales', 'Northern Ireland'],
	KP: ['North Korea', 'DPRK'],
	KR: ['South Korea', 'Korea'],
	LA: ['Laos'],
	MK: ['Macedonia'],
	MM: ['Burma'],
	NL: ['Holland', 'The Netherlands'],
	PS: ['Palestine'],
	RU: ['Russian Federation'],
	SA: ['KSA'],
	SZ: ['Swaziland'],
	TL: ['East Timor'],
	TR: ['Turkey', 'Turkiye'],
	TW: ['Republic of China'],
	US: ['USA', 'US', 'America', 'United States of America'],
	VA: ['Holy See', 'Vatican'],
	VN: ['Viet Nam']
};

/** Lower case, accents and punctuation removed: "Côte d’Ivoire" -> "cote d ivoire". */
export function normaliseCountryText(text: string) {
	return text
		.normalize('NFD')
		.replace(/\p{Diacritic}/gu, '')
		.toLowerCase()
		.replace(/&/g, ' and ')
		.replace(/[^\p{Letter}\p{Number}]+/gu, ' ')
		.trim();
}

function browserName(code: string, names: Intl.DisplayNames | null) {
	try {
		return names?.of(code) ?? null;
	} catch {
		return null;
	}
}

function buildIndex(): IndexedCountry[] {
	let displayNames: Intl.DisplayNames | null = null;
	try {
		displayNames = new Intl.DisplayNames(['en'], { type: 'region' });
	} catch {
		displayNames = null;
	}
	return Country.getAllCountries()
		.map((country) => {
			const name = browserName(country.isoCode, displayNames) ?? country.name;
			const names = [
				...new Set(
					[name, country.name, ...(ALIASES[country.isoCode] ?? [])].map(normaliseCountryText)
				)
			];
			return {
				code: country.isoCode,
				name,
				flag: country.flag,
				names,
				words: [...new Set(names.flatMap((item) => item.split(' ')))]
			};
		})
		.sort((a, b) => a.name.localeCompare(b.name));
}

let index: IndexedCountry[] | null = null;

/** Every country, alphabetical. Built once, on first use. */
export function allCountryOptions(): CountryOption[] {
	index ??= buildIndex();
	return index;
}

export function findCountryOption(code: string | null | undefined) {
	if (!code) return undefined;
	const upper = code.toUpperCase();
	return allCountryOptions().find((country) => country.code === upper);
}

function matchRank(country: IndexedCountry, query: string) {
	if (country.code.toLowerCase() === query) return 0;
	if (country.names.includes(query)) return 0;
	if (country.names[0].startsWith(query)) return 1;
	if (country.names.some((name) => name.startsWith(query))) return 2;
	if (country.words.some((word) => word.startsWith(query))) return 3;
	if (country.names.some((name) => name.includes(query))) return 4;
	return -1;
}

/** Countries matching what was typed, best match first; the whole list for an empty search. */
export function searchCountries(query: string): CountryOption[] {
	const countries = allCountryOptions() as IndexedCountry[];
	const needle = normaliseCountryText(query);
	if (!needle) return countries;
	const ranked: { country: IndexedCountry; rank: number }[] = [];
	for (const country of countries) {
		const rank = matchRank(country, needle);
		if (rank >= 0) ranked.push({ country, rank });
	}
	// Array sort is stable, so equal ranks stay alphabetical.
	return ranked.sort((a, b) => a.rank - b.rank).map((item) => item.country);
}
