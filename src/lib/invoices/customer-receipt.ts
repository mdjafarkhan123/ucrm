// The exact shape `private.payment_receipt_document` returns, written out by hand for the same reason
// `customer-document.ts` is: what is missing from this type is the point of it. A receipt is Jobber's field
// set and nothing more — no receipt number, no invoice number, no line items, no balance. None of those may
// be added here without changing the one database function that decides what a customer may see.
//
// A payment is immutable once recorded, so unlike an invoice there is no status, no revision and no
// withheld-money case: whoever holds the link sees the amount, because a receipt with the number removed is
// not a receipt.

export type CustomerReceiptAddress = {
	address_line1: string | null;
	address_line2: string | null;
	city: string | null;
	state_region: string | null;
	postal_code: string | null;
	country: string | null;
};

export type CustomerPaymentReceipt = {
	business: { name: string | null };
	receipt: {
		amount_minor: number;
		currency_code: string;
		// A `date` column, so `YYYY-MM-DD` — never a timestamp.
		transaction_date: string;
		method: string;
		reference: string | null;
		details: string | null;
	};
	recipient: {
		display_name: string | null;
		company_name: string | null;
		// Null when the settled invoice carried no billing address, or the payment settled nothing.
		address: CustomerReceiptAddress | null;
	};
};
