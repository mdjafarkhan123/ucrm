<script lang="ts">
	import { untrack } from 'svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import {
		saveQuoteDeposit,
		recordQuoteDepositEvent,
		reverseQuoteDepositEvent,
		type QuoteDepositType,
		type QuoteDepositScheduleItem,
		type QuoteDepositEvent,
		type QuoteDepositMethod,
		type QuoteWriteError
	} from '$lib/quotes/api';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';

	// The deposit a quote asks for, folded into one card: configuring the shape (deposit-only or a payment
	// schedule) and, once the quote is sent, recording or reversing the offline receipt against it — per
	// Jafar's 2026-08-21 call not to split recording into a card of its own.
	//
	// Configuration writes the draft, the same lock/bump shape as Tax and Discount. Recording and reversing
	// are a different kind of write entirely — an immutable ledger row that never touches the draft's own
	// revision — so `onSaved` here takes no result to thread through; the page always just re-reads the quote.
	let {
		quoteId,
		revision,
		depositType,
		scheduleItems,
		depositRequiredMinor = null,
		depositEvents,
		totalMinor,
		currencyCode = 'USD',
		locale = 'en-US',
		editable = false,
		canSeePrice = true,
		canRecordDeposit = false,
		hasPublishedVersion = false,
		onSaved
	}: {
		quoteId: string;
		/** The draft revision the page last read. A stale one comes back as a conflict, not a silent write. */
		revision: number;
		depositType: QuoteDepositType | null;
		/** The installments for whichever version is on screen — draft while one is in progress. */
		scheduleItems: QuoteDepositScheduleItem[];
		/** What this version's deposit prices out to. Null when there is nothing configured. */
		depositRequiredMinor?: number | null;
		/** The receipt ledger for the currently published version only. */
		depositEvents: QuoteDepositEvent[];
		/** The draft's current total, needed to check a schedule's installments sum correctly before saving. */
		totalMinor: number;
		currencyCode?: string;
		locale?: string;
		editable?: boolean;
		canSeePrice?: boolean;
		canRecordDeposit?: boolean;
		/** Whether there is a sent version to record a deposit against at all. */
		hasPublishedVersion?: boolean;
		onSaved: () => Promise<void> | void;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	const configured = $derived(depositType !== null);

	const METHOD_LABELS: Record<QuoteDepositMethod, string> = {
		cash: 'Cash',
		check: 'Check',
		other: 'Other'
	};

	function pricedAmount(item: { value_type: 'fixed' | 'percentage'; value: number }) {
		return item.value_type === 'fixed' ? item.value : Math.round((totalMinor * item.value) / 10000);
	}

	// The most recent word on whether money has actually changed hands: the last received row that no
	// reversal names, or — if the last thing that happened was a reversal — that reversal itself, so a
	// deposit that was recorded and undone reads as "not received" rather than silently disappearing.
	const latestEvent = $derived(depositEvents[depositEvents.length - 1] ?? null);
	const liveReceipt = $derived(
		depositEvents.find(
			(event) =>
				event.event_type === 'received' &&
				!depositEvents.some((other) => other.reversed_event_id === event.id)
		) ?? null
	);
	const canRecord = $derived(
		canRecordDeposit && hasPublishedVersion && !liveReceipt && (depositRequiredMinor ?? 0) > 0
	);
	const canReverse = $derived(canRecordDeposit && Boolean(liveReceipt));

	// --- Configuring the deposit -------------------------------------------------------------------------

	// A row keeps both a fixed and a percentage draft rather than one shared number — switching a row's type
	// does not have to guess whether a leftover figure was cents or basis points. Only the one matching its
	// current `type` is read at save time, the same way the deposit-only fields below already work.
	type DraftRow = {
		/** A browser-minted id, not the array index — removing a middle row must not shift which input DOM
		 *  node (and its focus/composition state) belongs to which row. */
		key: string;
		description: string;
		type: 'fixed' | 'percentage';
		fixedValue: number;
		percentDraft: string;
	};

	let configOpen = $state(false);
	let configMode = $state<QuoteDepositType>('deposit_only');
	let depositOnlyType = $state<'fixed' | 'percentage'>('percentage');
	let depositOnlyFixed = $state(0);
	let depositOnlyPercent = $state('');
	let scheduleRows = $state<DraftRow[]>([]);
	let configSaving = $state(false);
	let configError = $state('');

	function toDraftRow(item: { description: string; value_type: string; value: number }): DraftRow {
		const type = item.value_type as 'fixed' | 'percentage';
		return {
			key: crypto.randomUUID(),
			description: item.description,
			type,
			fixedValue: type === 'fixed' ? item.value : 0,
			percentDraft: type === 'percentage' ? (item.value / 100).toString() : ''
		};
	}

	function emptyRow(): DraftRow {
		return {
			key: crypto.randomUUID(),
			description: '',
			type: 'fixed',
			fixedValue: 0,
			percentDraft: ''
		};
	}

	function openConfig() {
		configMode = depositType ?? 'deposit_only';
		const first = scheduleItems[0];
		depositOnlyType =
			configMode === 'deposit_only' && first
				? (first.value_type as 'fixed' | 'percentage')
				: 'percentage';
		depositOnlyFixed =
			configMode === 'deposit_only' && first?.value_type === 'fixed' ? first.value : 0;
		depositOnlyPercent =
			configMode === 'deposit_only' && first?.value_type === 'percentage'
				? (first.value / 100).toString()
				: '';
		scheduleRows =
			configMode === 'schedule' && scheduleItems.length
				? scheduleItems.map(toDraftRow)
				: [emptyRow()];
		configError = '';
		configOpen = true;
	}

	function closeConfig() {
		if (configSaving) return;
		configOpen = false;
	}

	// The raw figure the server expects: whole cents for a fixed row, basis points for a percentage one —
	// zero when the percentage field does not yet hold a valid number, same as the deposit-only fields.
	function rowRawValue(row: DraftRow): number {
		if (row.type === 'fixed') return row.fixedValue;
		const parsed = Number(row.percentDraft);
		return Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed * 100) : 0;
	}

	function rowPricedAmount(row: DraftRow): number {
		return pricedAmount({ value_type: row.type, value: rowRawValue(row) });
	}

	const scheduleSum = $derived(scheduleRows.reduce((sum, row) => sum + rowPricedAmount(row), 0));

	function addRow() {
		if (scheduleRows.length >= 12) return;
		scheduleRows = [...scheduleRows, emptyRow()];
	}

	function removeRow(index: number) {
		if (scheduleRows.length <= 1) return;
		scheduleRows = scheduleRows.filter((_, rowIndex) => rowIndex !== index);
	}

	async function writeConfig(
		depositTypeToSave: QuoteDepositType | null,
		items: { description: string; type: 'fixed' | 'percentage'; value: number }[]
	) {
		if (configSaving) return;
		configSaving = true;
		configError = '';
		try {
			await saveQuoteDeposit(
				quoteId,
				untrack(() => revision),
				{ deposit_type: depositTypeToSave, items }
			);
			configOpen = false;
			await onSaved();
		} catch (cause) {
			const failure = cause as QuoteWriteError;
			configError =
				failure.reason === 'stale'
					? 'Someone else changed this quote. Close this, check the latest figures, and try again.'
					: (failure.fieldErrors?.form ?? failure.message);
		} finally {
			configSaving = false;
		}
	}

	function saveConfig() {
		if (configMode === 'deposit_only') {
			if (depositOnlyType === 'percentage') {
				const parsed = Number(depositOnlyPercent);
				if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 100) {
					configError = 'Enter a percentage between 0 and 100.';
					return;
				}
				void writeConfig('deposit_only', [
					{ description: 'Deposit', type: 'percentage', value: Math.round(parsed * 100) }
				]);
				return;
			}
			if (depositOnlyFixed <= 0) {
				configError = 'Enter an amount above zero.';
				return;
			}
			void writeConfig('deposit_only', [
				{ description: 'Deposit', type: 'fixed', value: depositOnlyFixed }
			]);
			return;
		}

		if (totalMinor <= 0) {
			configError = 'Add line items to this quote before setting a payment schedule.';
			return;
		}
		for (const row of scheduleRows) {
			if (row.description.trim().length < 2) {
				configError = 'Give every installment a description.';
				return;
			}
			if (rowRawValue(row) <= 0) {
				configError = 'Every installment needs an amount above zero.';
				return;
			}
		}
		if (scheduleSum !== totalMinor) {
			configError = `Installments must add up to the quote total. They currently add up to ${money.format(
				scheduleSum / 100
			)} but the total is ${money.format(totalMinor / 100)}.`;
			return;
		}
		void writeConfig(
			'schedule',
			scheduleRows.map((row) => ({
				description: row.description.trim(),
				type: row.type,
				value: rowRawValue(row)
			}))
		);
	}

	// --- Recording and reversing --------------------------------------------------------------------------

	let recordOpen = $state(false);
	let recordMethod = $state<QuoteDepositMethod>('cash');
	let recordReference = $state('');
	let recordNote = $state('');
	let recordSaving = $state(false);
	let recordError = $state('');
	let recordKey = crypto.randomUUID();

	function openRecord() {
		recordMethod = 'cash';
		recordReference = '';
		recordNote = '';
		recordError = '';
		recordKey = crypto.randomUUID();
		recordOpen = true;
	}

	function closeRecord() {
		if (recordSaving) return;
		recordOpen = false;
	}

	async function submitRecord() {
		if (recordSaving) return;
		recordSaving = true;
		recordError = '';
		try {
			await recordQuoteDepositEvent(quoteId, {
				idempotencyKey: recordKey,
				method: recordMethod,
				reference: recordReference.trim() || null,
				note: recordNote.trim() || null
			});
			recordOpen = false;
			await onSaved();
		} catch (cause) {
			const failure = cause as QuoteWriteError;
			recordError = failure.fieldErrors?.form ?? failure.message;
		} finally {
			recordSaving = false;
		}
	}

	let reverseOpen = $state(false);
	let reverseReason = $state('');
	let reverseSaving = $state(false);
	let reverseError = $state('');
	let reverseKey = crypto.randomUUID();

	function openReverse() {
		reverseReason = '';
		reverseError = '';
		reverseKey = crypto.randomUUID();
		reverseOpen = true;
	}

	function closeReverse() {
		if (reverseSaving) return;
		reverseOpen = false;
	}

	async function submitReverse() {
		if (reverseSaving || !liveReceipt) return;
		reverseSaving = true;
		reverseError = '';
		try {
			await reverseQuoteDepositEvent(quoteId, liveReceipt.id, {
				idempotencyKey: reverseKey,
				reason: reverseReason.trim()
			});
			reverseOpen = false;
			await onSaved();
		} catch (cause) {
			const failure = cause as QuoteWriteError;
			reverseError = failure.fieldErrors?.form ?? failure.message;
		} finally {
			reverseSaving = false;
		}
	}
