/** Whole currency units, as the list pages' overview cards write them. */
export function formatWhole(amountMinor: number, currency: string, locale: string): string {
	return new Intl.NumberFormat(locale, {
		style: 'currency',
		currency,
		maximumFractionDigits: 0
	}).format(amountMinor / 100);
}
