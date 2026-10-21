<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RailRow from '$lib/components/layout/RailRow.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import type { QuoteTaxSource, QuoteWriteError } from '$lib/quotes/api';
	import { fetchTaxPicker, taxPickerKey } from '$lib/settings/api';
	import {
		checkTax,
		percentText,
		taxDraftFrom,
		taxSourceOptions,
		type TaxPayload
	} from '$lib/work/pricing-adjustments';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

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
		staged = false,
		dialogHint,
		recordTone = 'quote',
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
		/** The record does not exist yet. The page holds the choice and writes it when the record is saved, so
		 * there is nothing to announce as saved here. */
		staged?: boolean;
		/** The record line under the pop-up's title, e.g. "Quote #1042 · Gutter cleaning". */
		dialogHint?: string;
		/** The record colour of the pop-up's icon tile (`quote`, `invoice`, `job`). */
		recordTone?: string;
		/** Writes the tax choice against the revision it is handed. */
		onSave: (revision: number, payload: TaxPayload) => Promise<unknown>;
		onSaved: (result: unknown) => Promise<void> | void;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const configured = $derived(taxSource !== 'not_configured');
	const rateText = $derived(`${percentText(rateBasisPoints)}%`);
	/** Still waiting on someone to choose: the row's tile and value turn yellow. */
	const waiting = $derived(taxSource === 'not_configured' && canSeePrice);

	const SOURCE_LABEL: Record<QuoteTaxSource, string> = {
		not_configured: 'Not configured',
		business_default: 'Business default',
		property_default: 'From the property',
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

	const sourceOptions = $derived(taxSourceOptions(picker));

	let draftValue = $state('business_default');
	let draftCustomName = $state('');
	let draftCustomRate = $state('');
	let draftSaveReusable = $state(false);
	const toast = getToastManager();
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function openDialog() {
		const draft = taxDraftFrom(taxSource, rateId, name, rateBasisPoints);
		draftValue = draft.value;
		draftCustomName = draft.customName;
		draftCustomRate = draft.customRate;
		draftSaveReusable = draft.saveReusable;
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
			if (!staged) toast.success('Tax saved');
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
		const checked = checkTax(
			{
				value: draftValue,
				customName: draftCustomName,
				customRate: draftCustomRate,
				saveReusable: draftSaveReusable
			},
			canManageTaxes
		);
		if (checked.fieldErrors) {
			fieldErrors = checked.fieldErrors;
			return;
		}
		void write(checked.payload);
	}
</script>

<RailRow
	icon={receiptIcon}
	label="Tax"
	tone={waiting ? 'warning' : 'neutral'}
	value={!canSeePrice
		? 'No access to prices'
		: taxSource === 'not_configured'
			? 'Not configured'
			: taxSource === 'no_tax'
				? 'No tax'
				: `${name || 'Tax'} ${rateText}`}
	valueTone={!canSeePrice ? 'quiet' : waiting ? 'warning' : 'default'}
	sub={canSeePrice && configured && taxSource !== 'no_tax' ? SOURCE_LABEL[taxSource] : undefined}
	amount={canSeePrice && configured && taxSource !== 'no_tax' && taxMinor !== null
		? money.format(taxMinor / 100)
		: undefined}
>
	{#snippet actions()}
		{#if editable && canSeePrice}
			<PencilButton
				onclick={openDialog}
				onhover={warm}
				label={taxSource === 'not_configured' ? 'Set the tax' : 'Edit the tax'}
			/>
		{/if}
	{/snippet}
</RailRow>

{#if open}
	<Dialog
		{open}
		title={configured ? 'Edit tax' : 'Set tax'}
		subtitle={dialogHint}
		icon={receiptIcon}
		iconTone={recordTone}
		size="small"
		onClose={close}
	>
		<div class="record-tax-dialog">
			{#if error}<p class="record-tax-dialog__error" role="alert">{error}</p>{/if}

			<Select
				id="record-tax-source"
				label="Tax"
				bind:value={draftValue}
				options={sourceOptions}
				disabled={saving}
			/>

			{#if draftValue === 'custom'}
				<div class="record-tax-dialog__row">
					<Input
						id="record-tax-custom-name"
						label="What the client sees this called"
						disabled={saving}
						bind:value={draftCustomName}
						invalid={Boolean(fieldErrors.custom_name)}
						errorMessage={fieldErrors.custom_name ?? ''}
					/>
					<div class="record-tax-dialog__rate">
						<Input
							id="record-tax-custom-rate"
							label="Rate %"
							inputmode="decimal"
							disabled={saving}
							bind:value={draftCustomRate}
							invalid={Boolean(fieldErrors.custom_rate_basis_points)}
							errorMessage={fieldErrors.custom_rate_basis_points ?? ''}
						/>
					</div>
				</div>
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
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="record-tax-dialog__note-icon" aria-hidden="true">{@html infoIcon}</span>
				Tax is added on top of the price and skips any line marked exempt.
			</p>
		</div>

		{#snippet footer()}
			<div class="record-tax-dialog__actions">
				<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}>
					Cancel
				</Button>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<Button variant="primary" loading={saving} onclick={save}
					>{@html checkIcon}{staged ? 'Apply to draft' : 'Save tax'}</Button
				>
			</div>
		{/snippet}
	</Dialog>
{/if}

<style lang="scss">
	.record-tax-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		/* Cancel and Save sit together on the right, as in every form pop-up. */
		&__actions {
			display: flex;
			gap: var(--space-small);
		}

		&__error {
			margin: 0;
			color: var(--color-destructive);
		}

		/* The name the client reads and its rate sit on one line; the rate needs only a few digits. */
		&__row {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);

			> :global(:first-child) {
				flex: 1 1 auto;
				min-width: 0;
			}
		}

		&__rate {
			flex: 0 0 96px;
		}

		&__note {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: 10px 12px;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: 1.4;
		}

		&__note-icon {
			display: inline-flex;
			flex: 0 0 auto;
			color: var(--color-informative);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
	}
</style>
