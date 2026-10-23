// Prints the SQL rows for private.sms_phone_country_prefixes: which country a phone number belongs to, by its
// longest matching leading digits. Built from libphonenumber-js (Google's libphonenumber data), so the database
// can tell a customer's country from an E.164 number without the app. Re-run after a libphonenumber-js upgrade:
//   node scripts/generate-phone-country-prefixes.mjs > rows.sql
import { createRequire } from 'node:module';
import { parsePhoneNumberFromString } from 'libphonenumber-js/max';

const metadata = createRequire(import.meta.url)('libphonenumber-js/metadata.max.json');

// Shared calling codes split by area code (+1) or by a few more digits (+44 7781 is Guernsey), so every
// prefix is checked to MIN_DEPTH digits and a mixed one down to MAX_DEPTH.
const MIN_DEPTH = 3;
const MAX_DEPTH = 5;
const SAMPLES = 60;

// Each calling code lists its main country first (US for +1, GB for +44).
const regionsByCode = new Map(Object.entries(metadata.country_calling_codes));

// Deterministic digits so the output never changes between runs.
let seed = 42;
const digit = () => {
	seed = (seed * 1664525 + 1013904223) >>> 0;
	return String(Math.floor((seed / 2 ** 32) * 10));
};

// The national number lengths any country on this calling code allows.
const lengthsFor = (regions) =>
	[...new Set(regions.flatMap((region) => metadata.countries[region]?.[3] ?? []))].sort();

const countriesAfter = (code, national, lengths) => {
	const votes = new Map();
	for (let i = 0; i < SAMPLES; i += 1) {
		for (const length of lengths) {
			if (length <= national.length) continue;
			let rest = '';
			while (national.length + rest.length < length) rest += digit();
			const parsed = parsePhoneNumberFromString(`+${code}${national}${rest}`);
			if (parsed?.isValid() && parsed.country) {
				votes.set(parsed.country, (votes.get(parsed.country) ?? 0) + 1);
			}
		}
	}
	return votes;
};

const rows = [];
const walk = (code, national, inherited, lengths) => {
	const votes = countriesAfter(code, national, lengths);
	if (votes.size === 0 && national.length >= MIN_DEPTH) return;
	const [top] = [...votes.entries()].sort((a, b) => b[1] - a[1]);
	if ((votes.size === 1 && national.length >= MIN_DEPTH) || national.length >= MAX_DEPTH) {
		if (top && top[0] !== inherited) rows.push([code + national, top[0]]);
		return;
	}
	for (let d = 0; d <= 9; d += 1) walk(code, national + d, inherited, lengths);
};

for (const [code, regions] of [...regionsByCode.entries()].sort()) {
	const home = regions[0];
	rows.push([code, home]);
	if (regions.length > 1) walk(code, '', home, lengthsFor(regions));
}

console.log(
	rows
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([prefix, country]) => `('${prefix}', '${country}')`)
		.join(',\n')
);
