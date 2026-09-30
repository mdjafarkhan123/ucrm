import { formatUsd } from '$lib/jafar/packages';

// Package builder P9: one public, published edition as visitors see it on /get-started and on its details
// page. Both read the same shape so the card, the details, and the application agree.

export type BillingInterval = 'month' | 'year';

export type PublicPackage = {
	edition_id: string;
	slug: string;
	name: string;
	promise: string | null;
	highlights: string[];
	included_services: { name: string; description: string }[];
	exclusions: string | null;
	monthly_price_usd_cents: number | null;
	yearly_price_usd_cents: number | null;
	capabilities: { key: string; label: string; description: string; core: boolean }[];
	allowances: {
		key: string;
		label: string;
		state: 'numeric' | 'unlimited';
		value: number | null;
		unit: string;
		resets_monthly: boolean;
	}[];
};

export function priceFor(pkg: PublicPackage, interval: BillingInterval) {
	return interval === 'month' ? pkg.monthly_price_usd_cents : pkg.yearly_price_usd_cents;
}

/** The interval a visitor gets for this package: the one they asked for when it is offered, otherwise the other. */
export function offeredInterval(pkg: PublicPackage, wanted: BillingInterval): BillingInterval {
	if (priceFor(pkg, wanted) !== null) return wanted;
	return wanted === 'month' ? 'year' : 'month';
}

export function offersBoth(pkg: PublicPackage) {
	return pkg.monthly_price_usd_cents !== null && pkg.yearly_price_usd_cents !== null;
}

/** "$129" and "a month" / "a year, paid upfront" — the exact amount the customer agrees to. */
export function priceParts(pkg: PublicPackage, interval: BillingInterval) {
	return {
		amount: formatUsd(priceFor(pkg, interval)),
		per: interval === 'month' ? 'a month' : 'a year, paid upfront'
	};
}

export function priceSentence(pkg: PublicPackage, interval: BillingInterval) {
	const { amount, per } = priceParts(pkg, interval);
	return `${amount} ${per}`;
}

/** Whole-percent saving of yearly over twelve monthly payments, rounded as the builder shows it; null when none. */
export function yearlySavingPercent(pkg: PublicPackage) {
	if (!offersBoth(pkg) || !pkg.monthly_price_usd_cents) return null;
	const saving = 1 - pkg.yearly_price_usd_cents! / (pkg.monthly_price_usd_cents * 12);
	const percent = Math.round(saving * 100);
	return percent >= 1 ? percent : null;
}

const UNIT_NAMES: Record<string, [string, string]> = {
	seats: ['team seat', 'team seats'],
	recipients: ['email', 'emails'],
	widgets: ['chat widget', 'chat widgets'],
	conversations: ['website chat', 'website chats'],
	recipes: ['active automation', 'active automations']
};

/** "Up to 5 team seats", "1,000 operational emails a month", "Unlimited marketing email". */
export function allowanceSentence(allowance: PublicPackage['allowances'][number]) {
	const perMonth = allowance.resets_monthly ? ' a month' : '';
	if (allowance.state === 'unlimited') return `Unlimited ${allowance.label.toLowerCase()}`;
	const count = allowance.value ?? 0;
	const [one, many] = UNIT_NAMES[allowance.unit] ?? [allowance.unit, allowance.unit];
	const formatted = count.toLocaleString('en-US');
	if (allowance.unit === 'recipients') {
		const kind = allowance.label.toLowerCase().replace(/\s*email$/, '');
		return `${formatted} ${kind} ${count === 1 ? one : many}${perMonth}`;
	}
	if (allowance.unit === 'seats') return `Up to ${formatted} ${count === 1 ? one : many}`;
	return `${formatted} ${count === 1 ? one : many}${perMonth}`;
}
