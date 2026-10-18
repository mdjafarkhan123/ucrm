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
	import { fetchTaxPicker, taxPickerKey } from '$lib/settings/api';
	import {
		checkDiscount,
		checkTax,
		discountDraftFrom,
		taxDraftFrom,
		taxSourceOptions,
		type Checked,
		type DiscountPayload,
		type TaxPayload
	} from '$lib/work/pricing-adjustments';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import alertIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';

	// The discount and tax of a priced record, changed in place under its lines (Job details edit mode
	// `jFBRB`). It holds only drafts: every change goes up to the page, which saves them with the lines in one
	// press. A change hands up the payload, the messages that say what to fix, or null when the choice is back
	// to what was saved.
	//
	// Money stays the database's answer. The saved discount, tax and total show while nothing that moves them
	// has changed; once something has, they wait for the save to work them out.
	let {
		discount,
		tax,
		propertyId = null,
		canManageTaxes = false,
		discountMinor,
		taxMinor,
		totalMinor,
		linesChanged = false,
		showErrors = false,
		disabled = false,
		currencyCode = 'USD',
		locale = 'en-US',
		onDiscountChange,
		onTaxChange
	}: {
		discount: { name: string | null; type: QuoteDiscountType | null; value: number | null };
		tax: {
			source: QuoteTaxSource;
			rateId: string | null;
			name: string | null;
			rateBasisPoints: number;
		};
		/** Tax follows the property, so a record without one has no tax choice to make. */
		propertyId?: string | null;
		canManageTaxes?: boolean;
		discountMinor: number;
		taxMinor: number;
		totalMinor: number;
		/** The lines differ from the saved ones, so the saved figures no longer hold. */
		linesChanged?: boolean;
		/** A save was refused for these fields, so say what is wrong even in fields not yet left. */
		showErrors?: boolean;
		disabled?: boolean;
		currencyCode?: string;
		locale?: string;
		onDiscountChange: (result: Checked<DiscountPayload> | null) => void;
		onTaxChange: (result: Checked<TaxPayload> | null) => void;
	} = $props();

	const uid = $props.id();
	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);

	const savedDiscount = untrack(() => discount);
	const savedTax = untrack(() => tax);
	let discountOn = $state(savedDiscount.type !== null);
	let discountDraft = $state(
		discountDraftFrom(savedDiscount.name, savedDiscount.type, savedDiscount.value)
	);
	let discountChanged = $state(false);
	let discountLeft = $state(false);
	const discountChecked = $derived(discountOn ? checkDiscount(discountDraft) : null);

	let taxOn = $state(savedTax.source !== 'not_configured');
	let taxDraft = $state(
		taxDraftFrom(savedTax.source, savedTax.rateId, savedTax.name, savedTax.rateBasisPoints)
	);
	let taxChanged = $state(false);
	let taxLeft = $state(false);
	const taxChecked = $derived(taxOn ? checkTax(taxDraft, canManageTaxes) : null);

	const pickerQuery = createQuery(() => ({
		queryKey: taxPickerKey(propertyId ?? undefined),
		queryFn: () => fetchTaxPicker(propertyId ?? undefined),
		enabled: Boolean(propertyId) && taxOn,
		staleTime: 30_000
	}));
	const sourceOptions = $derived(taxSourceOptions(pickerQuery.data));

	// The saved figures hold only while nothing that feeds them has moved.
	const figuresHold = $derived(!linesChanged && !discountChanged && !taxChanged);
	const discountErrors = $derived(
		(showErrors || discountLeft) && discountChecked?.fieldErrors ? discountChecked.fieldErrors : {}
	);
	const taxErrors = $derived(
		(showErrors || taxLeft) && taxChecked?.fieldErrors ? taxChecked.fieldErrors : {}
	);

	function changeDiscount(next: Partial<typeof discountDraft>) {
		discountDraft = { ...discountDraft, ...next };
		discountChanged = true;
		onDiscountChange(checkDiscount(discountDraft));
	}

	function addDiscount() {
		discountOn = true;
		discountDraft = discountDraftFrom(null, null, null);
		discountChanged = true;
		discountLeft = false;
		onDiscountChange(checkDiscount(discountDraft));
	}

	function removeDiscount() {
		discountOn = false;
		discountChanged = savedDiscount.type !== null;
		onDiscountChange(discountChanged ? { payload: { name: null, type: null, value: null } } : null);
	}

	function changeTax(next: Partial<typeof taxDraft>) {
		taxDraft = { ...taxDraft, ...next };
		taxChanged = true;
		onTaxChange(checkTax(taxDraft, canManageTaxes));
	}

	function addTax() {
		taxOn = true;
		taxChanged = true;
		onTaxChange(checkTax(taxDraft, canManageTaxes));
	}

	function figure(minor: number, sign = '') {
		return figuresHold ? `${sign}${money.format(minor / 100)}` : '—';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="pricing-adjustments concept-fields">
	{#if discountOn}
		<section class="pricing-adjustments__box" aria-labelledby={`${uid}-discount`}>
			<div class="pricing-adjustments__head">
				<h3 class="pricing-adjustments__title" id={`${uid}-discount`}>Discount</h3>
				<span class="pricing-adjustments__figure">{figure(discountMinor, '−')}</span>
				<Button
					variant="quiet"
					variation="destructive"
					size="small"
					{disabled}
					onclick={removeDiscount}
				>
					Remove
				</Button>
			</div>
			<div class="pricing-adjustments__discount-fields">
				<Input
					id={`${uid}-discount-name`}
					label="What the client sees"
					{disabled}
					bind:value={
						() => discountDraft.name, (name) => changeDiscount({ name: String(name ?? '') })
					}
				/>
				<div class="pricing-adjustments__type">
					<span class="pricing-adjustments__label" id={`${uid}-discount-type`}>Type</span>
					<SegmentedControl
						ariaLabel="Discount type"
						tone="plain"
						value={discountDraft.type}
						options={[
							{ value: 'percentage', label: '%', title: 'Percentage off' },
							{ value: 'fixed', label: '$', title: 'Amount off' }
						]}
						{disabled}
						onchange={(type) => changeDiscount({ type: type as QuoteDiscountType })}
					/>
				</div>
				<div class="pricing-adjustments__amount" onfocusout={() => (discountLeft = true)}>
					{#if discountDraft.type === 'percentage'}
						<Input
							id={`${uid}-discount-percent`}
							label="Percentage off"
							inputmode="decimal"
							{disabled}
							invalid={Boolean(discountErrors.value)}
							bind:value={
								() => discountDraft.percent,
								(percent) => changeDiscount({ percent: String(percent ?? '') })
							}
						/>
					{:else}
						<MoneyInput
							id={`${uid}-discount-fixed`}
							label="Amount off"
							{disabled}
							invalid={Boolean(discountErrors.value)}
							bind:value={() => discountDraft.fixed, (fixed) => changeDiscount({ fixed })}
						/>
					{/if}
				</div>
			</div>
			{#if discountErrors.value}
				<p class="pricing-adjustments__error" role="alert">
					<span aria-hidden="true">{@html alertIcon}</span>{discountErrors.value}
				</p>
			{/if}
		</section>
	{/if}

	{#if propertyId && taxOn}
		<section class="pricing-adjustments__box" aria-labelledby={`${uid}-tax`}>
			<div class="pricing-adjustments__head">
				<h3 class="pricing-adjustments__title" id={`${uid}-tax`}>Tax</h3>
				<span class="pricing-adjustments__figure">{figure(taxMinor)}</span>
			</div>
			<Select
				id={`${uid}-tax-source`}
				label="Where the rate comes from"
				options={sourceOptions}
				{disabled}
				bind:value={() => taxDraft.value, (value) => changeTax({ value })}
			/>
			{#if taxDraft.value === 'custom'}
				<div class="pricing-adjustments__custom" onfocusout={() => (taxLeft = true)}>
					<Input
						id={`${uid}-tax-name`}
						label="What the client sees"
						{disabled}
						invalid={Boolean(taxErrors.custom_name)}
						errorMessage={taxErrors.custom_name ?? ''}
						bind:value={
							() => taxDraft.customName,
							(customName) => changeTax({ customName: String(customName ?? '') })
						}
					/>
					<Input
						id={`${uid}-tax-rate`}
						label="Rate %"
						inputmode="decimal"
						{disabled}
						invalid={Boolean(taxErrors.custom_rate_basis_points)}
						errorMessage={taxErrors.custom_rate_basis_points ?? ''}
						bind:value={
							() => taxDraft.customRate,
							(customRate) => changeTax({ customRate: String(customRate ?? '') })
						}
					/>
				</div>
				{#if canManageTaxes}
					<Checkbox
						id={`${uid}-tax-reusable`}
						label="Save as a reusable rate"
						description="Adds it to your saved tax rates for future work."
						{disabled}
						bind:checked={
							() => taxDraft.saveReusable, (saveReusable) => changeTax({ saveReusable })
						}
					/>
				{/if}
			{/if}
			<p class="pricing-adjustments__hint">Taxed lines only, after the discount</p>
		</section>
	{/if}

	{#if !discountOn || (propertyId && !taxOn)}
		<div class="pricing-adjustments__add">
			{#if !discountOn}
				<Button variant="secondary" size="small" {disabled} onclick={addDiscount}>
					<span aria-hidden="true">{@html plusIcon}</span>Add discount
				</Button>
			{/if}
			{#if propertyId && !taxOn}
				<Button variant="secondary" size="small" {disabled} onclick={addTax}>
					<span aria-hidden="true">{@html plusIcon}</span>Add tax
				</Button>
			{/if}
		</div>
	{/if}

	<div class="pricing-adjustments__total">
		<span class="pricing-adjustments__total-label">Total</span>
		{#if figuresHold}
			<span class="pricing-adjustments__total-value">{money.format(totalMinor / 100)}</span>
		{:else}
			<span class="pricing-adjustments__total-later">Worked out when you save</span>
		{/if}
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.pricing-adjustments {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);

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

		&__figure {
			color: var(--color-heading);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
		}

		&__discount-fields {
			display: grid;
			grid-template-columns: minmax(0, 1fr) auto 110px;
			align-items: start;
			gap: var(--space-small);
		}

		&__type {
			display: flex;
			flex-direction: column;
			gap: 6px;
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__custom {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 110px;
			align-items: start;
			gap: var(--space-small);
		}

		// The amount field is narrow, so what to fix runs under the whole row rather than inside its column.
		&__error {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
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
		}

		&__add :global(svg) {
			width: 16px;
			height: 16px;
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
			font-weight: 700;
		}

		&__total-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			font-variant-numeric: tabular-nums;
		}

		&__total-later {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
