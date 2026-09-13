// Real-world exports (HubSpot, Jobber, spreadsheets) write the country as a full name -- "United States",
// "Canada" -- but our property schema stores a 2-letter ISO code and rejects anything else, which would turn
// every property row into an error. This normalizes a mapped country cell to its ISO 3166-1 alpha-2 code
// before validation.
//
// Scope is deliberate: the countries our contractors actually serve, plus the spellings those exports use. A
// value we do not recognise is returned unchanged so it fails the 2-letter check as a normal, fixable row
// error -- we never silently guess a country for someone.

// Full names and common aliases -> ISO alpha-2. Keys are compared lowercased and trimmed.
const NAME_TO_ISO2: Record<string, string> = {
	'united states': 'US',
	'united states of america': 'US',
	usa: 'US',
	'u.s.': 'US',
	'u.s.a.': 'US',
	us: 'US',
	america: 'US',

	canada: 'CA',
	ca: 'CA',

	'united kingdom': 'GB',
	uk: 'GB',
	'u.k.': 'GB',
	'great britain': 'GB',
	britain: 'GB',
	england: 'GB',
	scotland: 'GB',
	wales: 'GB',
	'northern ireland': 'GB',
	gb: 'GB',

	australia: 'AU',
	au: 'AU',

	'new zealand': 'NZ',
	nz: 'NZ',

	ireland: 'IE',
	'republic of ireland': 'IE',
	ie: 'IE'
};

// Return the ISO alpha-2 code for a country cell, or the original trimmed value when we do not recognise it
// (so downstream validation reports it as a fixable error rather than importing a wrong guess). An empty cell
// stays empty so the schema default can apply.
export function normalizeCountryToIso2(value: string | undefined | null): string {
	const trimmed = (value ?? '').trim();
	if (!trimmed) return '';

	const match = NAME_TO_ISO2[trimmed.toLowerCase()];
	if (match) return match;

	// A bare 2-letter code we do not have in the table (e.g. "FR") is still a valid-shaped ISO code; upper-case
	// it and let it through unchanged.
	if (/^[A-Za-z]{2}$/.test(trimmed)) return trimmed.toUpperCase();

	return trimmed;
}
