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

// Money a customer paid online through the contractor's Stripe account. Only Stripe's confirmation records
// these, so they are shown in history but never offered in the Record payment form.
export const ONLINE_PAYMENT_METHODS = ['stripe_card', 'stripe_bank', 'stripe_other'] as const;

export type OnlinePaymentMethod = (typeof ONLINE_PAYMENT_METHODS)[number];

/** Any method a recorded payment can carry. */
export type PaymentMethod = InvoicePaymentMethod | OnlinePaymentMethod;

export const INVOICE_PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
	other: 'Other',
	bank_transfer: 'Bank transfer',
	cash: 'Cash',
	check: 'Check',
	card_external: 'Credit/debit card',
	paypal: 'PayPal',
	stripe_card: 'Card (online)',
	stripe_bank: 'Bank payment (online)',
	stripe_other: 'Online payment'
};

export const INVOICE_PAYMENT_METHOD_OPTIONS = INVOICE_PAYMENT_METHODS.map((value) => ({
	value,
	label: INVOICE_PAYMENT_METHOD_LABELS[value]
}));
