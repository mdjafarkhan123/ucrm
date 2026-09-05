// The six manual methods the contract names — none of them processes a payment; each just acknowledges money
// received elsewhere. Same order and spelling as the database's check constraint and the server Zod schema.
export const INVOICE_PAYMENT_METHODS = [
	'other',
	'bank_transfer',
	'cash',
	'check',
	'card_external',
	'paypal'
] as const;

export type InvoicePaymentMethod = (typeof INVOICE_PAYMENT_METHODS)[number];

export const INVOICE_PAYMENT_METHOD_LABELS: Record<InvoicePaymentMethod, string> = {
	other: 'Other',
	bank_transfer: 'Bank transfer',
	cash: 'Cash',
	check: 'Check',
	card_external: 'Credit/debit card',
	paypal: 'PayPal'
};

export const INVOICE_PAYMENT_METHOD_OPTIONS = INVOICE_PAYMENT_METHODS.map((value) => ({
	value,
	label: INVOICE_PAYMENT_METHOD_LABELS[value]
}));
