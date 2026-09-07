<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import MoneyInput from '$lib/components/forms/MoneyInput.svelte';
	import {
		saveJobPaymentSchedule,
		type JobPaymentStage,
		type JobPaymentStageInput,
		type JobWriteError
	} from '$lib/jobs/api';

	// The editor for a one-off job's payment stages. It is the quote's installment editor with one thing
	// added: a stage that already has an invoice is history, so it is shown as a fixed row that cannot be
	// renamed, re-priced or removed. The database refuses such an edit anyway; this stops a person from
	// composing one in the first place.
	//
	// A schedule is one mode throughout — every stage an amount, or every stage a percentage — which is why
	// the choice sits at the top of the dialog rather than on each row. A schedule that already has a billed
	// stage is stuck with that stage's mode.
	let {
		open,
		jobId,
		revision,
		stages,
		totalMinor,
		currencyCode = 'USD',
		locale = 'en-US',
		onClose,
		onSaved
	}: {
		open: boolean;
		jobId: string;
		/** The revision the page last read. A stale one comes back as a conflict, not a silent write. */
		revision: number;
		/** The stages the job has now. Empty when this is the first schedule being written. */
		stages: JobPaymentStage[];
		/** The job total every stage has to add back up to. */
		totalMinor: number;
		currencyCode?: string;
		locale?: string;
		onClose: () => void;
		onSaved: () => Promise<void> | void;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);

	// A row keeps both a fixed and a percentage draft rather than one shared number, so switching the mode
	// never has to guess whether a leftover figure was cents or basis points.
	type DraftRow = {
		/** A browser-minted key, not the array index — removing a middle row must not move which input DOM
		 *  node (and its focus state) belongs to which row. */
		key: string;
		installmentId: string | null;
		description: string;
		fixedValue: number;
		percentDraft: string;
		locked: boolean;
	};

	let saving = $state(false);
	let error = $state('');

	function toDraftRow(stage: JobPaymentStage): DraftRow {
		return {
			key: crypto.randomUUID(),
			installmentId: stage.installment_id,
			description: stage.description,
			fixedValue: stage.value_type === 'fixed' ? (stage.value ?? 0) : 0,
			percentDraft: stage.value_type === 'percentage' ? ((stage.value ?? 0) / 100).toString() : '',
			locked: stage.locked
		};
	}

	function emptyRow(): DraftRow {
		return {
			key: crypto.randomUUID(),
			installmentId: null,
			description: '',
			fixedValue: 0,
			percentDraft: '',
			locked: false
		};
	}

	// The parent mounts this dialog only while it is open, so the draft is seeded once here, at creation,
	// rather than watched into place by an effect. A schedule that already has a billed stage opens in that
	// stage's mode; a job with no schedule yet opens on two empty stages, the smallest a schedule may be.
	let mode = $state<'fixed' | 'percentage'>(
		untrack(() => (stages[0]?.value_type === 'percentage' ? 'percentage' : 'fixed'))
	);
	let rows = $state<DraftRow[]>(
		untrack(() => (stages.length > 0 ? stages.map(toDraftRow) : [emptyRow(), emptyRow()]))
	);

	const hasBilledStage = $derived(rows.some((row) => row.locked));
	const configured = $derived(stages.length > 0);

	/** Whole cents for a fixed row, basis points for a percentage one; zero while the field is unusable. */
	function rawValue(row: DraftRow): number {
		if (mode === 'fixed') return row.fixedValue;
		const parsed = Number(row.percentDraft);
		return Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed * 100) : 0;
	}

	// Percentage stages are priced as a set, never one row at a time. This mirrors
	// `private.price_job_payment_schedule` exactly: floor every share, then hand the leftover cents out one
	// apiece by largest fractional part, ties going to the earlier stage. Rounding each row on its own left
	// the running total a cent off the job's, so a schedule that reconciles perfectly on save looked broken
	// while it was being typed. A locked stage is priced by that same pass on the server, which refuses the
	// save if the result no longer matches what it was billed at, so it is not held out of the spread here.
	const rowAmounts = $derived.by(() => {
		if (mode === 'fixed') return rows.map((row) => row.fixedValue);

		const shares = rows.map((row) => {
			const exact = (totalMinor * rawValue(row)) / 10000;
			const base = Math.floor(exact);
			return { base, fraction: exact - base };
		});
		let residual = totalMinor - shares.reduce((sum, share) => sum + share.base, 0);
		const order = shares
			.map((share, index) => ({ index, fraction: share.fraction }))
			.sort((a, b) => b.fraction - a.fraction || a.index - b.index);
		for (const entry of order) {
			if (residual <= 0) break;
			shares[entry.index].base += 1;
			residual -= 1;
		}
		return shares.map((share) => share.base);
	});

	const plannedTotal = $derived(rowAmounts.reduce((sum, amount) => sum + amount, 0));

	// A row that sits before a billed one cannot be removed: dropping it would move the billed stage's
	// position, and a billed stage keeps everything about it, position included.
	const lastBilledIndex = $derived(
		rows.reduce((last, row, index) => (row.locked ? index : last), -1)
	);

	function canRemove(index: number) {
		return !rows[index].locked && index > lastBilledIndex && rows.length > 2;
	}

	function addRow() {
		if (rows.length >= 12) return;
		rows = [...rows, emptyRow()];
	}

	function removeRow(index: number) {
		if (!canRemove(index)) return;
		rows = rows.filter((_, rowIndex) => rowIndex !== index);
	}

	async function write(stagesToSave: JobPaymentStageInput[]) {
		if (saving) return;
		saving = true;
		error = '';
		try {
			await saveJobPaymentSchedule(
				jobId,
				untrack(() => revision),
				stagesToSave
			);
			onClose();
			await onSaved();
		} catch (cause) {
			const failure = cause as JobWriteError;
			error =
				failure.reason === 'stale'
					? 'Someone else changed this job. Close this, check the latest figures, and try again.'
					: (failure.fieldErrors?.form ?? failure.message);
		} finally {
			saving = false;
		}
	}

	function save() {
		if (totalMinor <= 0) {
			error = 'Add priced lines to this job before setting a payment schedule.';
			return;
		}
		if (rows.length < 2) {
			error = 'A payment schedule needs at least 2 stages.';
			return;
		}
		for (const row of rows) {
			if (row.description.trim().length < 2) {
				error = 'Give every stage a description.';
				return;
			}
			if (rawValue(row) <= 0) {
				error = 'Every stage needs an amount above zero.';
				return;
			}
		}
		if (mode === 'percentage') {
			const basisPoints = rows.reduce((sum, row) => sum + rawValue(row), 0);
			if (basisPoints !== 10000) {
				error = `The percentages must add up to 100%. They currently add up to ${(basisPoints / 100).toFixed(2)}%.`;
				return;
			}
		} else if (plannedTotal !== totalMinor) {
			error = `The stages must add up to the job total. They currently add up to ${money.format(
				plannedTotal / 100
			)} but the total is ${money.format(totalMinor / 100)}.`;
			return;
		}

		void write(
			rows.map((row) => ({
				installment_id: row.installmentId,
				description: row.description.trim(),
				type: mode,
				value: rawValue(row)
			}))
		);
	}
