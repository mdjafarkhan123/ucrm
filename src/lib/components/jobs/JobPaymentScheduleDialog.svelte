<script lang="ts">
	import { untrack } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
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
	import stackIcon from '@tabler/icons/outline/stack-2.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash-banknote.svg?raw';
	import percentIcon from '@tabler/icons/outline/percentage.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import circlePlusIcon from '@tabler/icons/outline/circle-plus.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

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
		jobLine = '',
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
		/** "Job #1042 · Kitchen cabinet refit", the quiet line under the pop-up's title. */
		jobLine?: string;
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
	// Which button is waiting, so Remove schedule spins on its own press and Save schedule on its own.
	let removing = $state(false);
	let error = $state('');
	// The draft a refusal was about. Once the stages change, that message no longer describes the screen
	// (the live "Adds up to" line is the truth), so the banner steps aside until the next save says otherwise.
	let errorDraft = $state('');

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
	// Once every stage is billed the schedule already reconciles and not one row can move, so another stage
	// could only ever be refused — priced, it breaks the total; at zero, it is rejected outright.
	const allStagesBilled = $derived(rows.length > 0 && rows.every((row) => row.locked));
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
		// Only the rounding leftover is handed out. While the percentages are still short of 100% the rest of the
		// total is unassigned, not a cent per stage; at exactly 100% the target is the job total, as on the server.
		const basisPoints = rows.reduce((sum, row) => sum + rawValue(row), 0);
		const target = Math.round((totalMinor * basisPoints) / 10000);
		let residual = target - shares.reduce((sum, share) => sum + share.base, 0);
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
	const leftMinor = $derived(totalMinor - plannedTotal);

	// The Job total panel's bar: one part per stage in the invoice colour, each lighter than the last, and
	// the part of the total no stage has claimed yet in the border colour.
	const PART_OPACITY = [1, 0.7, 0.45, 0.3, 0.2];
	const partOpacity = (index: number) => PART_OPACITY[Math.min(index, PART_OPACITY.length - 1)];
	const unassignedMinor = $derived(Math.max(leftMinor, 0));

	const draftKey = $derived(
		JSON.stringify([mode, rows.map((row) => [row.description, row.fixedValue, row.percentDraft])])
	);
	const visibleError = $derived(error && errorDraft === draftKey ? error : '');

	function fail(message: string) {
		error = message;
		errorDraft = draftKey;
	}

	// A row that sits before a billed one cannot be removed: dropping it would move the billed stage's
	// position, and a billed stage keeps everything about it, position included.
	const lastBilledIndex = $derived(
		rows.reduce((last, row, index) => (row.locked ? index : last), -1)
	);

	function canRemove(index: number) {
		return !rows[index].locked && index > lastBilledIndex && rows.length > 2;
	}

	function addRow() {
		if (rows.length >= 12 || allStagesBilled) return;
		rows = [...rows, emptyRow()];
	}

	function removeRow(index: number) {
		if (!canRemove(index)) return;
		rows = rows.filter((_, rowIndex) => rowIndex !== index);
	}

	async function write(stagesToSave: JobPaymentStageInput[], removal = false) {
		if (saving) return;
		saving = true;
		removing = removal;
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
			fail(
				failure.reason === 'stale'
					? 'Someone else changed this job. Close this, check the latest figures, and try again.'
					: (failure.fieldErrors?.form ?? failure.message)
			);
		} finally {
			saving = false;
			removing = false;
		}
	}

	function save() {
		if (totalMinor <= 0) {
			fail('Add priced lines to this job before setting a payment schedule.');
			return;
		}
		if (rows.length < 2) {
			fail('A payment schedule needs at least 2 stages.');
			return;
		}
		for (const row of rows) {
			if (row.description.trim().length < 2) {
				fail('Give every stage a description.');
				return;
			}
			if (rawValue(row) <= 0) {
				fail('Every stage needs an amount above zero.');
				return;
			}
		}
		if (mode === 'percentage') {
			const basisPoints = rows.reduce((sum, row) => sum + rawValue(row), 0);
			if (basisPoints !== 10000) {
				fail(
					`The percentages must add up to 100%. They currently add up to ${(basisPoints / 100).toFixed(2)}%.`
				);
				return;
			}
		} else if (plannedTotal !== totalMinor) {
			fail(
				`The stages must add up to the job total. They currently add up to ${money.format(
					plannedTotal / 100
				)} but the total is ${money.format(totalMinor / 100)}.`
			);
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

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title={configured ? 'Edit payment schedule' : 'Add a payment schedule'}
	subtitle={jobLine || undefined}
	size="large"
	icon={stackIcon}
	iconTone="invoice"
	flush
	onClose={saving ? () => {} : onClose}
>
	<div class="schedule-dialog">
		<div class="schedule-dialog__stages">
			{#if visibleError}<Banner type="error">{visibleError}</Banner>{/if}

			<p class="schedule-dialog__intro">
				Split this job into stages you invoice one at a time. Every stage together has to come to
				the job total, {money.format(totalMinor / 100)}.
			</p>

			<SegmentedControl
				label="How is each stage set?"
				fullWidth
				value={mode}
				options={[
					{
						value: 'fixed',
						label: 'Amounts',
						icon: cashIcon,
						disabled: hasBilledStage && mode !== 'fixed'
					},
					{
						value: 'percentage',
						label: 'Percentages',
						icon: percentIcon,
						disabled: hasBilledStage && mode !== 'percentage'
					}
				]}
				disabled={saving}
				onchange={(next) => {
					mode = next as 'fixed' | 'percentage';
					error = '';
				}}
			/>
			{#if hasBilledStage}
				<Banner type="notice">
					One of these stages has already been invoiced, so the schedule stays as it is set and that
					stage cannot be changed.
				</Banner>
			{/if}

			<div
				class="schedule-dialog__list"
				class:schedule-dialog__list--percent={mode === 'percentage'}
				class:schedule-dialog__list--billed={hasBilledStage}
			>
				<div class="schedule-dialog__head" aria-hidden="true">
					<span>Stage</span>
					<span>{mode === 'percentage' ? 'Percent' : 'Amount'}</span>
					{#if mode === 'percentage'}<span class="schedule-dialog__head-amount">Amount</span>{/if}
					<span></span>
				</div>
				{#each rows as row, index (row.key)}
					<div class="schedule-dialog__row">
						<Input
							id={`job-stage-${index}-description`}
							label="Stage"
							size="small"
							disabled={saving || row.locked}
							bind:value={row.description}
						/>
						{#if mode === 'percentage'}
							<div class="schedule-dialog__percent">
								<Input
									id={`job-stage-${index}-percent`}
									label="Percent"
									size="small"
									inputmode="decimal"
									disabled={saving || row.locked}
									bind:value={row.percentDraft}
								/>
								<span class="schedule-dialog__percent-sign" aria-hidden="true">%</span>
							</div>
						{:else}
							<MoneyInput
								{currencyCode}
								id={`job-stage-${index}-amount`}
								label="Amount"
								size="small"
								disabled={saving || row.locked}
								bind:value={row.fixedValue}
							/>
						{/if}
						{#if mode === 'percentage'}
							<span class="schedule-dialog__amount">{money.format(rowAmounts[index] / 100)}</span>
						{/if}
						<span class="schedule-dialog__trail">
							{#if row.locked}
								<Badge size="small" status="informative">Invoiced</Badge>
							{:else}
								<Button
									variant="quiet"
									size="small"
									iconOnly
									label="Remove stage"
									class="schedule-dialog__remove"
									disabled={saving || !canRemove(index)}
									onclick={() => removeRow(index)}
								>
									{@html trashIcon}
								</Button>
							{/if}
						</span>
					</div>
				{/each}
				<div class="schedule-dialog__add">
					<Button
						variant="quiet"
						size="small"
						class="schedule-dialog__add-button"
						disabled={saving || rows.length >= 12 || allStagesBilled}
						onclick={addRow}
					>
						{@html circlePlusIcon}
						Add stage
					</Button>
				</div>
			</div>
		</div>

		<section class="schedule-dialog__panel" aria-labelledby="job-schedule-total-title">
			<header class="schedule-dialog__panel-head">
				<IconTile icon={receiptIcon} tone="invoice" size={32} white />
				<h3 id="job-schedule-total-title">Job total</h3>
			</header>
			<div class="schedule-dialog__total">
				<p class="schedule-dialog__total-amount">{money.format(totalMinor / 100)}</p>
				<div class="schedule-dialog__bar" aria-hidden="true">
					{#each rowAmounts as amount, index (rows[index].key)}
						{#if amount > 0}
							<span
								class="schedule-dialog__bar-part"
								style:flex-grow={amount}
								style:opacity={partOpacity(index)}
							></span>
						{/if}
					{/each}
					{#if unassignedMinor > 0}
						<span
							class="schedule-dialog__bar-part schedule-dialog__bar-part--rest"
							style:flex-grow={unassignedMinor}
						></span>
					{/if}
				</div>
				<ul class="schedule-dialog__legend">
					{#each rows as row, index (row.key)}
						<li class="schedule-dialog__legend-line">
							<span class="schedule-dialog__dot" style:opacity={partOpacity(index)}></span>
							<span class="schedule-dialog__legend-name">
								{row.description.trim() || `Stage ${index + 1}`}
							</span>
							<strong>{money.format(rowAmounts[index] / 100)}</strong>
						</li>
					{/each}
				</ul>
				<p
					class="schedule-dialog__left"
					class:schedule-dialog__left--done={leftMinor === 0}
					role="status"
				>
					<span class="schedule-dialog__left-icon" aria-hidden="true">
						{@html leftMinor === 0 ? circleCheckIcon : alertTriangleIcon}
					</span>
					<span class="schedule-dialog__left-name">Left to assign</span>
					<strong>{money.format(leftMinor / 100)}</strong>
				</p>
			</div>
		</section>
	</div>

	{#snippet footer()}
		{#if configured && !hasBilledStage}
			<Button
				variant="secondary"
				variation="destructive"
				loading={removing}
				disabled={saving && !removing}
				onclick={() => void write([], true)}
			>
				{@html trashIcon}
				Remove schedule
			</Button>
		{/if}
		<div class="schedule-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving && !removing} disabled={removing} onclick={save}>
				{@html checkIcon}
				Save schedule
			</Button>
		</div>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Payment schedule pop-up (Batch 50 B): the stages at the left, a "Job total" panel at the right that
	// shows how the stages share the total. Both sides run to the pop-up's edges, so the body is flush.
	.schedule-dialog {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 340px;

		&__stages {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			min-width: 0;
			padding: var(--space-medium);
		}

		&__intro {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		// One box holds the column names, every stage and the Add stage band. The trailing column holds the
		// remove button, or the "Invoiced" pill, which is wider, so every row gives it the same room.
		&__list {
			--schedule-trail: 32px;
			display: flex;
			flex-direction: column;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: 12px;

			&--billed {
				--schedule-trail: 84px;
			}
		}

		&__head,
		&__row {
			display: grid;
			grid-template-columns: minmax(0, 1fr) 150px var(--schedule-trail);
			align-items: center;
			gap: var(--space-slim);
			padding: 10px var(--space-small) 10px 14px;
		}

		&__list--percent &__head,
		&__list--percent &__row {
			grid-template-columns: minmax(0, 1fr) 110px 100px var(--schedule-trail);
		}

		&__head {
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__head-amount {
			text-align: right;
		}

		&__row {
			border-top: var(--border-base) solid var(--color-border);

			// Boxes are 36 high, so the labels they carry for screen readers stay out of sight.
			:global(.input__label) {
				position: absolute;
				width: 1px;
				height: 1px;
				overflow: hidden;
				clip-path: inset(50%);
				white-space: nowrap;
			}
		}

		&__percent {
			position: relative;

			:global(input) {
				padding-right: 18px;
				text-align: right;
				font-weight: 600;
			}
		}

		&__percent-sign {
			position: absolute;
			top: 50%;
			right: var(--space-slim);
			transform: translateY(-50%);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			pointer-events: none;
		}

		&__amount {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			font-variant-numeric: tabular-nums;
			text-align: right;
			white-space: nowrap;
		}

		&__trail {
			display: flex;
			justify-content: flex-end;
		}

		:global(.schedule-dialog__remove) {
			color: var(--color-icon--secondary);

			&:hover:not(:disabled) {
				color: var(--color-critical);
			}
		}

		&__add {
			padding: var(--space-small) var(--space-small);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		:global(.schedule-dialog__add-button) {
			color: var(--color-interactive);
		}

		&__panel {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			padding: var(--space-medium);
			border-left: var(--border-base) solid var(--color-invoice--surface-edge);
			background: var(--color-invoice--surface);
		}

		&__panel-head {
			display: flex;
			align-items: center;
			gap: var(--space-slim);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: 16px;
				font-weight: 600;
			}
		}

		&__total {
			display: flex;
			flex-direction: column;
			gap: 14px;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-invoice--surface-edge);
			border-radius: 12px;
			background: var(--color-surface);
		}

		&__total-amount {
			margin: 0;
			color: var(--color-heading);
			font-size: 40px;
			font-weight: 700;
			letter-spacing: -1px;
			font-variant-numeric: tabular-nums;
		}

		&__bar {
			display: flex;
			gap: 3px;
			height: 8px;
		}

		&__bar-part {
			flex: 1 1 0;
			min-width: 0;
			border-radius: var(--radius-small);
			background: var(--color-invoice);

			&--rest {
				background: var(--color-border);
			}
		}

		&__legend {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__legend-line {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text);
			font-size: 13px;
			font-weight: 500;

			strong {
				margin-left: auto;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
				font-variant-numeric: tabular-nums;
			}
		}

		&__legend-name {
			min-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__dot {
			flex: 0 0 auto;
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-invoice);
		}

		&__left {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding-top: 14px;
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-warning);
			font-size: 13px;
			font-weight: 500;

			// The icon keeps the state colour; the amount takes its on-surface shade so it reads on white.
			strong {
				margin-left: auto;
				color: var(--color-warning--onSurface);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
				font-variant-numeric: tabular-nums;
			}

			&--done {
				color: var(--color-success);

				strong {
					color: var(--color-success--onSurface);
				}
			}
		}

		&__left-name {
			color: var(--color-text);
		}

		&__left-icon {
			display: inline-flex;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}
	}
</style>
