// Venmo, Cash App, PayPal.me, Zelle and Interac e-Transfer (docs/online-payments-behavior-contract.md §6).
// None of these are processed by UCRM, so this module only builds the same links a contractor could hand a
// customer themselves -- the sources behind each format: Venmo's `?txn=pay&amount=&note=` deep link, Cash
// App's `/$cashtag/amount` and PayPal.me's `/username/amountCURRENCY`. Zelle and Interac e-Transfer have no
// such link anywhere -- both move money bank-to-bank from the sender's own banking app -- so those two and a
// free-text bank transfer stay copy-only.

export type PayByAppMethods = {
	venmo_username: string | null;
	cash_app_cashtag: string | null;
	paypal_me_username: string | null;
	zelle_contact: string | null;
	e_transfer_email: string | null;
	bank_transfer_instructions: string | null;
};

export function hasAnyPayByAppMethod(methods: PayByAppMethods | null | undefined): boolean {
	if (!methods) return false;
	return Object.values(methods).some((value) => value !== null && value !== '');
}

function formatAmount(amountMinor: number): string {
	return (amountMinor / 100).toFixed(2);
}

export function venmoPayLink(username: string, amountMinor: number, note: string): string {
	const params = new URLSearchParams({ txn: 'pay', amount: formatAmount(amountMinor), note });
	return `https://venmo.com/u/${encodeURIComponent(username)}?${params.toString()}`;
}

export function cashAppPayLink(cashtag: string, amountMinor: number): string {
	return `https://cash.app/$${encodeURIComponent(cashtag)}/${formatAmount(amountMinor)}`;
}

export function paypalMeLink(username: string, amountMinor: number, currencyCode: string): string {
	return `https://paypal.me/${encodeURIComponent(username)}/${formatAmount(amountMinor)}${currencyCode.toUpperCase()}`;
}
