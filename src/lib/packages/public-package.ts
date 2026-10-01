import { formatUsd } from '$lib/jafar/packages';

// Package builder P9: one public, published edition as visitors see it on /get-started and on its details
// page. Both read the same shape so the card, the details, and the application agree.

export type BillingInterval = 'month' | 'year';

/**
 * Package builder P11b: an introductory offer as the database shows it to a visitor or to Jafar — the
 * discount, how many periods it covers, and the price during and after it (`package_offer_shown`).
 */
export type ShownOffer = {
	id: string;
	name: string;
	discount_kind: 'percent' | 'fixed';
	percent_off: number | null;
	amount_off_usd_cents: number | null;
	monthly_periods: number | null;
	billing_interval: BillingInterval;
	periods: number;
	normal_price_usd_cents: number;
	intro_price_usd_cents: number;
	claim_ends_at: string | null;
};

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
	/** The automatic offer a new customer gets today on each billing, if any. */
	offers: Record<BillingInterval, ShownOffer | null>;
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

/**
 * What paying yearly saves against twelve monthly payments, in dollars, whole percent, and the monthly
 * equivalent of the yearly price. Null when the package is not offered both ways or yearly is no cheaper,
 * so a discount is never invented.
 */
export function yearlySaving(pkg: PublicPackage) {
	if (!offersBoth(pkg) || !pkg.monthly_price_usd_cents) return null;
	const twelveMonthsCents = pkg.monthly_price_usd_cents * 12;
	const savedCents = twelveMonthsCents - pkg.yearly_price_usd_cents!;
	const percent = Math.round((savedCents / twelveMonthsCents) * 100);
	if (savedCents <= 0 || percent < 1) return null;
	return {
		twelveMonthsCents,
		savedCents,
		percent,
		perMonthCents: Math.round(pkg.yearly_price_usd_cents! / 12)
	};
}

/** Whole-percent saving of yearly over twelve monthly payments, rounded as the builder shows it; null when none. */
export function yearlySavingPercent(pkg: PublicPackage) {
	return yearlySaving(pkg)?.percent ?? null;
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

/** "50% off" or "$20 off". */
export function offerDiscount(
	offer: Pick<ShownOffer, 'discount_kind' | 'percent_off' | 'amount_off_usd_cents'>
) {
	return offer.discount_kind === 'percent'
		? `${offer.percent_off}% off`
		: `${formatUsd(offer.amount_off_usd_cents)} off`;
}

/** "for 3 months", "for the first month", "for the first year". */
export function offerLength(interval: BillingInterval, periods: number) {
	if (interval === 'year') return 'for the first year';
	return periods === 1 ? 'for the first month' : `for ${periods} months`;
}

/** "50% off for 3 months". */
export function offerHeadline(offer: ShownOffer) {
	return `${offerDiscount(offer)} ${offerLength(offer.billing_interval, offer.periods)}`;
}

/** "$74.50 a month for 3 months, then $149 a month" — the exact intro and later price. */
export function offerPriceSentence(offer: ShownOffer) {
	const per = offer.billing_interval === 'month' ? 'a month' : 'a year';
	return `${formatUsd(offer.intro_price_usd_cents)} ${per} ${offerLength(offer.billing_interval, offer.periods)}, then ${formatUsd(offer.normal_price_usd_cents)} ${per}`;
}
