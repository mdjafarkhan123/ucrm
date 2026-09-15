<script lang="ts">
	import { createInfiniteQuery, createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import DataTable from '$lib/components/data-display/DataTable.svelte';
	import FilterBar from '$lib/components/data-display/FilterBar.svelte';
	import FilterField from '$lib/components/data-display/FilterField.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchSmsUsage,
		fetchSmsCreditTopups,
		fetchSmsLedger,
		requestSmsCreditTopup,
		cancelSmsCreditTopup,
		smsUsageKey,
		smsCreditTopupsKey,
		smsLedgerKey,
		smsCreditTopupStatusLabel,
		smsCreditTopupStatusTone,
		smsLedgerEntryKindLabel,
		smsAvailabilityLabel,
		smsAvailabilityTone,
		formatSmsMoney,
		SmsUsageWriteError,
		type SmsLedgerEntry
	} from '$lib/communications/sms-usage';
	import walletIcon from '@tabler/icons/outline/wallet.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import activityIcon from '@tabler/icons/outline/activity.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const usageQuery = createQuery(() => ({
		queryKey: smsUsageKey,
		queryFn: fetchSmsUsage,
		staleTime: 15_000
	}));
	const topupsQuery = createQuery(() => ({
		queryKey: smsCreditTopupsKey,
		queryFn: fetchSmsCreditTopups,
		staleTime: 15_000
	}));

	let entryKindFilter = $state('');
	const ledgerFilters = $derived(
		entryKindFilter ? { entry_kind: entryKindFilter } : ({} as { entry_kind?: string })
	);
	const ledgerQuery = createInfiniteQuery(() => ({
		queryKey: smsLedgerKey(ledgerFilters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchSmsLedger(pageParam, ledgerFilters),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
		staleTime: 15_000
	}));
	const ledgerEntries = $derived(ledgerQuery.data?.pages.flatMap((p) => p.entries) ?? []);

	const entryKindOptions = [
		{ value: '', label: 'All entry types' },
		{ value: 'credit', label: 'Top-up' },
		{ value: 'charge', label: 'Message charge' },
		{ value: 'refund', label: 'Refund' },
		{ value: 'adjustment', label: 'Adjustment' }
	];

	// Request top-up dialog --------------------------------------------------------------------
	let requestOpen = $state(false);
	let amountUsd = $state('');
	let offsiteReference = $state('');
	let requestNote = $state('');
	let requestFieldErrors = $state<Record<string, string>>({});

	function openRequest() {
		amountUsd = '';
		offsiteReference = '';
		requestNote = '';
		requestFieldErrors = {};
		requestOpen = true;
	}

	const requestMutation = createMutation(() => ({
		mutationFn: requestSmsCreditTopup,
		onSuccess: () => {
			queryClient.invalidateQueries({ queryKey: smsCreditTopupsKey });
			requestOpen = false;
			toast.success('Top-up requested', 'Jafar will confirm it once the payment arrives.');
		},
		onError: (error: unknown) => {
			if (error instanceof SmsUsageWriteError) {
				requestFieldErrors = error.fieldErrors;
				if (Object.keys(error.fieldErrors).length === 0) toast.error(error.message);
			} else {
				toast.error('The top-up request could not be submitted.');
			}
		}
	}));

	function submitRequest(event: SubmitEvent) {
		event.preventDefault();
		requestFieldErrors = {};
		const amount = Number(amountUsd);
		const amountMinor = Math.round(amount * 100);
		if (!Number.isFinite(amount) || amountMinor <= 0) {
			requestFieldErrors = { requested_amount_minor: 'Enter an amount greater than zero.' };
			return;
		}
		requestMutation.mutate({
			requested_amount_minor: amountMinor,
			offsite_reference: offsiteReference.trim() || null,
			note: requestNote.trim() || null
		});
	}

	// Cancel a still-pending request ------------------------------------------------------------
	let cancellingId = $state<string | null>(null);
	const cancelMutation = createMutation(() => ({
		mutationFn: cancelSmsCreditTopup,
		onSuccess: () => {
			queryClient.invalidateQueries({ queryKey: smsCreditTopupsKey });
			toast.success('Top-up request cancelled.');
		},
		onError: (error: unknown) => {
			toast.error(error instanceof Error ? error.message : 'The request could not be cancelled.');
		},
		onSettled: () => {
			cancellingId = null;
		}
	}));

	function cancelRequest(requestId: string) {
		cancellingId = requestId;
		cancelMutation.mutate(requestId);
	}

	function formatTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	function formatPercent(value: number | null) {
		if (value === null) return 'No sends yet';
		return `${(value * 100).toFixed(1)}%`;
	}

	const ledgerColumns = [
		{ key: 'occurred_at', label: 'Date' },
		{ key: 'entry_kind', label: 'Type' },
		{ key: 'reference', label: 'Reference' },
		{ key: 'bucket', label: 'Bucket' },
		{ key: 'amount', label: 'Amount', align: 'end' as const },
		{ key: 'balance_after', label: 'Balance after', align: 'end' as const }
	];
</script>

<svelte:head><title>SMS usage · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<PageHeader
		eyebrow="Settings · Communications"
		title="SMS usage"
		description="Your text messaging balance, this month's charges, and lean delivery health."
	/>

	{#if usageQuery.isPending}
		<LoadingSkeleton variant="card" rows={3} />
	{:else if usageQuery.isError}
		<ErrorState
			description="The SMS usage could not be loaded."
			retry={() => usageQuery.refetch()}
		/>
	{:else}
		{@const usage = usageQuery.data}
		<div class="sms-usage__balance-strip">
			<KpiCard
				tone="brand"
				label="Available balance"
				value={formatSmsMoney(usage.balance.spendable_balance_minor, usage.balance.currency_code)}
				note="Ready to spend on outbound texts"
				icon={walletIcon}
			/>
			<KpiCard
				label="Reserved"
				value={formatSmsMoney(usage.balance.reserved_balance_minor, usage.balance.currency_code)}
				note="Pending charges for messages in flight"
				icon={receiptIcon}
			/>
			<KpiCard
				label="Usage this month"
				value={formatSmsMoney(
					usage.usage_summary.retail_charge_minor,
					usage.balance.currency_code
				)}
				note={`${usage.usage_summary.messages} message${usage.usage_summary.messages === 1 ? '' : 's'} · ${usage.usage_summary.segments} segment${usage.usage_summary.segments === 1 ? '' : 's'}`}
				icon={activityIcon}
			/>
			<KpiCard
				tone={smsAvailabilityTone[usage.availability.state]}
				label="Sending availability"
				value={smsAvailabilityLabel[usage.availability.state]}
				note={usage.availability.reason ?? 'No pause is in effect'}
				icon={historyIcon}
			/>
		</div>

		<div class="sms-usage__add-credit">
			<div>
				<p class="sms-usage__add-credit-title">Need more balance?</p>
				<p class="sms-usage__add-credit-copy">
					Requesting a top-up creates no usable credit until Jafar confirms the payment arrived.
				</p>
			</div>
			<Button onclick={openRequest}>Request top-up</Button>
		</div>

		<SectionBlock title="Messaging health" icon={activityIcon} level={2}>
			<p class="sms-usage__hint">
				The last {usage.messaging_health.period_days} days. For message-by-message detail, use Conversations
				once it supports SMS.
			</p>
			<div class="sms-usage__health-grid">
				<KpiCard
					variant="compact"
					label="Sent"
					value={String(usage.messaging_health.sent)}
					note="Outbound attempts"
					icon={activityIcon}
				/>
				<KpiCard
					variant="compact"
					tone="success"
					label="Delivered"
					value={String(usage.messaging_health.delivered)}
					note="Confirmed by carrier"
					icon={activityIcon}
				/>
				<KpiCard
					variant="compact"
					tone="critical"
					label="Failed"
					value={String(usage.messaging_health.failed)}
					note="Could not be delivered"
					icon={activityIcon}
				/>
				<KpiCard
					variant="compact"
					label="Received"
					value={String(usage.messaging_health.received)}
					note="Coming with Conversations SMS"
					icon={activityIcon}
				/>
				<KpiCard
					variant="compact"
					label="Opt-out rate"
					value={formatPercent(usage.messaging_health.opt_out_rate)}
					note="Of messages sent"
					icon={activityIcon}
				/>
			</div>
		</SectionBlock>

		<SectionBlock title="Top-up requests" icon={receiptIcon} level={2}>
			{#if topupsQuery.isPending}
				<LoadingSkeleton variant="table" rows={2} />
			{:else if topupsQuery.isError}
				<ErrorState
					description="The top-up requests could not be loaded."
					retry={() => topupsQuery.refetch()}
				/>
			{:else if topupsQuery.data.requests.length === 0}
				<EmptyState
					icon={receiptIcon}
					title="No top-up requests yet"
					description="Request a top-up above once you need more balance."
				/>
			{:else}
				<ul class="sms-usage__topups">
					{#each topupsQuery.data.requests as request (request.id)}
						<li class="sms-usage__topup">
							<div>
								<p class="sms-usage__topup-amount">
									{formatSmsMoney(request.requested_amount_minor, request.currency_code)} requested
								</p>
								<p class="sms-usage__topup-meta">
									{formatTime(request.requested_at)}
									{#if request.offsite_reference}· Ref: {request.offsite_reference}{/if}
								</p>
								{#if request.status === 'confirmed' && request.settled_amount_minor !== null}
									<p class="sms-usage__topup-meta">
										Confirmed: {formatSmsMoney(request.settled_amount_minor, request.currency_code)}
									</p>
								{/if}
								{#if request.status === 'rejected' && request.decision_reason}
									<p class="sms-usage__topup-meta">Declined: {request.decision_reason}</p>
								{/if}
							</div>
							<div class="sms-usage__topup-actions">
								<StatusBadge status={smsCreditTopupStatusTone[request.status]}>
									{smsCreditTopupStatusLabel[request.status]}
								</StatusBadge>
								{#if request.status === 'awaiting_confirmation'}
									<Button
										size="small"
										variant="secondary"
										variation="subtle"
										loading={cancelMutation.isPending && cancellingId === request.id}
										onclick={() => cancelRequest(request.id)}
									>
										Cancel
									</Button>
								{/if}
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		</SectionBlock>

		<SectionBlock title="Ledger" icon={historyIcon} level={2}>
			<FilterBar onClear={entryKindFilter ? () => (entryKindFilter = '') : undefined}>
				<FilterField label="Entry type" id="sms-ledger-entry-kind">
					<Select id="sms-ledger-entry-kind" options={entryKindOptions} bind:value={entryKindFilter} />
				</FilterField>
			</FilterBar>

			{#if ledgerQuery.isPending}
				<LoadingSkeleton variant="table" rows={4} />
			{:else if ledgerQuery.isError}
				<ErrorState
					description="The ledger could not be loaded."
					retry={() => ledgerQuery.refetch()}
				/>
			{:else if ledgerEntries.length === 0}
				<EmptyState
					icon={historyIcon}
					title="Nothing here yet"
					description="Charges, top-up credits, refunds and adjustments will appear here once your account has activity."
				/>
			{:else}
				<DataTable
					columns={ledgerColumns}
					items={ledgerEntries}
					rowId={(entry: SmsLedgerEntry) => entry.id}
					caption="SMS credit ledger"
				>
					{#snippet row(entry: SmsLedgerEntry)}
						<td>{formatTime(entry.occurred_at)}</td>
						<td>{smsLedgerEntryKindLabel[entry.entry_kind]}</td>
						<td>{entry.reference}</td>
						<td>Purchased</td>
						<td class="align-end">
							{formatSmsMoney(entry.amount_minor, usage.balance.currency_code)}
						</td>
						<td class="align-end">
							{formatSmsMoney(entry.balance_after_minor, usage.balance.currency_code)}
						</td>
					{/snippet}
				</DataTable>
				<ListLoadMore
					hasNextPage={ledgerQuery.hasNextPage}
					isFetchingNextPage={ledgerQuery.isFetchingNextPage}
					onLoadMore={() => void ledgerQuery.fetchNextPage()}
					endLabel="That’s the whole ledger."
				/>
			{/if}
		</SectionBlock>
	{/if}
</PageContainer>

<Dialog open={requestOpen} title="Request a top-up" onClose={() => (requestOpen = false)}>
	<form class="sms-usage__form" onsubmit={submitRequest}>
		<p>
			Send payment offsite, then log the request here. Jafar confirms once the money arrives and
			credits your balance.
		</p>
		<Input
			id="sms-topup-amount"
			label="Amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={amountUsd}
			required
			invalid={Boolean(requestFieldErrors.requested_amount_minor)}
			errorMessage={requestFieldErrors.requested_amount_minor}
		/>
		<Input
			id="sms-topup-reference"
			label="Payment reference (optional)"
			bind:value={offsiteReference}
			invalid={Boolean(requestFieldErrors.offsite_reference)}
			errorMessage={requestFieldErrors.offsite_reference}
		/>
		<Textarea
			id="sms-topup-note"
			label="Note (optional)"
			bind:value={requestNote}
			rows={3}
			maxlength={2000}
			invalid={Boolean(requestFieldErrors.note)}
			errorMessage={requestFieldErrors.note}
		/>
		<div class="sms-usage__form-actions">
			<Button type="submit" loading={requestMutation.isPending}>Submit request</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (requestOpen = false)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.sms-usage {
		&__balance-strip {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
			gap: var(--space-base);
			margin-bottom: var(--space-large);
		}

		&__add-credit {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			margin-bottom: var(--space-large);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__add-credit-title {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__add-credit-copy {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			margin: calc(var(--space-small) * -1) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__health-grid {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
			gap: var(--space-base);
		}

		&__topups {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__topup {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__topup-amount {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__topup-meta {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__topup-actions {
			display: flex;
			align-items: center;
			gap: var(--space-base);
		}

		&__form {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__form-actions {
			display: flex;
			gap: var(--space-base);
		}
	}

	@media (max-width: 639px) {
		.sms-usage__topup {
			flex-direction: column;
			align-items: flex-start;
		}
	}
</style>
