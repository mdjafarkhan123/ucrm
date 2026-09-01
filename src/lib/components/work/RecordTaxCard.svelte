<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import type { QuoteTaxSource, QuoteWriteError } from '$lib/quotes/api';
	import { fetchTaxPicker, taxPickerKey } from '$lib/settings/api';
	import taxIcon from '@tabler/icons/outline/receipt-tax.svg?raw';

	// Five ways a priced record's tax can be set: follow the Business default, follow this property's own
	// pin, freeze one saved rate, freeze a one-off custom rate, or say explicitly there is no tax. Whichever
	// one is chosen, the database resolves and freezes the real name/percentage at save time — this card only
	// ever shows what the last save actually froze.
	//
	// A quote and a job are taxed from the same five options, so this card belongs to neither: the page hands
	// it the one function that writes, and the card knows nothing about which record it is pricing.
	let {
		revision,
		propertyId,
		taxSource,
		rateId,
		name,
		rateBasisPoints,
		taxMinor = null,
		currencyCode = 'USD',
		locale = 'en-US',
		editable = false,
		canSeePrice = true,
		canManageTaxes = false,
		recordNoun = 'quote',
		unsetHint = 'Required before sending this quote.',
		onSave,
		onSaved
	}: {
		revision: number;
		propertyId: string;
		taxSource: QuoteTaxSource;
		rateId: string | null;
		name: string | null;
		/** 8.25% is 825. Zero is No tax. */
		rateBasisPoints: number;
		taxMinor?: number | null;
		currencyCode?: string;
		locale?: string;
		editable?: boolean;
		canSeePrice?: boolean;
		/** Only an owner/admin may save a custom rate to the shared list — the database enforces this too. */
		canManageTaxes?: boolean;
		/** What the record is called in the sentence a stale save produces. */
		recordNoun?: string;
		/** Why an unset tax matters here. A quote cannot be sent without one; a job simply is not taxed yet. */
		unsetHint?: string;
		/** Writes the tax choice against the revision it is handed. */
		onSave: (revision: number, payload: TaxPayload) => Promise<unknown>;
		onSaved: (result: unknown) => Promise<void> | void;
	} = $props();

	type TaxPayload = {
		source: Exclude<QuoteTaxSource, 'not_configured'>;
		rate_id: string | null;
		custom_name: string | null;
		custom_rate_basis_points: number | null;
		save_as_reusable: boolean;
	};

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const configured = $derived(taxSource !== 'not_configured');
	const rateText = $derived(`${(rateBasisPoints / 100).toFixed(2).replace(/\.?0+$/, '')}%`);

	const SOURCE_LABEL: Record<QuoteTaxSource, string> = {
		not_configured: 'Not configured',
		business_default: 'Business default',
		property_default: 'Property default',
		saved_rate: 'Saved rate',
		no_tax: 'No tax',
		custom: 'Custom'
	};

	const queryClient = useQueryClient();
	let open = $state(false);

	function warm() {
		void queryClient.prefetchQuery({
			queryKey: taxPickerKey(propertyId),
			queryFn: () => fetchTaxPicker(propertyId)
		});
	}

	const pickerQuery = createQuery(() => ({
		queryKey: taxPickerKey(propertyId),
		queryFn: () => fetchTaxPicker(propertyId),
		enabled: open,
		staleTime: 30_000,
		gcTime: 60_000
	}));
	const picker = $derived(pickerQuery.data);

	function previewLabel(
		resolved: { name: string | null; rate_basis_points: number } | null | undefined
	) {
		if (!resolved) return '…';
		if (resolved.rate_basis_points > 0)
			return `${resolved.name} — ${(resolved.rate_basis_points / 100).toFixed(2).replace(/\.?0+$/, '')}%`;
		return 'No tax';
	}

	// Encodes the schema's `source` (plus, for a saved rate, which one) as one Select value.
	const sourceOptions = $derived([
		{
			value: 'business_default',
			label: `Business default — ${previewLabel(picker?.business_default)}`
		},
		{
			value: 'property_default',
			label: `Property default — ${previewLabel(picker?.property_default)}`
		},
		...(picker?.rates ?? []).map((rate) => ({
			value: `rate:${rate.id}`,
			label: `${rate.name} — ${(rate.rate_basis_points / 100).toFixed(2).replace(/\.?0+$/, '')}%`
		})),
		{ value: 'custom', label: 'Custom rate…' },
		{ value: 'no_tax', label: 'No tax' }
	]);

	let draftValue = $state('business_default');
	let draftCustomName = $state('');
	let draftCustomRate = $state('');
	let draftSaveReusable = $state(false);
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function openDialog() {
		draftValue =
			taxSource === 'saved_rate' && rateId
				? `rate:${rateId}`
				: taxSource === 'not_configured'
					? 'business_default'
					: taxSource;
		draftCustomName = taxSource === 'custom' ? (name ?? '') : '';
		draftCustomRate = taxSource === 'custom' ? (rateBasisPoints / 100).toString() : '';
		draftSaveReusable = false;
		error = '';
		fieldErrors = {};
		open = true;
	}

	function close() {
		if (saving) return;
		open = false;
	}

	async function write(payload: TaxPayload) {
		if (saving) return;
		saving = true;
		error = '';
		fieldErrors = {};
		try {
			const result = await onSave(
				untrack(() => revision),
				payload
			);
			open = false;
			await onSaved(result);
		} catch (cause) {
			const failure = cause as QuoteWriteError;
			fieldErrors = failure.fieldErrors ?? {};
			error = Object.keys(fieldErrors).length
				? ''
				: failure.reason === 'stale'
					? `Someone else changed this ${recordNoun}. Close this, check the latest figures, and try again.`
					: failure.message;
		} finally {
			saving = false;
		}
	}

	function save() {
		if (draftValue.startsWith('rate:')) {
			void write({
				source: 'saved_rate',
				rate_id: draftValue.slice(5),
				custom_name: null,
				custom_rate_basis_points: null,
				save_as_reusable: false
			});
			return;
		}

		if (draftValue === 'custom') {
			const parsed = Number(draftCustomRate);
			const cleanName = draftCustomName.trim();
			const nextFieldErrors: Record<string, string> = {};
			if (!cleanName)
				nextFieldErrors.custom_name = 'Give this tax a name the customer will recognize.';
			if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 100)
				nextFieldErrors.custom_rate_basis_points = 'Enter a rate between 0 and 100.';
			if (Object.keys(nextFieldErrors).length) {
				fieldErrors = nextFieldErrors;
				return;
			}
			void write({
				source: 'custom',
				rate_id: null,
				custom_name: cleanName,
				custom_rate_basis_points: Math.round(parsed * 100),
				save_as_reusable: canManageTaxes && draftSaveReusable
			});
			return;
		}

		void write({
			source: draftValue as 'business_default' | 'property_default' | 'no_tax',
			rate_id: null,
			custom_name: null,
			custom_rate_basis_points: null,
			save_as_reusable: false
		});
	}
