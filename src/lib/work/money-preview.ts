// What a priced record will come to while someone is still editing it: the same arithmetic the database's
// calculate functions use (`private.calculate_invoice` and its quote and job twins), run in the browser so
// the editor's discount, tax and total move as the person types. The saved figures still come from the
// database; this is only the preview until Save.
//
// The order matters and follows the database exactly: the discount comes off the whole subtotal, is taken
// from the untaxed lines first, then spread across each group's lines in proportion (whole cents, the
// leftover cents going to the earliest lines), and tax is rounded per taxed line on what is left of it.

export type PreviewLine = { line_total_minor: number; is_taxable: boolean };

export type PreviewDiscount = { type: 'percentage' | 'fixed'; value: number } | null;

export type MoneyPreview = {
	subtotal_minor: number;
	discount_minor: number;
	tax_minor: number;
	total_minor: number;
};

export function previewMoney(
	lines: PreviewLine[],
	discount: PreviewDiscount,
	taxRateBasisPoints: number
): MoneyPreview {
	const subtotal = lines.reduce((sum, line) => sum + line.line_total_minor, 0);
	const untaxedTotal = lines
		.filter((line) => !line.is_taxable)
		.reduce((sum, line) => sum + line.line_total_minor, 0);
	const taxedTotal = subtotal - untaxedTotal;

	let discountMinor = 0;
	if (discount?.type === 'fixed') discountMinor = Math.min(discount.value, subtotal);
	else if (discount?.type === 'percentage')
		discountMinor = Math.round((subtotal * discount.value) / 10000);

	const untaxedDiscount = Math.min(discountMinor, untaxedTotal);
	const taxedDiscount = discountMinor - untaxedDiscount;

	// Only the taxed group's share of the discount changes the tax, so only it is spread line by line.
	const taxed = lines.filter((line) => line.is_taxable);
	const raw = taxed.map((line) =>
		taxedTotal === 0 || taxedDiscount === 0
			? 0
			: Math.floor((taxedDiscount * line.line_total_minor) / taxedTotal)
	);
	const remainder = taxedDiscount - raw.reduce((sum, share) => sum + share, 0);
	const taxMinor = taxed.reduce((sum, line, index) => {
		const share = raw[index] + (index < remainder ? 1 : 0);
		return sum + Math.round(((line.line_total_minor - share) * taxRateBasisPoints) / 10000);
	}, 0);

	return {
		subtotal_minor: subtotal,
		discount_minor: discountMinor,
		tax_minor: taxMinor,
		total_minor: subtotal - discountMinor + taxMinor
	};
}
