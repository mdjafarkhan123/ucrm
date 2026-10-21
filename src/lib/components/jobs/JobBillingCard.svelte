<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { Snippet } from 'svelte';
	import { untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import JobPaymentScheduleDialog from '$lib/components/jobs/JobPaymentScheduleDialog.svelte';
	import { saveJobBilling, type JobPaymentSchedule, type JobWriteError } from '$lib/jobs/api';
	import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
	import type { InvoiceDerivedStatus } from '$lib/invoices/statuses';
	import type { JobType } from '$lib/jobs/statuses';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import cardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import coinIcon from '@tabler/icons/outline/coin.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import listNumbersIcon from '@tabler/icons/outline/list-numbers.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// The job's billing setup, which the contract insists is *three* separate decisions and never one
	// selector: how the work is priced, when we invoice, and how the money is collected. This card owns the
	// first two. The third belongs to Payments, so there is no control for it here at all — choosing an
	// invoicing rhythm can never quietly switch on a card charge.
	//
	// The reminders are for our own team, not messages to the client, and the card says so in those words.
	// Chasing a customer for payment belongs to Invoices and Communications.
	let {
		jobId,
		revision,
		jobType,
		priceBasis,
		billingTiming,
		totalMinor = null,
		schedule = null,
		currencyCode = 'USD',
		locale = 'en-US',
		editable = false,
		canSeePrice = true,
		canInvoice = false,
		clientId = null,
		jobLine = '',
		extra,
		onSaved
	}: {
		jobId: string;
		/** The revision the page last read. A stale one comes back as a conflict, not a silent write. */
		revision: number;
		/** Fixed at creation, and it decides which pricing bases are even offered. */
		jobType: JobType;
		priceBasis: string;
		billingTiming: string;
		/** The job total, used only to say the choice back in money the contractor recognises. */
		totalMinor?: number | null;
		/** A one-off job's payment stages, or null when it bills as a whole. */
		schedule?: JobPaymentSchedule | null;
		currencyCode?: string;
		locale?: string;
		editable?: boolean;
		canSeePrice?: boolean;
		/** Whether this reader may raise an invoice at all. Without it a stage offers no billing action. */
		canInvoice?: boolean;
		/** The job's client, which the invoice composer needs. Null on a job that somehow has none. */
		clientId?: string | null;
		/** "Job #1042 · Kitchen cabinet refit", the quiet line under each pop-up's title. */
		jobLine?: string;
		/** More to draw inside the card, after the payment schedule (the job's invoice reminders). */
		extra?: Snippet;
		onSaved: () => Promise<void> | void;
	} = $props();

	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);

	const BASIS_LABEL: Record<string, string> = {
		job_total: 'One price for the whole job',
		per_visit: 'A price for each visit',
		fixed_per_period: 'A fixed amount each billing period'
	};

	const TIMING_LABEL: Record<string, string> = {
		on_closure: 'Once, when the job is finished',
		per_completed_visit: 'After each completed visit',
		month_end: 'At the end of every month',
		custom_dates: 'On dates we pick ourselves',
		manual: 'Never remind us — we will decide'
	};

	// A one-off job is priced as a whole job and nothing else; repeating work chooses between the other two.
	// The database refuses the wrong pairing anyway, so this list is convenience, not the rule.
	const basisOptions = $derived(
		jobType === 'one_off'
			? [{ value: 'job_total', label: BASIS_LABEL.job_total }]
			: [
					{ value: 'per_visit', label: BASIS_LABEL.per_visit },
					{ value: 'fixed_per_period', label: BASIS_LABEL.fixed_per_period }
				]
	);

	const timingOptions = Object.entries(TIMING_LABEL).map(([value, label]) => ({ value, label }));

	/** The choice said back in money — "$2,400 for the whole job" — so it is checkable before saving. */
	function summaryFor(basis: string) {
		if (!canSeePrice || totalMinor === null) return null;
		const amount = money.format(totalMinor / 100);
		if (basis === 'per_visit') return `${amount} per completed visit`;
		if (basis === 'fixed_per_period')
			return `${amount} each billing period, whatever the visit count`;
		return `${amount} for the whole job`;
	}

	const summary = $derived(summaryFor(priceBasis));

	// --- The payment schedule -----------------------------------------------------------------------------
	// Only a one-off job can carry one, and only a reader who may see the job's money can see what the stages
	// are worth. A stage says where it has got to: still to bill, or the live status of the bill it produced.
	const stages = $derived(schedule?.stages ?? []);
	const canScheduleStages = $derived(jobType === 'one_off' && canSeePrice);
	const scheduleTotalMinor = $derived(schedule?.job_total_minor ?? totalMinor ?? 0);

	const STAGE_LABELS: Record<string, string> = {
		remaining: 'Still to bill',
		// A stage that was billed and then had that draft deleted. The stage is spent either way -- the amount
		// it was billed at is permanent -- so it never offers to be billed again, and says so rather than
		// pretending it is still to come.
		spent: 'Already billed',
		// A reader without invoices.view learns only that a bill exists, never which one or where it stands.
		invoiced: 'Invoiced',
		...INVOICE_STATUS_LABELS
	};

	function stageTone(status: string) {
		if (status === 'remaining') return undefined;
		if (status === 'spent') return 'inactive' as const;
		if (status === 'invoiced') return 'inactive' as const;
		return INVOICE_STATUS_TONES[status as InvoiceDerivedStatus] ?? 'inactive';
	}

	// Billing one stage (Invoices 5c-3). Same move as the visits and periods cards: hand the choice to the
	// invoice composer by navigating, rather than opening a second dialog here. The composer seeds itself
	// from the job and the stage, and the server prices the stage again when it saves.
	const canBillStage = $derived(canInvoice && canSeePrice && Boolean(clientId));

	// `locked` is the write command's own test -- the stage has been priced into a bill -- and it outlives the
	// bill. `status` only knows where a live bill stands, so the two disagree in exactly one case: a progress
	// draft that was created and then deleted. The stage is still spent, and only this reading offers no
	// button for it.
	function displayStatus(stage: (typeof stages)[number]) {
		return stage.status === 'remaining' && stage.locked ? 'spent' : stage.status;
	}

	function billStage(installmentId: string) {
		if (!clientId) return;
		void goto(
			`${resolve('/(app)/invoices/new')}?client=${clientId}&job=${jobId}&installment=${installmentId}`
		);
	}

	let scheduleOpen = $state(false);

	let open = $state(false);
	let draftBasis = $state('');
	let draftTiming = $state('');
	let saving = $state(false);
	let error = $state('');

	const draftSummary = $derived(summaryFor(draftBasis));
	// The decisions panel reads each choice back in a sentence, so it moves with the boxes.
	const priceDecision = $derived(
		canSeePrice && totalMinor !== null
			? `${BASIS_LABEL[draftBasis] ?? draftBasis}: ${money.format(totalMinor / 100)}.`
			: `${BASIS_LABEL[draftBasis] ?? draftBasis}.`
	);
	const reminderDecision = $derived(
		`${TIMING_LABEL[draftTiming] ?? draftTiming}. A reminder for your team, nothing goes to the client.`
	);
	const changed = $derived(draftBasis !== priceBasis || draftTiming !== billingTiming);

	function openDialog() {
		draftBasis = priceBasis;
		draftTiming = billingTiming;
		error = '';
		open = true;
	}

	function close() {
		if (saving) return;
		open = false;
	}

	async function save() {
		if (saving || !changed) return;
		saving = true;
		error = '';
		try {
			await saveJobBilling(
				jobId,
				untrack(() => revision),
				{ price_basis: draftBasis, billing_timing: draftTiming }
			);
			open = false;
			await onSaved();
		} catch (cause) {
			const failure = cause as JobWriteError;
			error =
				failure.reason === 'stale'
					? 'Someone else changed this job. Close this, check the latest, and try again.'
					: (failure.fieldErrors?.form ?? failure.message);
		} finally {
			saving = false;
		}
	}