</script>

<Dialog
	{open}
	title={configured ? 'Edit payment schedule' : 'Add a payment schedule'}
	size="default"
	onClose={saving ? () => {} : onClose}
>
	<div class="schedule-dialog">
		{#if error}<p class="schedule-dialog__error" role="alert">{error}</p>{/if}

		<p class="schedule-dialog__intro">
			Split this job into stages you invoice one at a time. Every stage together has to come to the
			job total, {money.format(totalMinor / 100)}.
		</p>

		<SegmentedControl
			label="How is each stage set?"
			value={mode}
			options={[
				{ value: 'fixed', label: 'Amounts' },
				{ value: 'percentage', label: 'Percentages' }
			]}
			disabled={saving || hasBilledStage}
			onchange={(next) => {
				mode = next as 'fixed' | 'percentage';
				error = '';
			}}
		/>
		{#if hasBilledStage}
			<p class="schedule-dialog__note">
				One of these stages has already been invoiced, so the schedule stays as it is set and that
				stage cannot be changed.
			</p>
		{/if}

		<div class="schedule-dialog__rows">
			{#each rows as row, index (row.key)}
				<div class="schedule-dialog__row">
					<Input
						id={`job-stage-${index}-description`}
						label="Stage"
						disabled={saving || row.locked}
						bind:value={row.description}
					/>
					{#if mode === 'percentage'}
						<Input
							id={`job-stage-${index}-percent`}
							label="Percent"
							inputmode="decimal"
							disabled={saving || row.locked}
							bind:value={row.percentDraft}
						/>
					{:else}
						<MoneyInput
							id={`job-stage-${index}-amount`}
							label="Amount"
							disabled={saving || row.locked}
							bind:value={row.fixedValue}
						/>
					{/if}
					<span class="schedule-dialog__amount">{money.format(rowAmounts[index] / 100)}</span>
					{#if row.locked}
						<Badge size="small" status="informative">Invoiced</Badge>
					{:else}
						<Button
							variant="tertiary"
							variation="destructive"
							size="small"
							disabled={saving || !canRemove(index)}
							onclick={() => removeRow(index)}
						>
							Remove
						</Button>
					{/if}
				</div>
			{/each}
		</div>

		<Button
			variant="secondary"
			variation="subtle"
			disabled={saving || rows.length >= 12}
			onclick={addRow}
		>
			Add stage
		</Button>

		<p class="schedule-dialog__note">
			Adds up to {money.format(plannedTotal / 100)} of {money.format(totalMinor / 100)}.
		</p>

		<div class="schedule-dialog__actions">
			{#if configured && !hasBilledStage}
				<Button
					variant="tertiary"
					variation="destructive"
					disabled={saving}
					onclick={() => void write([])}
				>
					Remove schedule
				</Button>
			{/if}
			<div class="schedule-dialog__confirm">
				<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
					Cancel
				</Button>
				<Button variant="primary" loading={saving} onclick={save}>Save schedule</Button>
			</div>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.schedule-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-destructive);
		}

		&__intro,
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
			grid-template-columns: 2fr 1fr auto auto;
			align-items: end;
			gap: var(--space-small);
		}

		&__amount {
			padding-bottom: var(--space-small);
			color: var(--color-text--secondary);
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
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
