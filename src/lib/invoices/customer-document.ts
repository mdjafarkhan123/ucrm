// The exact shape `private.invoice_customer_document` returns, written out by hand because the database
// function builds its JSON field by field on purpose: what is missing from this type is the point of it.
// There is no cost, no margin, no internal note and no other client here, and none of those may be added
// without changing the one function that decides what a customer may see.
//
// `money` is null when amounts are withheld — a staff previewer without `invoices.view_price`. The numbers
// never leave the database in that case, rather than being sent and then not drawn. A customer looking at
// their own bill always gets them.

export type CustomerInvoiceLine = {
	line_id: string;
	position: number;
	line_kind: string;
	name: string;
	description: string | null;
	unit_label: string | null;
	quantity: number | null;
	service_date: string | null;
	// Present only when money is included.
	unit_price_minor?: number;
	line_total_minor?: number;
	/**
	 * Progress bills only, and only with money: the whole item, beside `line_total_minor`, which is the share
	 * this bill asks for. Shown as "Item total" next to "Due this invoice".
	 */
	progress_original_amount_minor?: number | null;
};

// Which stage of the agreed payment schedule this bill is. Null on an ordinary invoice. Numbered and named,
// with nothing about the stages that come after it — future installment values never reach the customer.
export type CustomerInvoiceProgress = {
	installment_number: number;
	description: string;
	is_deposit: boolean;
};

export type CustomerInvoiceDiscount = {
	name: string | null;
	type: string;
	value: number;
	amount_minor: number;
};

export type CustomerInvoiceTax = {
	name: string | null;
	rate_basis_points: number | null;
	amount_minor: number;
};

export type CustomerInvoiceMoney = {
	subtotal_minor: number;
	// Null when there was no discount or no tax on the bill.
	discount: CustomerInvoiceDiscount | null;
	tax: CustomerInvoiceTax | null;
	total_minor: number;
	// The deposit-vs-payment split, backed by invoice_payment_allocations grouped by source. Zero when none.
	deposit_applied_minor: number;
	payment_received_minor: number;
	balance_due_minor: number;
};

export type CustomerInvoiceCustomer = {
	client_id: string;
	display_name: string;
	company_name: string | null;
	first_name: string | null;
	last_name: string | null;
	client_type: string;
};

export type CustomerInvoiceAddress = {
	source: 'client' | 'property' | 'none';
	property_id: string | null;
	address_line1?: string | null;
	address_line2?: string | null;
	city?: string | null;
	state_region?: string | null;
	postal_code?: string | null;
	country?: string | null;
};

export type CustomerInvoiceServiceProperty = {
	property_id: string;
	job_id: string | null;
	label: string | null;
	address_line1: string | null;
	address_line2: string | null;
	city: string | null;
	state_region: string | null;
	postal_code: string | null;
	country: string | null;
};

export type CustomerInvoicePaymentTerm = {
	term_id?: string;
	name?: string;
	rule: string;
	net_days?: number | null;
};

export type CustomerInvoiceDocument = {
	business: { name: string | null };
	invoice: {
		invoice_number: number;
		subject: string | null;
		currency_code: string;
		status: string;
		issue_date: string;
		due_date: string;
		due_date_source: string;
		payment_term_snapshot: CustomerInvoicePaymentTerm | null;
		contract_disclaimer: string | null;
	};
	customer: CustomerInvoiceCustomer;
	billing_address: CustomerInvoiceAddress;
	service_properties: CustomerInvoiceServiceProperty[];
	progress: CustomerInvoiceProgress | null;
	lines: CustomerInvoiceLine[];
	money: CustomerInvoiceMoney | null;
};
