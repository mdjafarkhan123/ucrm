<script lang="ts">
	import { untrack } from 'svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import type { QuoteDiscountType, QuoteWriteError } from '$lib/quotes/api';
	import discountIcon from '@tabler/icons/outline/discount.svg?raw';

	// The one discount a priced record carries, named the way the customer reads it. The card shows what is
	// set and how much came off; the dialog is where it is changed. Like any dialog that owns a piece of the
	// record on its own, it writes the moment its button is pressed and never waits on the page's save bar.
	//
	// The amount taken off is the database's figure, not one worked out here — a percentage discount is
	// applied to non-taxable value first, and only the calculation knows how that landed.
	//
	// A quote and a job discount the same way, so this card belongs to neither: the page hands it the one
	// function that writes, and the card knows nothing about which record it is pricing.
	let {
		revision,
		name,
		type,
		value,
		discountMinor = null,
		currencyCode = 'USD',
		locale = 'en-US',
		editable = false,
		canSeePrice = true,
		recordNoun = 'quote',
		onSave,
		onSaved
	}: {
		/** The revision the page last read. A stale one comes back as a conflict, not a silent write. */
		revision: number;
		name: string | null;
		type: QuoteDiscountType | null;
		/** Whole cents for a fixed discount, basis points for a percentage one. */
		value: number | null;
		/** What the discount actually took off, as the database calculated it. */
		discountMinor?: number | null;
		currencyCode?: string;
		locale?: string;
		editable?: boolean;
		canSeePrice?: boolean;
		/** What the record is called in the sentence a stale save produces. */
		recordNoun?: string;
		/** Writes the discount against the revision it is handed. */
		onSave: (
			revision: number,
			payload: { name: string | null; type: QuoteDiscountType | null; value: number | null }
		) => Promise<unknown>;
		onSaved: (result: unknown) => Promise<void> | void;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const configured = $derived(type !== null);

	/** "10% off" or "$50.00 off" — what was asked for, beside what it came to. */
	const valueText = $derived.by(() => {
		if (type === 'percentage') return `${((value ?? 0) / 100).toFixed(2).replace(/\.?0+$/, '')}%`;
		if (type === 'fixed') return money.format((value ?? 0) / 100);
		return '';
	});

	let open = $state(false);
	let draftName = $state('');
	let draftType = $state<QuoteDiscountType>('percentage');
	let draftFixed = $state(0);
	let draftPercent = $state('');
	let saving = $state(false);
	let error = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	function openDialog() {
		draftName = name ?? 'Discount';
		draftType = type ?? 'percentage';
		draftFixed = type === 'fixed' ? (value ?? 0) : 0;
		draftPercent = type === 'percentage' ? ((value ?? 0) / 100).toString() : '';
		error = '';
		fieldErrors = {};
		open = true;
	}

	function close() {
		if (saving) return;
		open = false;
	}

	async function write(payload: {
		name: string | null;
		type: QuoteDiscountType | null;
		value: number | null;
	}) {
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
		if (draftType === 'percentage') {
			const parsed = Number(draftPercent);
			if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 100) {
				fieldErrors = { value: 'Enter a percentage between 0 and 100.' };
				return;
			}
			void write({
				name: draftName.trim() || null,
				type: 'percentage',
				value: Math.round(parsed * 100)
			});
			return;
		}
		if (draftFixed <= 0) {
			fieldErrors = { value: 'Enter an amount above zero.' };
			return;
		}
		void write({ name: draftName.trim() || null, type: 'fixed', value: draftFixed });
	}
</script>

<RailCard title="Discount" icon={discountIcon}>
	{#snippet actions()}
		{#if editable && canSeePrice && configured}
			<Button variant="tertiary" size="small" onclick={openDialog}>Edit</Button>
		{/if}
	{/snippet}

	{#if !canSeePrice}
		<p class="record-discount__muted">You do not have access to these prices.</p>
	{:else if configured}
		<div class="record-discount__set">
			<p class="record-discount__name">{name || 'Discount'}</p>
			<p class="record-discount__value">
				{valueText} off
				{#if discountMinor !== null}
					<span class="record-discount__amount">−{money.format(discountMinor / 100)}</span>
				{/if}
			</p>
		</div>
	{:else if editable}
		<Button variant="secondary" variation="subtle" fullWidth onclick={openDialog}>
			Add discount
		</Button>
	{:else}
		<p class="record-discount__muted">No discount on this {recordNoun}.</p>
	{/if}
</RailCard>

{#if open}
	<Dialog {open} title={configured ? 'Edit discount' : 'Add discount'} size="small" onClose={close}>
		<div class="record-discount-dialog">
			{#if error}<p class="record-discount-dialog__error" role="alert">{error}</p>{/if}

			<Input
				id="record-discount-name"
				label="What the client sees this called"
				disabled={saving}
				bind:value={draftName}
				invalid={Boolean(fieldErrors.name)}
				errorMessage={fieldErrors.name ?? ''}
			/>

			<SegmentedControl
				label="Discount type"
				value={draftType}
				options={[
					{ value: 'percentage', label: 'Percentage' },
					{ value: 'fixed', label: 'Amount' }
				]}
				disabled={saving}
				onchange={(next) => {
					draftType = next as QuoteDiscountType;
					fieldErrors = {};
				}}
			/>

			{#if draftType === 'percentage'}
				<Input
					id="record-discount-percent"
					label="Percentage off"
					inputmode="decimal"
					disabled={saving}
					bind:value={draftPercent}
					invalid={Boolean(fieldErrors.value)}
					errorMessage={fieldErrors.value ?? ''}
				/>
			{:else}
				<MoneyInput
					id="record-discount-amount"
					label="Amount off"
					disabled={saving}
					bind:value={draftFixed}
					invalid={Boolean(fieldErrors.value)}
					errorMessage={fieldErrors.value ?? ''}
				/>
			{/if}

			<div class="record-discount-dialog__actions">
				{#if configured}
					<Button
						variant="tertiary"
						variation="destructive"
						disabled={saving}
						onclick={() => void write({ name: null, type: null, value: null })}
					>
						Remove discount
					</Button>
				{/if}
				<div class="record-discount-dialog__confirm">
					<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}>
						Cancel
					</Button>
					<Button variant="primary" loading={saving} onclick={save}>Save discount</Button>
				</div>
			</div>
		</div>
	</Dialog>
{/if}

<style lang="scss">
	.record-discount__muted {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.record-discount__set {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.record-discount__name {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.record-discount__value {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
		margin: 0;
		color: var(--color-text--secondary);
	}

	.record-discount__amount {
		color: var(--color-heading);
		font-weight: 600;
	}

	.record-discount-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-destructive);
		}

		&__actions {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			margin-top: var(--space-small);

			/* Three short verbs on one line. Left to itself, "Remove discount" breaks across two lines and
			   the row grows taller than the fields above it. */
			:global(.button) {
				white-space: nowrap;
			}
		}

		/* Cancel and Save stay together on the right, whether or not Remove is there to their left. */
		&__confirm {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}
	}
</style>
