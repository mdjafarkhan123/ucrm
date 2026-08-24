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
	image_attachment_id: string | null;
	quantity?: number;
	unit_price_minor?: number;
	line_total_minor?: number;
};

export type CustomerQuoteAttachment = {
	id: string;
	name: string;
	mime_type: string;
	size_bytes: number;
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

// Null when there is no required deposit. Before Payments exists, this is a fact to arrange with the
// contractor, never a control the customer can pay through.
export type CustomerQuoteDeposit = {
	required_minor: number;
	satisfied: boolean;
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
	business: { name: string | null };
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
