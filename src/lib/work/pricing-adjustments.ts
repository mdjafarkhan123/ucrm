import type { QuoteDiscountType, QuoteTaxSource } from '$lib/quotes/api';
import type { TaxPicker } from '$lib/settings/api';

// The rules for a priced record's one discount and one tax choice, shared by the cards that change them in a
// dialog and the concept edit panel that changes them in place. Each turns what was typed into the payload
// the save command takes, or into the field messages that say what to fix — it never works out money, which
// stays the database's job.

export type DiscountPayload = {
	name: string | null;
	type: QuoteDiscountType | null;
	value: number | null;
};

export type DiscountDraft = {
	name: string;
	type: QuoteDiscountType;
	/** What was typed into "Percentage off", as text so a half-typed "7." survives. */
	percent: string;
	/** Whole cents. */
	fixed: number;
};

export type TaxPayload = {
	source: Exclude<QuoteTaxSource, 'not_configured'>;
	rate_id: string | null;
	custom_name: string | null;
	custom_rate_basis_points: number | null;
	save_as_reusable: boolean;
};

export type TaxDraft = {
	/** One Select value: a source, or `rate:<id>` for a saved rate. */
	value: string;
	customName: string;
	customRate: string;
	saveReusable: boolean;
};

export type Checked<T> =
	{ payload: T; fieldErrors?: never } | { payload?: never; fieldErrors: Record<string, string> };

/** "7.5" from 750 basis points; trailing zeros dropped. */
export function percentText(basisPoints: number) {
	return (basisPoints / 100).toFixed(2).replace(/\.?0+$/, '');
}

export function discountDraftFrom(
	name: string | null,
	type: QuoteDiscountType | null,
	value: number | null
): DiscountDraft {
	return {
		name: name ?? 'Discount',
		type: type ?? 'percentage',
		fixed: type === 'fixed' ? (value ?? 0) : 0,
		percent: type === 'percentage' ? ((value ?? 0) / 100).toString() : ''
	};
}

export function checkDiscount(draft: DiscountDraft): Checked<DiscountPayload> {
	const name = draft.name.trim() || null;
	if (draft.type === 'percentage') {
		const parsed = Number(draft.percent);
		if (!draft.percent.trim() || !Number.isFinite(parsed) || parsed <= 0 || parsed > 100)
			return { fieldErrors: { value: 'Enter a percentage between 0 and 100.' } };
		return { payload: { name, type: 'percentage', value: Math.round(parsed * 100) } };
	}
	if (draft.fixed <= 0) return { fieldErrors: { value: 'Enter an amount above zero.' } };
	return { payload: { name, type: 'fixed', value: draft.fixed } };
}

export function taxDraftFrom(
	taxSource: QuoteTaxSource,
	rateId: string | null,
	name: string | null,
	rateBasisPoints: number
): TaxDraft {
	return {
		value:
			taxSource === 'saved_rate' && rateId
				? `rate:${rateId}`
				: taxSource === 'not_configured'
					? 'business_default'
					: taxSource,
		customName: taxSource === 'custom' ? (name ?? '') : '',
		customRate: taxSource === 'custom' ? percentText(rateBasisPoints) : '',
		saveReusable: false
	};
}

function resolvedLabel(
	resolved: { name: string | null; rate_basis_points: number } | null | undefined
) {
	if (!resolved) return '…';
	if (resolved.rate_basis_points > 0)
		return `${resolved.name} ${percentText(resolved.rate_basis_points)}%`;
	return 'No tax';
}

/** Every tax choice as one list of Select options, each saying what rate it comes to. */
export function taxSourceOptions(picker: TaxPicker | undefined) {
	return [
		{
			value: 'business_default',
			label: `Business default — ${resolvedLabel(picker?.business_default)}`
		},
		{
			value: 'property_default',
			label: `Property default — ${resolvedLabel(picker?.property_default)}`
		},
		...(picker?.rates ?? []).map((rate) => ({
			value: `rate:${rate.id}`,
			label: `${rate.name} — ${percentText(rate.rate_basis_points)}%`
		})),
		{ value: 'custom', label: 'Custom rate…' },
		{ value: 'no_tax', label: 'No tax' }
	];
}

export function checkTax(draft: TaxDraft, canManageTaxes: boolean): Checked<TaxPayload> {
	if (draft.value.startsWith('rate:'))
		return {
			payload: {
				source: 'saved_rate',
				rate_id: draft.value.slice(5),
				custom_name: null,
				custom_rate_basis_points: null,
				save_as_reusable: false
			}
		};

	if (draft.value === 'custom') {
		const parsed = Number(draft.customRate);
		const name = draft.customName.trim();
		const fieldErrors: Record<string, string> = {};
		if (!name) fieldErrors.custom_name = 'Give this tax a name the customer will recognize.';
		if (!draft.customRate.trim() || !Number.isFinite(parsed) || parsed <= 0 || parsed > 100)
			fieldErrors.custom_rate_basis_points = 'Enter a rate between 0 and 100.';
		if (Object.keys(fieldErrors).length) return { fieldErrors };
		return {
			payload: {
				source: 'custom',
				rate_id: null,
				custom_name: name,
				custom_rate_basis_points: Math.round(parsed * 100),
				save_as_reusable: canManageTaxes && draft.saveReusable
			}
		};
	}

	return {
		payload: {
			source: draft.value as 'business_default' | 'property_default' | 'no_tax',
			rate_id: null,
			custom_name: null,
			custom_rate_basis_points: null,
			save_as_reusable: false
		}
	};
}