</script>

<RailCard
	tone="invoice"
	title="Billing"
	description="How and when this job is invoiced"
	icon={receiptIcon}
	compact={false}
	class="job-billing-card"
>
	{#snippet actions()}
		{#if editable}
			<PencilButton onclick={openDialog} label="Edit billing setup" />
		{/if}
	{/snippet}

	<dl class="job-billing">
		<div class="job-billing__row">
			<dt class="job-billing__label">How it is priced</dt>
			<dd class="job-billing__value">
				{BASIS_LABEL[priceBasis] ?? priceBasis}
				{#if summary}<span class="job-billing__summary">{summary}</span>{/if}
			</dd>
		</div>
		<div class="job-billing__row">
			<dt class="job-billing__label">Remind our team to invoice</dt>
			<dd class="job-billing__value">{TIMING_LABEL[billingTiming] ?? billingTiming}</dd>
		</div>
	</dl>

	{#if canScheduleStages}
		<div class="job-billing__schedule">
			<p class="job-billing__label">Payment schedule</p>

			{#if stages.length > 0}
				{#if schedule?.reconciles === false}
					<p class="job-billing__warning" role="status">
						These stages no longer add up to the job total. Edit the stages that have not been
						invoiced yet so they match.
					</p>
				{/if}
				<ul class="job-billing__stages">
					{#each stages as stage (stage.installment_id)}
						<li class="job-billing__stage">
							<IconTile icon={cardIcon} tone="invoice" size={32} />
							<span class="job-billing__stage-name">{stage.description}</span>
							{#if stage.amount_minor !== null}
								<span class="job-billing__stage-amount">
									{money.format(stage.amount_minor / 100)}
								</span>
							{/if}
							<div class="job-billing__stage-meta">
								<Badge size="small" status={stageTone(displayStatus(stage))}>
									{STAGE_LABELS[displayStatus(stage)] ?? stage.status}
								</Badge>
								{#if canBillStage && displayStatus(stage) === 'remaining'}
									<Button
										variant="tertiary"
										size="small"
										onclick={() => billStage(stage.installment_id)}
									>
										Create invoice
									</Button>
								{:else if stage.invoice}
									<a
										class="job-billing__stage-link"
										href={resolve('/(app)/invoices/[id=uuid]', { id: stage.invoice.id })}
									>
										Invoice #{stage.invoice.invoice_number}
									</a>
								{/if}
							</div>
						</li>
					{/each}
				</ul>
				{#if editable}
					<Button
						variant="secondary"
						variation="subtle"
						fullWidth
						onclick={() => (scheduleOpen = true)}
					>
						Edit payment schedule
					</Button>
				{/if}
			{:else if editable}
				<p class="job-billing__note">
					This job is invoiced in one go. Split it into stages to invoice it as the work goes.
				</p>
				<Button
					variant="secondary"
					variation="subtle"
					fullWidth
					onclick={() => (scheduleOpen = true)}
				>
					Add a payment schedule
				</Button>
			{:else}
				<p class="job-billing__note">This job is invoiced in one go.</p>
			{/if}
		</div>
	{/if}

	{#if extra}{@render extra()}{/if}

	<p class="job-billing__note">
		Reminders are prompts for your own team, not messages to the client. Payment is collected by
		hand for now.
	</p>
</RailCard>

{#if scheduleOpen}
	<JobPaymentScheduleDialog
		open={scheduleOpen}
		{jobId}
		{revision}
		{stages}
		totalMinor={scheduleTotalMinor}
		{currencyCode}
		{locale}
		{jobLine}
		onClose={() => (scheduleOpen = false)}
		{onSaved}
	/>
{/if}

{#if open}
	<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
	<!-- eslint-disable svelte/no-at-html-tags -->
	<Dialog
		{open}
		title="Billing setup"
		subtitle={jobLine || undefined}
		size="medium"
		icon={receiptIcon}
		iconTone="invoice"
		flush
		onClose={close}
	>
		<div class="job-billing-dialog">
			<div class="job-billing-dialog__form">
				{#if error}<Banner type="error">{error}</Banner>{/if}

				<Select
					id="job-billing-basis"
					label="How is this work priced?"
					options={basisOptions}
					disabled={saving || basisOptions.length === 1}
					locked={basisOptions.length === 1}
					bind:value={draftBasis}
				/>
				{#if draftSummary}
					<p class="job-billing-dialog__summary">
						<IconTile icon={coinIcon} tone="invoice" size={24} white />
						{draftSummary}
					</p>
				{/if}

				<Select
					id="job-billing-timing"
					label="When should we be reminded to invoice?"
					options={timingOptions}
					disabled={saving}
					bind:value={draftTiming}
				/>
			</div>

			<section class="job-billing-dialog__panel" aria-labelledby="job-billing-decisions">
				<header class="job-billing-dialog__panel-head">
					<IconTile icon={listNumbersIcon} tone="invoice" size={32} white />
					<h3 id="job-billing-decisions">Three decisions</h3>
				</header>
				<ol class="job-billing-dialog__decisions">
					<li class="job-billing-dialog__decision">
						<p class="job-billing-dialog__decision-head">
							<span class="job-billing-dialog__decision-icon" aria-hidden="true"
								>{@html coinIcon}</span
							>
							<span class="job-billing-dialog__decision-title">Price</span>
							<span class="job-billing-dialog__decision-number">1</span>
						</p>
						<p class="job-billing-dialog__decision-text">{priceDecision}</p>
					</li>
					<li class="job-billing-dialog__decision">
						<p class="job-billing-dialog__decision-head">
							<span class="job-billing-dialog__decision-icon" aria-hidden="true"
								>{@html bellIcon}</span
							>
							<span class="job-billing-dialog__decision-title">Invoice reminder</span>
							<span class="job-billing-dialog__decision-number">2</span>
						</p>
						<p class="job-billing-dialog__decision-text">{reminderDecision}</p>
					</li>
					<li class="job-billing-dialog__decision job-billing-dialog__decision--elsewhere">
						<p class="job-billing-dialog__decision-head">
							<span
								class="job-billing-dialog__decision-icon job-billing-dialog__decision-icon--quiet"
								aria-hidden="true">{@html cardIcon}</span
							>
							<span class="job-billing-dialog__decision-title">Collect the money</span>
							<Badge size="small" status="inactive">Not set here</Badge>
						</p>
						<p class="job-billing-dialog__decision-text">
							Lives with Payments. Nothing here charges a client.
						</p>
					</li>
				</ol>
			</section>
		</div>

		{#snippet footer()}
			<div class="job-billing-dialog__actions">
				<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}>
					Cancel
				</Button>
				<Button variant="primary" loading={saving} disabled={!changed} onclick={save}>
					{@html checkIcon}
					Save billing
				</Button>
			</div>
		{/snippet}
	</Dialog>
	<!-- eslint-enable svelte/no-at-html-tags -->
{/if}

<style lang="scss">
	.job-billing {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		grid-template-columns: repeat(2, minmax(0, 1fr));

		&__row {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__schedule > &__label {
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.08em;
			text-transform: uppercase;
		}

		&__value {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__summary {
			color: var(--color-text--secondary);
			font-weight: 400;
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__schedule {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__warning {
			margin: 0;
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			border-radius: var(--radius-base);
			padding: var(--space-small);
			font-size: var(--typography--fontSize-small);
		}

		&__stages {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__stage {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
				padding-top: var(--space-small);
			}
		}

		&__stage-name {
			flex: 1;
			min-width: 0;
			overflow-wrap: anywhere;
			color: var(--color-heading);
		}

		// Status and its one action share a line of their own under the stage's name and amount: the rail is
		// too narrow to hold all four side by side without the name running over the money.
		&__stage-meta {
			display: flex;
			flex-basis: 100%;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__stage-amount {
			color: var(--color-text--secondary);
			font-variant-numeric: tabular-nums;
			white-space: nowrap;
		}

		&__stage-link {
			color: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
		}
	}

	// Concept look (Job details `tNdkX`): the card's parts run edge to edge, each with 20px sides and a
	// full-width rule above it; a payment stage reads on one line, led by a card tile.
	:global(.record-detail--cards .rail-card--concept.job-billing-card) {
		padding-bottom: 0;
	}
	:global(.record-detail--cards .rail-card--concept.job-billing-card > :not(.card-header)) {
		margin: 0;
		padding: var(--space-base) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
	}
	:global(
		.record-detail--cards .rail-card--concept.job-billing-card > .job-billing__note:last-child
	) {
		padding-top: 0;
		border-top: 0;
	}
	:global(.record-detail--cards .rail-card--concept.job-billing-card > :nth-child(2)) {
		border-top: 0;
	}
	:global(.record-detail--cards) .job-billing {
		&__stage {
			flex-wrap: nowrap;
			gap: var(--space-slim);
			padding: var(--space-small) 0;

			& + & {
				padding-top: var(--space-small);
			}
		}

		&__stage-name,
		&__stage-amount {
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__stage-amount {
			color: var(--color-heading);
		}

		&__stage-meta {
			flex-basis: auto;
			justify-content: flex-end;
		}
	}

	// Billing setup pop-up (Batch 50 B): the two boxes at the left, the three decisions the card keeps apart at
	// the right. Both sides run to the pop-up's edges, so the body is flush and each side pads itself.
	.job-billing-dialog {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 330px;

		&__form {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			min-width: 0;
			padding: var(--space-medium);
		}

		// The saved choice said back in money, so it is checkable before saving.
		&__summary {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: 10px var(--space-slim);
			border: var(--border-base) solid var(--color-invoice--surface-edge);
			border-radius: 12px;
			background: var(--color-invoice--surface);
			color: var(--color-invoice--onSurface);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
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

		&__decisions {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__decision {
			display: flex;
			flex-direction: column;
			gap: 10px;
			padding: var(--space-slim) var(--space-slim) var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-invoice--surface-edge);
			border-radius: 12px;
			background: var(--color-surface);

			// Not decided here: the card stays but steps back.
			&--elsewhere {
				opacity: 0.8;
			}
		}

		&__decision-head {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
		}

		&__decision-icon {
			display: inline-flex;
			color: var(--color-invoice);

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&--quiet {
				color: var(--color-icon--secondary);
			}
		}

		&__decision-title {
			flex: 1 1 auto;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__decision-number {
			color: var(--color-invoice);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__decision-text {
			margin: 0;
			color: var(--color-text);
			font-size: 13px;
			line-height: 1.45;
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}
	}
</style>