</script>

<RailCard title="Deposit" icon={cashIcon}>
	{#snippet actions()}
		{#if editable && canSeePrice && configured}
			<Button variant="tertiary" size="small" onclick={openConfig}>Edit</Button>
		{/if}
	{/snippet}

	{#if !canSeePrice}
		<p class="quote-deposit__muted">You do not have access to quote prices.</p>
	{:else if configured}
		<div class="quote-deposit__set">
			<p class="quote-deposit__name">
				{depositType === 'schedule' ? 'Payment schedule' : 'Deposit'}
			</p>
			{#if depositRequiredMinor !== null}
				<p class="quote-deposit__amount">{money.format(depositRequiredMinor / 100)}</p>
			{/if}

			{#if depositType === 'schedule'}
				<ul class="quote-deposit__schedule">
					{#each scheduleItems as item (item.id)}
						<li class="quote-deposit__schedule-row">
							<span>{item.description}</span>
							<span>{money.format(pricedAmount(item) / 100)}</span>
						</li>
					{/each}
				</ul>
			{/if}

			{#if liveReceipt}
				<p class="quote-deposit__status quote-deposit__status--received">
					Received {money.format(liveReceipt.amount_minor / 100)} · {METHOD_LABELS[
						liveReceipt.method
					]} · {dateFormat.format(new Date(liveReceipt.created_at))}
				</p>
				{#if liveReceipt.reference}
					<p class="quote-deposit__note">Ref: {liveReceipt.reference}</p>
				{/if}
				{#if liveReceipt.note}
					<p class="quote-deposit__note">{liveReceipt.note}</p>
				{/if}
			{:else if latestEvent?.event_type === 'reversed'}
				<p class="quote-deposit__status">
					Reversed on {dateFormat.format(new Date(latestEvent.created_at))} — not yet recorded again.
				</p>
			{:else if hasPublishedVersion}
				<p class="quote-deposit__status">Awaiting deposit.</p>
			{:else}
				<p class="quote-deposit__muted">The deposit will be requested once this quote is sent.</p>
			{/if}

			{#if canRecord}
				<Button variant="secondary" variation="subtle" fullWidth onclick={openRecord}>
					Record deposit received
				</Button>
			{:else if canReverse}
				<Button variant="tertiary" variation="destructive" fullWidth onclick={openReverse}>
					Reverse deposit
				</Button>
			{/if}
		</div>
	{:else if editable}
		<Button variant="secondary" variation="subtle" fullWidth onclick={openConfig}
			>Add deposit</Button
		>
	{:else}
		<p class="quote-deposit__muted">No deposit on this quote.</p>
	{/if}
</RailCard>

{#if configOpen}
	<Dialog
		open={configOpen}
		title={configured ? 'Edit deposit' : 'Add deposit'}
		size="default"
		onClose={closeConfig}
	>
		<div class="quote-deposit-dialog">
			{#if configError}<p class="quote-deposit-dialog__error" role="alert">{configError}</p>{/if}

			<SegmentedControl
				label="Deposit type"
				value={configMode}
				options={[
					{ value: 'deposit_only', label: 'Deposit only' },
					{ value: 'schedule', label: 'Payment schedule' }
				]}
				disabled={configSaving}
				onchange={(next) => {
					configMode = next as QuoteDepositType;
					configError = '';
				}}
			/>

			{#if configMode === 'deposit_only'}
				<SegmentedControl
					label="Amount type"
					value={depositOnlyType}
					options={[
						{ value: 'percentage', label: 'Percentage' },
						{ value: 'fixed', label: 'Amount' }
					]}
					disabled={configSaving}
					onchange={(next) => (depositOnlyType = next as 'fixed' | 'percentage')}
				/>
				{#if depositOnlyType === 'percentage'}
					<Input
						id="quote-deposit-percent"
						label="Percentage of the total"
						inputmode="decimal"
						disabled={configSaving}
						bind:value={depositOnlyPercent}
					/>
				{:else}
					<MoneyInput
						id="quote-deposit-amount"
						label="Deposit amount"
						disabled={configSaving}
						bind:value={depositOnlyFixed}
					/>
				{/if}
			{:else}
				<div class="quote-deposit-dialog__rows">
					{#each scheduleRows as row, index (row.key)}
						<div class="quote-deposit-dialog__row">
							<Input
								id={`quote-deposit-row-${index}-description`}
								label="Installment"
								disabled={configSaving}
								bind:value={row.description}
							/>
							<SegmentedControl
								size="small"
								value={row.type}
								options={[
									{ value: 'fixed', label: '$' },
									{ value: 'percentage', label: '%' }
								]}
								disabled={configSaving}
								onchange={(next) => {
									row.type = next as 'fixed' | 'percentage';
									row.fixedValue = 0;
									row.percentDraft = '';
								}}
							/>
							{#if row.type === 'percentage'}
								<Input
									id={`quote-deposit-row-${index}-percent`}
									label="Percent"
									inputmode="decimal"
									disabled={configSaving}
									bind:value={row.percentDraft}
								/>
							{:else}
								<MoneyInput
									id={`quote-deposit-row-${index}-amount`}
									label="Amount"
									disabled={configSaving}
									bind:value={row.fixedValue}
								/>
							{/if}
							<Button
								variant="tertiary"
								variation="destructive"
								size="small"
								disabled={configSaving || scheduleRows.length <= 1}
								onclick={() => removeRow(index)}
							>
								Remove
							</Button>
						</div>
					{/each}
				</div>
				<Button
					variant="secondary"
					variation="subtle"
					disabled={configSaving || scheduleRows.length >= 12}
					onclick={addRow}
				>
					Add installment
				</Button>
				<p class="quote-deposit-dialog__note">
					Adds up to {money.format(scheduleSum / 100)} of {money.format(totalMinor / 100)}.
				</p>
			{/if}

			<div class="quote-deposit-dialog__actions">
				{#if configured}
					<Button
						variant="tertiary"
						variation="destructive"
						disabled={configSaving}
						onclick={() => void writeConfig(null, [])}
					>
						Remove deposit
					</Button>
				{/if}
				<div class="quote-deposit-dialog__confirm">
					<Button
						variant="secondary"
						variation="subtle"
						disabled={configSaving}
						onclick={closeConfig}
					>
						Cancel
					</Button>
					<Button variant="primary" loading={configSaving} onclick={saveConfig}>Save deposit</Button
					>
				</div>
			</div>
		</div>
	</Dialog>
{/if}

{#if recordOpen}
	<Dialog open={recordOpen} title="Record deposit received" size="small" onClose={closeRecord}>
		<div class="quote-deposit-dialog">
			{#if recordError}<p class="quote-deposit-dialog__error" role="alert">{recordError}</p>{/if}

			<SegmentedControl
				label="How was it received"
				value={recordMethod}
				options={[
					{ value: 'cash', label: 'Cash' },
					{ value: 'check', label: 'Check' },
					{ value: 'other', label: 'Other' }
				]}
				disabled={recordSaving}
				onchange={(next) => (recordMethod = next as QuoteDepositMethod)}
			/>

			<Input
				id="quote-deposit-reference"
				label="Reference (optional)"
				disabled={recordSaving}
				bind:value={recordReference}
			/>

			<Textarea
				id="quote-deposit-record-note"
				label="Note (optional)"
				rows={3}
				maxlength={500}
				disabled={recordSaving}
				bind:value={recordNote}
			/>

			<div class="quote-deposit-dialog__actions">
				<div class="quote-deposit-dialog__confirm">
					<Button
						variant="secondary"
						variation="subtle"
						disabled={recordSaving}
						onclick={closeRecord}
					>
						Cancel
					</Button>
					<Button variant="primary" loading={recordSaving} onclick={() => void submitRecord()}>
						Record deposit
					</Button>
				</div>
			</div>
		</div>
	</Dialog>
{/if}

{#if reverseOpen}
	<Dialog open={reverseOpen} title="Reverse deposit" size="small" onClose={closeReverse}>
		<div class="quote-deposit-dialog">
			{#if reverseError}<p class="quote-deposit-dialog__error" role="alert">{reverseError}</p>{/if}

			<Textarea
				id="quote-deposit-reverse-reason"
				label="Why is this being reversed?"
				rows={3}
				maxlength={500}
				disabled={reverseSaving}
				bind:value={reverseReason}
			/>

			<div class="quote-deposit-dialog__actions">
				<div class="quote-deposit-dialog__confirm">
					<Button
						variant="secondary"
						variation="subtle"
						disabled={reverseSaving}
						onclick={closeReverse}
					>
						Cancel
					</Button>
					<Button
						variant="primary"
						variation="destructive"
						disabled={reverseReason.trim().length === 0}
						loading={reverseSaving}
						onclick={() => void submitReverse()}
					>
						Reverse deposit
					</Button>
				</div>
			</div>
		</div>
	</Dialog>
{/if}

<style lang="scss">
	.quote-deposit__muted {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.quote-deposit__set {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.quote-deposit__name {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.quote-deposit__amount {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.quote-deposit__schedule {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.quote-deposit__schedule-row {
		display: flex;
		justify-content: space-between;
		gap: var(--space-base);
		color: var(--color-text--secondary);
	}

	.quote-deposit__status {
		margin: 0;
		color: var(--color-text--secondary);

		&--received {
			color: var(--color-heading);
			font-weight: 600;
		}
	}

	.quote-deposit__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.quote-deposit-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-destructive);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__rows {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__row {
			display: grid;
			grid-template-columns: 2fr auto 1fr auto;
			align-items: end;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			margin-top: var(--space-small);

			:global(.button) {
				white-space: nowrap;
			}
		}

		&__confirm {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}
	}
</style>