</script>

<RailCard title="Tax" icon={taxIcon}>
	{#snippet actions()}
		{#if editable && canSeePrice && configured}
			<Button variant="tertiary" size="small" onclick={openDialog} onhover={warm}>Edit</Button>
		{/if}
	{/snippet}

	{#if !canSeePrice}
		<p class="record-tax__muted">You do not have access to these prices.</p>
	{:else if taxSource === 'not_configured'}
		<div class="record-tax__unset">
			<Badge status="warning" dot={false}>Not configured</Badge>
			{#if editable}
				<p class="record-tax__hint">{unsetHint}</p>
			{/if}
		</div>
		{#if editable}
			<Button variant="secondary" variation="subtle" fullWidth onclick={openDialog} onhover={warm}>
				Set tax
			</Button>
		{/if}
	{:else if taxSource === 'no_tax'}
		<p class="record-tax__name">No tax</p>
	{:else}
		<div class="record-tax__set">
			<p class="record-tax__name">{name || 'Tax'}</p>
			<p class="record-tax__value">
				{rateText}
				{#if taxMinor !== null}
					<span class="record-tax__amount">{money.format(taxMinor / 100)}</span>
				{/if}
			</p>
			<p class="record-tax__source">{SOURCE_LABEL[taxSource]}</p>
		</div>
	{/if}
</RailCard>

{#if open}
	<Dialog {open} title={configured ? 'Edit tax' : 'Set tax'} size="small" onClose={close}>
		<div class="record-tax-dialog">
			{#if error}<p class="record-tax-dialog__error" role="alert">{error}</p>{/if}

			<div class="record-tax-dialog__field">
				<label class="record-tax-dialog__label" for="record-tax-source">Tax</label>
				<Select
					id="record-tax-source"
					bind:value={draftValue}
					options={sourceOptions}
					disabled={saving}
				/>
			</div>

			{#if draftValue === 'custom'}
				<Input
					id="record-tax-custom-name"
					label="What the client sees this called"
					disabled={saving}
					bind:value={draftCustomName}
					invalid={Boolean(fieldErrors.custom_name)}
					errorMessage={fieldErrors.custom_name ?? ''}
				/>
				<Input
					id="record-tax-custom-rate"
					label="Rate %"
					inputmode="decimal"
					disabled={saving}
					bind:value={draftCustomRate}
					invalid={Boolean(fieldErrors.custom_rate_basis_points)}
					errorMessage={fieldErrors.custom_rate_basis_points ?? ''}
				/>
				{#if canManageTaxes}
					<Checkbox
						id="record-tax-save-reusable"
						label="Save as a reusable rate"
						description="Adds it to your organization's saved tax rates for future work."
						bind:checked={draftSaveReusable}
						disabled={saving}
					/>
				{/if}
			{/if}

			<p class="record-tax-dialog__note">
				Tax is added on top of the price and skips any line marked exempt.
			</p>

			<div class="record-tax-dialog__actions">
				<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}>
					Cancel
				</Button>
				<Button variant="primary" loading={saving} onclick={save}>Save tax</Button>
			</div>
		</div>
	</Dialog>
{/if}

<style lang="scss">
	.record-tax__muted {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.record-tax__unset {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		margin-bottom: var(--space-small);
	}

	.record-tax__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.record-tax__set {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.record-tax__name {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.record-tax__value {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
		margin: 0;
		color: var(--color-text--secondary);
	}

	.record-tax__amount {
		color: var(--color-heading);
		font-weight: 600;
	}

	.record-tax__source {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.record-tax-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__error {
			margin: 0;
			color: var(--color-destructive);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
