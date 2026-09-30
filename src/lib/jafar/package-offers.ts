import { formatUsd, PackageApiError, type ApiError } from '$lib/jafar/packages';
import { offerDiscount, offerLength } from '$lib/packages/public-package';

// Package builder P11b: what Jafar's offer builder reads and sends. The rules are in the database
// (save_package_offer, P11a); the API is src/routes/api/jafar/package-offers.

export type OfferStatus = 'open' | 'scheduled' | 'ended' | 'full' | 'archived';

export type PackageOffer = {
	id: string;
	name: string;
	apply_mode: 'automatic' | 'code';
	code: string | null;
	discount_kind: 'percent' | 'fixed';
	percent_off: number | null;
	amount_off_usd_cents: number | null;
	applies_to_monthly: boolean;
	applies_to_yearly: boolean;
	monthly_periods: number | null;
	customer_eligibility: 'new' | 'existing' | 'any';
	claim_starts_at: string;
	claim_ends_at: string | null;
	redemption_cap: number | null;
	archived_at: string | null;
	revision: number;
	created_at: string;
	updated_at: string;
	status: OfferStatus;
	/** Once anyone has claimed it, its discount, billing, and length are fixed. */
	terms_locked: boolean;
	claim_count: number;
	package_ids: string[];
	claims: {
		id: string;
		organization_id: string;
		organization_name: string;
		method: 'automatic' | 'code';
		honored: boolean;
		claimed_at: string;
		released_at: string | null;
		actor_owner_email: string;
	}[];
};

/** The whole offer as the form edits it and the save command receives it. */
export type OfferForm = {
	name: string;
	apply_mode: 'automatic' | 'code';
	code: string | null;
	discount_kind: 'percent' | 'fixed';
	percent_off: number | null;
	amount_off_usd_cents: number | null;
	applies_to_monthly: boolean;
	applies_to_yearly: boolean;
	monthly_periods: number | null;
	customer_eligibility: 'new' | 'existing' | 'any';
	claim_starts_at: string;
	claim_ends_at: string | null;
	redemption_cap: number | null;
	package_ids: string[];
};

async function send<T>(url: string, method: string, body?: unknown): Promise<T> {
	const response = await fetch(url, {
		method,
		headers: body === undefined ? undefined : { 'content-type': 'application/json' },
		body: body === undefined ? undefined : JSON.stringify(body)
	});
	const result = (await response.json().catch(() => ({}))) as T & ApiError;
	if (!response.ok) {
		throw new PackageApiError(
			result.error ?? 'Something went wrong. Try again.',
			response.status,
			result
		);
	}
	return result;
}

export async function fetchPackageOffers() {
	return (await send<{ offers: PackageOffer[] }>('/api/jafar/package-offers', 'GET')).offers;
}

export function createPackageOffer(input: { idempotency_key: string; terms: OfferForm }) {
	return send<{ result: { offer_id: string } }>('/api/jafar/package-offers', 'POST', input);
}

export function savePackageOffer(offerId: string, expectedRevision: number, terms: OfferForm) {
	return send<{ result: { offer_id: string; revision: number } }>(
		`/api/jafar/package-offers/${offerId}`,
		'PATCH',
		{ action: 'save', expected_revision: expectedRevision, terms }
	);
}

export function setPackageOfferArchived(offerId: string, archived: boolean) {
	return send<{ result: { offer_id: string } }>(`/api/jafar/package-offers/${offerId}`, 'PATCH', {
		action: archived ? 'archive' : 'restore'
	});
}

export function formFromOffer(offer: PackageOffer): OfferForm {
	return {
		name: offer.name,
		apply_mode: offer.apply_mode,
		code: offer.code,
		discount_kind: offer.discount_kind,
		percent_off: offer.percent_off,
		amount_off_usd_cents: offer.amount_off_usd_cents,
		applies_to_monthly: offer.applies_to_monthly,
		applies_to_yearly: offer.applies_to_yearly,
		monthly_periods: offer.monthly_periods,
		customer_eligibility: offer.customer_eligibility,
		claim_starts_at: offer.claim_starts_at,
		claim_ends_at: offer.claim_ends_at,
		redemption_cap: offer.redemption_cap,
		package_ids: [...offer.package_ids]
	};
}

/** "50% off for 3 months on monthly · first year on yearly". */
export function describeOfferTerms(
	offer: Pick<
		OfferForm,
		| 'discount_kind'
		| 'percent_off'
		| 'amount_off_usd_cents'
		| 'applies_to_monthly'
		| 'applies_to_yearly'
		| 'monthly_periods'
	>
) {
	const lengths = [
		offer.applies_to_monthly && offer.monthly_periods
			? `${offerLength('month', offer.monthly_periods)} on monthly`
			: null,
		offer.applies_to_yearly ? `${offerLength('year', 1)} on yearly` : null
	].filter(Boolean);
	return `${offerDiscount(offer)} ${lengths.join(' · ')}`;
}

/** The price during the offer: $149 at 50% off is $74.50. Mirrors package_offer_intro_price. */
export function introPrice(
	offer: Pick<OfferForm, 'discount_kind' | 'percent_off' | 'amount_off_usd_cents'>,
	normalPrice: number
) {
	if (offer.discount_kind === 'percent')
		return normalPrice - Math.round((normalPrice * (offer.percent_off ?? 0)) / 100);
	return Math.max(normalPrice - (offer.amount_off_usd_cents ?? 0), 0);
}

export const offerStatusLabels: Record<OfferStatus, string> = {
	open: 'Open',
	scheduled: 'Not open yet',
	ended: 'Claims closed',
	full: 'All places claimed',
	archived: 'Archived'
};

export const eligibilityLabels: Record<OfferForm['customer_eligibility'], string> = {
	new: 'New customers',
	existing: 'Existing customers',
	any: 'New and existing customers'
};
