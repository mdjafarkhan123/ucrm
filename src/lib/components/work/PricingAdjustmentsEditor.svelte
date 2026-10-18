<script module lang="ts">
	import type {
		QuoteDiscountType as DiscountType,
		QuoteTaxSource as TaxSource
	} from '$lib/quotes/api';

	export type DiscountPayload = {
		name: string | null;
		type: DiscountType | null;
		value: number | null;
	};
	export type TaxPayload = {
		source: Exclude<TaxSource, 'not_configured'>;
		rate_id: string | null;
		custom_name: string | null;
		custom_rate_basis_points: number | null;
		save_as_reusable: boolean;
	};
</script>

<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import type { QuoteDiscountType, QuoteTaxSource } from '$lib/quotes/api';
	import { fetchTaxPicker, taxPickerKey, type TaxPickerResolved } from '$lib/settings/api';
	import { previewMoney, type PreviewLine } from '$lib/work/money-preview';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// The discount, tax and total of a priced record while its products editor is open (concept Job details,
	// edit frame `jFBRB`). Everything here is staged: nothing is written until the editor's one Save, which
	// sends lines, discount and tax together. The figures are a live preview worked out the way the database
	// will work them out; the saved card shows the database's own figures again after Save.
	//
	// The same choices as the Discount and Tax dialogs (`RecordDiscountCard`, `RecordTaxCard`), laid open:
	// a name and a percentage or an amount for the discount, and the five ways a tax rate can be set.
	let {
		lines,
		discount,
		tax,
		propertyId = null,
		canManageTaxes = false,
		currencyCode = 'USD',
		locale = 'en-US',
		disabled = false,
		onChange
	}: {
		/** The editor's lines as they stand, priced lines only. */
		lines: PreviewLine[];
		/** The saved discount; `type` null means none. */
		discount: { name: string | null; type: QuoteDiscountType | null; value: number | null };
		/** The saved tax choice and what it froze. */
		tax: {
			source: QuoteTaxSource;
			rateId: string | null;
			name: string | null;
			rateBasisPoints: number;
		};
		/** Tax is chosen per property. Without one there is nothing to inherit, so no tax section shows. */
		propertyId?: string | null;
		/** Only an owner or admin may save a custom rate to the shared list. */
		canManageTaxes?: boolean;
		currencyCode?: string;
		locale?: string;
		disabled?: boolean;
		/** What Save should send. `undefined` means unchanged; `problem` blocks Save with that message. */
		onChange: (staged: {
			discount: DiscountPayload | undefined;
			tax: TaxPayload | undefined;
			problem: string | null;
		}) => void;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const format = (minor: number) => money.format(minor / 100);
	const rateText = (basisPoints: number) =>
		`${(basisPoints / 100).toFixed(2).replace(/\.?0+$/, '')}%`;

	// The editor opens on what is saved; from then on these fields are the person's.
	const saved = untrack(() => ({ discount, tax }));

	let discountOpen = $state(saved.discount.type !== null);
	let discountName = $state(saved.discount.name ?? 'Discount');
	let discountType = $state<QuoteDiscountType>(saved.discount.type ?? 'percentage');
	let discountPercent = $state(
		saved.discount.type === 'percentage' ? ((saved.discount.value ?? 0) / 100).toString() : ''
	);
	let discountFixed = $state(saved.discount.type === 'fixed' ? (saved.discount.value ?? 0) : 0);

	let taxOpen = $state(saved.tax.source !== 'not_configured');
	let taxValue = $state(
		saved.tax.source === 'saved_rate' && saved.tax.rateId
			? `rate:${saved.tax.rateId}`
			: saved.tax.source === 'not_configured'
				? 'business_default'
				: saved.tax.source
	);
	let customName = $state(saved.tax.source === 'custom' ? (saved.tax.name ?? '') : '');
	let customRate = $state(
		saved.tax.source === 'custom' ? (saved.tax.rateBasisPoints / 100).toString() : ''
	);
	let saveReusable = $state(false);

	const pickerQuery = createQuery(() => ({
		queryKey: taxPickerKey(propertyId ?? undefined),
		queryFn: () => fetchTaxPicker(propertyId ?? undefined),
		enabled: Boolean(propertyId),
		staleTime: 30_000
	}));
	const picker = $derived(pickerQuery.data);

	function resolvedLabel(resolved: TaxPickerResolved | null | undefined) {
		if (!resolved) return '…';
		return resolved.rate_basis_points > 0
			? `${resolved.name} ${rateText(resolved.rate_basis_points)}`
			: 'No tax';
	}

	const taxOptions = $derived([
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
			label: `${rate.name} — ${rateText(rate.rate_basis_points)}`
		})),
		// A rate the job froze that is no longer on the shared list still has to be choosable as itself.
		...(saved.tax.source === 'saved_rate' &&
		saved.tax.rateId &&
		picker &&
		!picker.rates.some((rate) => rate.id === saved.tax.rateId)
			? [
					{
						value: `rate:${saved.tax.rateId}`,
						label: `${saved.tax.name ?? 'Saved rate'} — ${rateText(saved.tax.rateBasisPoints)}`
					}
				]
			: []),
		{ value: 'custom', label: 'Custom rate…' },
		{ value: 'no_tax', label: 'No tax' }
	]);

	// --- What the fields add up to --------------------------------------------------------------------------

	const parsedPercent = $derived(Number(discountPercent));
	const discountProblem = $derived.by(() => {
		if (!discountOpen) return null;
		if (discountType === 'percentage')
			return Number.isFinite(parsedPercent) && parsedPercent > 0 && parsedPercent <= 100
				? null
				: 'Enter a discount percentage between 0 and 100.';
		return discountFixed > 0 ? null : 'Enter a discount amount above zero.';
	});
	const discountValue = $derived(
		discountType === 'percentage' ? Math.round(parsedPercent * 100) : discountFixed
	);

	const parsedCustomRate = $derived(Number(customRate));
	const taxProblem = $derived.by(() => {
		if (!taxOpen || taxValue !== 'custom') return null;
		if (!customName.trim()) return 'Give the custom tax a name the customer will recognize.';
		if (!Number.isFinite(parsedCustomRate) || parsedCustomRate <= 0 || parsedCustomRate > 100)
			return 'Enter a tax rate between 0 and 100.';
		return null;
	});

	// The rate the preview taxes at. Until the picker answers, a choice the job already froze keeps its rate.
	const previewRate = $derived.by(() => {
		if (!taxOpen) return 0;
		const unchangedSource =
			taxValue === saved.tax.source ||
			(taxValue.startsWith('rate:') && taxValue.slice(5) === saved.tax.rateId);
		const fallback = unchangedSource ? saved.tax.rateBasisPoints : 0;
		if (taxValue === 'no_tax') return 0;
		if (taxValue === 'custom') return taxProblem ? 0 : Math.round(parsedCustomRate * 100);
		if (taxValue === 'business_default')
			return picker?.business_default.rate_basis_points ?? fallback;
		if (taxValue === 'property_default')
			return picker?.property_default?.rate_basis_points ?? fallback;
		return (
			picker?.rates.find((rate) => rate.id === taxValue.slice(5))?.rate_basis_points ?? fallback
		);
	});

	const preview = $derived(
		previewMoney(
			lines,
			discountOpen && !discountProblem ? { type: discountType, value: discountValue } : null,
			previewRate
		)
	);

	const discountPayload = $derived.by((): DiscountPayload | undefined => {
		if (!discountOpen)
			return saved.discount.type === null ? undefined : { name: null, type: null, value: null };
		if (discountProblem) return undefined;
		const next = { name: discountName.trim() || null, type: discountType, value: discountValue };
		const same =
			next.type === saved.discount.type &&
			next.value === saved.discount.value &&
			next.name === (saved.discount.name ?? null);
		return same ? undefined : next;
	});

	const taxPayload = $derived.by((): TaxPayload | undefined => {
		if (!taxOpen || taxProblem) return undefined;
		const base = {
			rate_id: null,
			custom_name: null,
			custom_rate_basis_points: null,
			save_as_reusable: false
		};
		let next: TaxPayload;
		if (taxValue.startsWith('rate:'))
			next = { ...base, source: 'saved_rate', rate_id: taxValue.slice(5) };
		else if (taxValue === 'custom')
			next = {
				...base,
				source: 'custom',
				custom_name: customName.trim(),
				custom_rate_basis_points: Math.round(parsedCustomRate * 100),
				save_as_reusable: canManageTaxes && saveReusable
			};
		else next = { ...base, source: taxValue as 'business_default' | 'property_default' | 'no_tax' };
		const same =
			next.source === saved.tax.source &&
			(next.source !== 'saved_rate' || next.rate_id === saved.tax.rateId) &&
			(next.source !== 'custom' ||
				(next.custom_name === saved.tax.name &&
					next.custom_rate_basis_points === saved.tax.rateBasisPoints &&
					!next.save_as_reusable));
		return same ? undefined : next;
	});

	$effect(() => {
		const staged = {
			discount: discountPayload,
			tax: taxPayload,
			problem: discountProblem ?? taxProblem
		};
		untrack(() => onChange(staged));
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="pricing-adjustments">
	<div class="pricing-adjustments__row">
		<span class="pricing-adjustments__label">Subtotal</span>
		<span class="pricing-adjustments__value">{format(preview.subtotal_minor)}</span>
	</div>

	{#if discountOpen}
		<section class="pricing-adjustments__box" aria-labelledby="pricing-adjustments-discount">
			<div class="pricing-adjustments__head">
				<h3 class="pricing-adjustments__title" id="pricing-adjustments-discount">Discount</h3>
				<span class="pricing-adjustments__amount">−{format(preview.discount_minor)}</span>
				<Button
					variant="quiet"
					variation="destructive"
					size="small"
					{disabled}
					onclick={() => (discountOpen = false)}>Remove</Button
				>
			</div>
			<div class="pricing-adjustments__fields">
				<div class="pricing-adjustments__field pricing-adjustments__field--grow">
					<label class="pricing-adjustments__field-label" for="pricing-adjustments-discount-name"
						>What the client sees</label
					>
					<Input id="pricing-adjustments-discount-name" {disabled} bind:value={discountName} />
				</div>
				<div class="pricing-adjustments__field">
					<span class="pricing-adjustments__field-label" id="pricing-adjustments-discount-type"
						>Type</span
					>
					<SegmentedControl
						ariaLabel="Discount type"
						value={discountType}
						options={[
							{ value: 'percentage', label: '%', title: 'Percentage' },
							{ value: 'fixed', label: '$', title: 'Amount' }
						]}
						{disabled}
						onchange={(next) => (discountType = next as QuoteDiscountType)}
					/>
				</div>
				<div class="pricing-adjustments__field pricing-adjustments__field--number">
					{#if discountType === 'percentage'}
						<label class="pricing-adjustments__field-label" for="pricing-adjustments-discount-value"
							>Percentage off</label
						>
						<Input
							id="pricing-adjustments-discount-value"
							inputmode="decimal"
							{disabled}
							invalid={Boolean(discountProblem) && discountPercent !== ''}
							bind:value={discountPercent}
						/>
					{:else}
						<label class="pricing-adjustments__field-label" for="pricing-adjustments-discount-value"
							>Amount off</label
						>
						<MoneyInput
							id="pricing-adjustments-discount-value"
							{disabled}
							bind:value={discountFixed}
						/>
					{/if}
				</div>
			</div>
		</section>
	{/if}

	{#if propertyId && taxOpen}
		<section class="pricing-adjustments__box" aria-labelledby="pricing-adjustments-tax">
			<div class="pricing-adjustments__head">
				<h3 class="pricing-adjustments__title" id="pricing-adjustments-tax">Tax</h3>
				<span class="pricing-adjustments__amount">{format(preview.tax_minor)}</span>
				{#if saved.tax.source === 'not_configured'}
					<!-- Only a tax added in this edit can be taken back off; a saved one is changed to "No tax". -->
					<Button
						variant="quiet"
						variation="destructive"
						size="small"
						{disabled}
						onclick={() => (taxOpen = false)}>Remove</Button
					>
				{/if}
			</div>
			<div class="pricing-adjustments__field">
				<label class="pricing-adjustments__field-label" for="pricing-adjustments-tax-source"
					>Where the rate comes from</label
				>
				<Select
					id="pricing-adjustments-tax-source"
					bind:value={taxValue}
					options={taxOptions}
					{disabled}
				/>
			</div>
			{#if taxValue === 'custom'}
				<div class="pricing-adjustments__fields">
					<div class="pricing-adjustments__field pricing-adjustments__field--grow">
						<label class="pricing-adjustments__field-label" for="pricing-adjustments-tax-name"
							>What the client sees</label
						>
						<Input id="pricing-adjustments-tax-name" {disabled} bind:value={customName} />
					</div>
					<div class="pricing-adjustments__field pricing-adjustments__field--number">
						<label class="pricing-adjustments__field-label" for="pricing-adjustments-tax-rate"
							>Rate %</label
						>
						<Input
							id="pricing-adjustments-tax-rate"
							inputmode="decimal"
							{disabled}
							bind:value={customRate}
						/>
					</div>
				</div>
				{#if canManageTaxes}
					<Checkbox
						id="pricing-adjustments-tax-reusable"
						label="Save as a reusable rate"
						bind:checked={saveReusable}
						{disabled}
					/>
				{/if}
			{/if}
			<p class="pricing-adjustments__hint">Taxed lines only, after the discount</p>
		</section>
	{/if}

	{#if !discountOpen || (propertyId && !taxOpen)}
		<div class="pricing-adjustments__add">
			{#if !discountOpen}
				<Button variant="secondary" size="small" {disabled} onclick={() => (discountOpen = true)}>
					<span class="pricing-adjustments__icon" aria-hidden="true">{@html plusIcon}</span>
					Add discount
				</Button>
			{/if}
			{#if propertyId && !taxOpen}
				<Button variant="secondary" size="small" {disabled} onclick={() => (taxOpen = true)}>
					<span class="pricing-adjustments__icon" aria-hidden="true">{@html plusIcon}</span>
					Add tax
				</Button>
			{/if}
		</div>
	{/if}

	{#if discountOpen || taxOpen}
		<div class="pricing-adjustments__total">
			<span class="pricing-adjustments__total-label">Total</span>
			<span class="pricing-adjustments__total-value">{format(preview.total_minor)}</span>
		</div>
	{/if}
</div>

<style lang="scss">
	// Concept edit frame `jFBRB`: a soft grey panel, Subtotal on top, then each adjustment in a white box of
	// its own and the Total last in a white box.
	.pricing-adjustments {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		width: min(480px, 100%);
		padding: var(--space-base) var(--space-base) var(--space-small);
		border-radius: var(--radius-large);
		background: var(--color-surface--background--subtle);

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			font-size: var(--typography--fontSize-base);
		}
		&__label {
			flex: 1 1 auto;
			color: var(--color-text--secondary);
		}
		&__value {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__box {
			display: flex;
			flex-direction: column;
			gap: 10px;
			padding: var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}
		&__head {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 28px;
		}
		&__title {
			flex: 1 1 auto;
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__amount {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__fields {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);
		}
		&__field {
			display: flex;
			min-width: 0;
			flex-direction: column;
			gap: 6px;

			&--grow {
				flex: 1 1 auto;
			}
			&--number {
				flex: 0 0 96px;
			}
		}
		&__field-label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}
		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__add {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			padding-bottom: var(--space-small);
		}
		&__icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__total {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: 10px var(--space-slim);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}
		&__total-label {
			flex: 1 1 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
		&__total-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
		}

		// Concept fields (`inputs.md`): a 40px box with its label above it rather than floating inside.
		:global(.input__control) {
			min-height: 40px;
		}
		:global(.input input) {
			padding: 0 var(--space-slim);
			line-height: 38px;
		}
		:global(.select__trigger) {
			min-height: 40px;
			font-size: var(--typography--fontSize-base);
		}
		// The % / $ switch stands as tall as the fields beside it: 32px options in a 3px-padded track.
		:global(.segmented__track) {
			padding: 3px;
		}
		:global(.segmented__option) {
			min-width: 36px;
			min-height: 32px;
		}
	}
</style>
