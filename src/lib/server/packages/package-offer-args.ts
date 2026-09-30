import type { PackageOfferTerms } from '$lib/server/validation/package-builder.schema';

// The save_package_offer arguments for a validated form. Only the fields its discount and billing use are
// sent; the others go as null so an unused percentage or month count is never stored.
export function savePackageOfferArgs(
	terms: PackageOfferTerms,
	context: {
		offerId: string | null;
		expectedRevision: number;
		actorEmail: string;
		idempotencyKey: string;
	}
) {
	return {
		offer_id: context.offerId as string,
		expected_revision: context.expectedRevision,
		name: terms.name,
		apply_mode: terms.apply_mode,
		code: (terms.apply_mode === 'code' ? terms.code : null) as string,
		discount_kind: terms.discount_kind,
		percent_off: (terms.discount_kind === 'percent' ? terms.percent_off : null) as number,
		amount_off_usd_cents: (terms.discount_kind === 'fixed'
			? terms.amount_off_usd_cents
			: null) as number,
		applies_to_monthly: terms.applies_to_monthly,
		applies_to_yearly: terms.applies_to_yearly,
		monthly_periods: (terms.applies_to_monthly ? terms.monthly_periods : null) as number,
		customer_eligibility: terms.customer_eligibility,
		claim_starts_at: terms.claim_starts_at,
		claim_ends_at: terms.claim_ends_at as string,
		redemption_cap: terms.redemption_cap as number,
		package_ids: terms.package_ids,
		actor_owner_email: context.actorEmail,
		idempotency_key: context.idempotencyKey
	};
}
