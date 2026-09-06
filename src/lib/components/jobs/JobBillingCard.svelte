<script lang="ts">
	import { untrack } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import JobPaymentScheduleDialog from '$lib/components/jobs/JobPaymentScheduleDialog.svelte';
	import { saveJobBilling, type JobPaymentSchedule, type JobWriteError } from '$lib/jobs/api';
	import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
	import type { InvoiceDerivedStatus } from '$lib/invoices/statuses';
	import type { JobType } from '$lib/jobs/statuses';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

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
		// A reader without invoices.view learns only that a bill exists, never which one or where it stands.
		invoiced: 'Invoiced',
		...INVOICE_STATUS_LABELS
	};

	function stageTone(status: string) {
		if (status === 'remaining') return undefined;
		if (status === 'invoiced') return 'inactive' as const;
		return INVOICE_STATUS_TONES[status as InvoiceDerivedStatus] ?? 'inactive';
	}

	// Billing one stage (Invoices 5c-3). Same move as the visits and periods cards: hand the choice to the
	// invoice composer by navigating, rather than opening a second dialog here. The composer seeds itself
	// from the job and the stage, and the server prices the stage again when it saves.
	const canBillStage = $derived(canInvoice && canSeePrice && Boolean(clientId));

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

<RailCard title="Billing" icon={receiptIcon}>
	{#snippet actions()}
		{#if editable}
			<Button variant="tertiary" size="small" onclick={openDialog}>Edit</Button>
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
							<span class="job-billing__stage-name">{stage.description}</span>
							{#if stage.amount_minor !== null}
								<span class="job-billing__stage-amount">
									{money.format(stage.amount_minor / 100)}
								</span>
							{/if}
							<div class="job-billing__stage-meta">
								<Badge size="small" status={stageTone(stage.status)}>
									{STAGE_LABELS[stage.status] ?? stage.status}
								</Badge>
								{#if canBillStage && stage.status === 'remaining'}
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
										href={resolve('/(app)/invoices/[id]', { id: stage.invoice.id })}
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
		onClose={() => (scheduleOpen = false)}
		{onSaved}
	/>
{/if}

{#if open}
	<Dialog {open} title="Billing setup" size="small" onClose={close}>
		<div class="job-billing-dialog">
			{#if error}<p class="job-billing-dialog__error" role="alert">{error}</p>{/if}

			<Select
				id="job-billing-basis"
				label="How is this work priced?"
				options={basisOptions}
				disabled={saving || basisOptions.length === 1}
				bind:value={draftBasis}
			/>
			{#if draftSummary}
				<p class="job-billing-dialog__summary">{draftSummary}</p>
			{/if}

			<Select
				id="job-billing-timing"
				label="When should we be reminded to invoice?"
				options={timingOptions}
				disabled={saving}
				bind:value={draftTiming}
			/>

			<p class="job-billing-dialog__note">
				Collecting the money is a separate decision and lives with Payments. Nothing here charges a
				client.
			</p>

			<div class="job-billing-dialog__actions">
				<Button variant="secondary" variation="subtle" disabled={saving} onclick={close}>
					Cancel
				</Button>
				<Button variant="primary" loading={saving} disabled={!changed} onclick={save}>
					Save billing
				</Button>
			</div>
		</div>
	</Dialog>
{/if}

<style lang="scss">
	.job-billing {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;

		&__row {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
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

	.job-billing-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			color: var(--color-destructive);
		}

		&__summary {
			margin: 0;
			color: var(--color-text--secondary);
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
