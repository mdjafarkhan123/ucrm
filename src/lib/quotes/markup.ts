// Markup is the third seat of the "Unit cost / Markup % / Unit price" row on the new-item form. It is
// never stored — only cost and price are — so these two turn one into the other whenever somebody edits
// the row. Money stays in whole minor units the whole way through; the percentage is the only decimal.

/**
 * What percentage sits between a cost and a price. Empty until both are set — a cost with no price yet
 * is a half-filled form, not a 100% loss, and showing "-100" there only invites somebody to correct it.
 */
export function markupPercentFrom(costMinor: number, priceMinor: number): string {
	if (costMinor <= 0 || priceMinor <= 0) return '';
	const percent = ((priceMinor - costMinor) / costMinor) * 100;
	if (!Number.isFinite(percent)) return '';
	// One decimal is as fine as anybody prices; a whole number shows without a trailing ".0".
	return String(Math.round(percent * 10) / 10);
}

/** The price a cost reaches at this markup, rounded to the nearest whole minor unit. */
export function priceFromMarkup(costMinor: number, percent: number): number {
	const price = Math.round(costMinor * (1 + percent / 100));
	return price < 0 ? 0 : price;
}
