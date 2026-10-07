// Country names and flags straight from a code, with no country table: the browser knows the names
// (CLDR, the same source Google and Apple use) and a flag is just two regional-indicator letters.

let regionNames: Intl.DisplayNames | null | undefined;

/** The browser's own (CLDR) name for a country code, or null when it has none. */
export function browserCountryName(code: string) {
	if (regionNames === undefined) {
		try {
			regionNames = new Intl.DisplayNames(['en'], { type: 'region' });
		} catch {
			regionNames = null;
		}
	}
	try {
		return regionNames?.of(code) ?? null;
	} catch {
		return null;
	}
}

/** "PK" -> "Pakistan" without building the searchable list, for showing a saved country. */
export function countryDisplayName(code: string) {
	return browserCountryName(code.toUpperCase()) ?? code;
}

/** "PK" -> 🇵🇰, from the two regional-indicator letters, so a saved flag needs no country table. */
export function countryFlag(code: string) {
	if (!/^[A-Za-z]{2}$/.test(code)) return '';
	return String.fromCodePoint(
		...[...code.toUpperCase()].map((letter) => 0x1f1a5 + letter.charCodeAt(0))
	);
}
