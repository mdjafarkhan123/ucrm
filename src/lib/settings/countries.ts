import { Country } from 'country-state-city';
import { COMMON_CURRENCIES } from '$lib/settings/currencies';

// Every country, by ISO code, for the pickers that save the code rather than the typed name.
export const COUNTRIES = Country.getAllCountries()
	.map((country) => ({ value: country.isoCode, label: country.name }))
	.sort((a, b) => a.label.localeCompare(b.label));

/** The currency a business in this country most likely charges in, when it is one we offer. */
export function countryCurrency(countryCode: string | null | undefined): string | null {
	if (!countryCode) return null;
	const currency = Country.getCountryByCode(countryCode.toUpperCase())?.currency;
	return COMMON_CURRENCIES.some((item) => item.code === currency) ? (currency ?? null) : null;
}
