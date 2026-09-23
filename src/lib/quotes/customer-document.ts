import type { PayByAppMethods } from '$lib/payments/pay-by-app';

// The exact shape `resolve_quote_access_link` returns. It is written out by hand because the database
// function builds its JSON field by field on purpose: what is missing from this type is the point of it.
// There is no cost, no margin, no catalog source, no private note and no second recipient here, and none
// of those may be added without changing the function that decides what a customer may see.
//
// Quantities, unit prices and line totals are optional because the version's visibility switches decide
// whether the number is in the payload at all, rather than hiding it in the browser.

export type CustomerQuoteLine = {
	id: string;
	position: number;
	line_kind: string;
	selection_kind: string;
	is_recommended: boolean;
	category: string | null;
	name: string;
	description: string | null;
	unit_label: string | null;
	image_file_id: string | null;
	/** True only when this line had a photo and it was later moved to Trash — never for a line with none. */
	image_removed: boolean;
	quantity?: number;
	unit_price_minor?: number;
	line_total_minor?: number;
};

export type CustomerQuoteAttachment = {
	/** Null once `removed` is true — the server withholds the file's own facts, not just its bytes. */
	id: string | null;
	name: string | null;
	mime_type: string | null;
	size_bytes: number | null;
	removed: boolean;
};

export type CustomerQuoteTotals = {
	subtotal_minor: number;
	discount_name: string | null;
	discount_minor: number;
	tax_name: string | null;
	tax_rate_basis_points: number | null;
	tax_minor: number;
	total_minor: number;
};

// Null when there is no required deposit.
export type CustomerQuoteDeposit = {
	required_minor: number;
	satisfied: boolean;
};

// Online deposit payment on the customer's copy (online payments Part 4). Built by the server from
// `quote_online_deposit_context`; null when there is nothing at all to show. Amounts and switches only --
// nothing here identifies the business, the quote row or the Stripe account.
export type CustomerQuoteDepositPayment = {
	/** A Pay deposit button may be shown right now. False when Stripe isn't connected -- pay_by_app may still apply. */
	available: boolean;
	deposit_required_minor: number;
	test_mode: boolean;
	pay_by_app: PayByAppMethods | null;
};

export type CustomerQuoteDocument = {
	quote: {
		quote_number: number;
		status: string;
		sent_at: string | null;
		decision: string | null;
		decided_at: string | null;
	};
	recipient: { name: string; email: string };
	business: { name: string | null; brand_color: string | null; has_logo: boolean };
	document: {
		version_number: number;
		published_at: string | null;
		currency_code: string;
		client_display_name: string | null;
		service_address_line1: string | null;
		service_address_line2: string | null;
		service_city: string | null;
		service_state_region: string | null;
		service_postal_code: string | null;
		service_country: string | null;
		introduction: string | null;
		client_message: string | null;
		contract_disclaimer: string | null;
		show_quantities: boolean;
		show_unit_prices: boolean;
		show_line_totals: boolean;
		show_totals: boolean;
	};
	lines: CustomerQuoteLine[];
	attachments: CustomerQuoteAttachment[];
	// Null when the version hides totals: the numbers never leave the database, rather than being sent
	// and then not drawn.
	totals: CustomerQuoteTotals | null;
	deposit: CustomerQuoteDeposit | null;
};
