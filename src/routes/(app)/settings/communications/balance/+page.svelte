<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import {
		createInfiniteQuery,
		createMutation,
		createQuery,
		useQueryClient
	} from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable from '$lib/components/data-display/DataTable.svelte';
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
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import refundIcon from '@tabler/icons/outline/rotate-2.svg?raw';
	import topupIcon from '@tabler/icons/outline/arrow-down-left.svg?raw';
	import adjustIcon from '@tabler/icons/outline/adjustments-horizontal.svg?raw';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import handCoinIcon from '@tabler/icons/outline/businessplan.svg?raw';
	import walletBigIcon from '@tabler/icons/outline/wallet.svg?raw';

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

	/** "$284.60 USD" split so the figure can be drawn large and the currency small. */
	function moneyParts(minor: number, currency: string) {
		const text = formatSmsMoney(minor, currency);
		const cut = text.lastIndexOf(' ');
		return { amount: text.slice(0, cut), currency: text.slice(cut + 1) };
	}

	const topupStatusIcon = {
		awaiting_confirmation: clockIcon,
		confirmed: checkIcon,
		rejected: closeIcon,
		cancelled: closeIcon
	};
	const ledgerKindIcon: Record<SmsLedgerEntry['entry_kind'], string> = {
		credit: topupIcon,
		charge: messageIcon,
		refund: refundIcon,
		adjustment: adjustIcon
	};

	const ledgerColumns = [
		{ key: 'occurred_at', label: 'Date', width: '200px' },
		{ key: 'entry_kind', label: 'Type', width: '200px' },
		{ key: 'reference', label: 'Reference' },
		{ key: 'bucket', label: 'Bucket', width: '110px' },
		{ key: 'amount', label: 'Amount', align: 'end' as const, width: '130px' },
		{ key: 'balance_after', label: 'Balance after', align: 'end' as const, width: '150px' }
	];
</script>

<svelte:head><title>Communication Balance · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
	<div class="balance record-detail--cards">
		<SettingsPageHeader
			title="Communication Balance"
			description="One balance for texts and extra email sending beyond your plan, this month's SMS charges, and lean delivery health."
			icon={walletBigIcon}
			tone="task"
			presentation="communication"
		/>

		{#if usageQuery.isPending}
			<LoadingSkeleton variant="card" rows={3} />
		{:else if usageQuery.isError}
			<ErrorState
				description="The Communication Balance could not be loaded."
				retry={() => usageQuery.refetch()}
			/>
		{:else}
			{@const usage = usageQuery.data}
			{@const available = moneyParts(
				usage.balance.spendable_balance_minor,
				usage.balance.currency_code
			)}
			{@const stats = [
				{
					label: 'Reserved',
					icon: receiptIcon,
					tone: 'informative',
					...moneyParts(usage.balance.reserved_balance_minor, usage.balance.currency_code),
					note: 'Pending charges for messages in flight'
				},
				{
					label: 'SMS usage this month',
					icon: activityIcon,
					tone: 'informative',
					...moneyParts(usage.usage_summary.retail_charge_minor, usage.balance.currency_code),
					note: `${usage.usage_summary.messages} message${usage.usage_summary.messages === 1 ? '' : 's'} · ${usage.usage_summary.segments} segment${usage.usage_summary.segments === 1 ? '' : 's'}`
				},
				{
					label: 'Email usage this month',
					icon: mailIcon,
					tone: 'informative',
					...moneyParts(usage.email_usage_summary.retail_charge_minor, usage.balance.currency_code),
					note: `${usage.email_usage_summary.recipients} recipient${usage.email_usage_summary.recipients === 1 ? '' : 's'} beyond your plan's allowance`
				}
			]}
			<div class="balance__hero">
				<article class="balance__available">
					<div class="balance__available-top">
						<IconTile icon={walletIcon} tone="feature" size={32} />
						<span>Available balance</span>
					</div>
					<strong class="balance__available-value">
						{available.amount}<small>{available.currency}</small>
					</strong>
					<p>Ready to spend on outbound texts and over-allowance email</p>
				</article>
				<div class="balance__stats">
					{#each stats as stat (stat.label)}
						<article class="balance__stat">
							<div class="balance__stat-top">
								<IconTile icon={stat.icon} tone="informative" size={40} />
								<span>{stat.label}</span>
							</div>
							<strong>{stat.amount} <small>{stat.currency}</small></strong>
							<p>{stat.note}</p>
						</article>
					{/each}
					<article class="balance__stat">
						<div class="balance__stat-top">
							<IconTile
								icon={historyIcon}
								tone={smsAvailabilityTone[usage.availability.state]}
								size={40}
							/>
							<span>Sending availability</span>
						</div>
						<strong
							class={`balance__availability balance__availability--${smsAvailabilityTone[usage.availability.state]}`}
						>
							<span class="balance__dot" aria-hidden="true"></span>
							{smsAvailabilityLabel[usage.availability.state]}
						</strong>
						<p>{usage.availability.reason ?? 'No pause is in effect'}</p>
					</article>
				</div>
			</div>

			<div class="balance__add-credit">
				<IconTile icon={handCoinIcon} tone="informative" size={40} />
				<div class="balance__add-credit-copy">
					<p class="balance__add-credit-title">Need more balance?</p>
					<p>
						Requesting a top-up creates no usable credit until Jafar confirms the payment arrived.
					</p>
				</div>
				<Button onclick={openRequest}>Request top-up</Button>
			</div>

			<SectionBlock
				tone="inactive"
				title="SMS messaging health"
				subtitle={`The last ${usage.messaging_health.period_days} days. For message-by-message detail, use Conversations once it supports SMS.`}
				icon={activityIcon}
				level={2}
			>
				<div class="balance__health-grid">
					{#each [{ label: 'Sent', value: String(usage.messaging_health.sent), note: 'Outbound attempts', tone: 'neutral' }, { label: 'Delivered', value: String(usage.messaging_health.delivered), note: 'Confirmed by carrier', tone: 'success' }, { label: 'Failed', value: String(usage.messaging_health.failed), note: 'Could not be delivered', tone: 'critical' }, { label: 'Received', value: String(usage.messaging_health.received), note: 'Coming with Conversations SMS', tone: 'neutral' }, { label: 'Opt-out rate', value: formatPercent(usage.messaging_health.opt_out_rate), note: 'Of messages sent', tone: 'neutral' }] as stat (stat.label)}
						<div class={`balance__health balance__health--${stat.tone}`}>
							<span class="balance__health-label">
								<span class="balance__dot" aria-hidden="true"></span>{stat.label}
							</span>
							<strong>{stat.value}</strong>
							<small>{stat.note}</small>
						</div>
					{/each}
				</div>
			</SectionBlock>

			<SectionBlock
				tone="inactive"
				title="Top-up requests"
				icon={receiptIcon}
				level={2}
				class={topupsQuery.data?.requests.length ? 'section-block--flush' : ''}
			>
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
					<ul class="balance__topups">
						{#each topupsQuery.data.requests as request (request.id)}
							<li class="balance__topup">
								<IconTile
									icon={topupStatusIcon[request.status]}
									tone={smsCreditTopupStatusTone[request.status]}
									size={40}
								/>
								<div class="balance__topup-copy">
									<p class="balance__topup-amount">
										{formatSmsMoney(request.requested_amount_minor, request.currency_code)} requested
									</p>
									<p class="balance__topup-meta">
										{formatTime(request.requested_at)}
										{#if request.offsite_reference}· Ref: {request.offsite_reference}{/if}
									</p>
									{#if request.status === 'confirmed' && request.settled_amount_minor !== null}
										<p class="balance__topup-meta">
											Confirmed: {formatSmsMoney(
												request.settled_amount_minor,
												request.currency_code
											)}
										</p>
									{/if}
									{#if request.status === 'rejected' && request.decision_reason}
										<p class="balance__topup-meta">Declined: {request.decision_reason}</p>
									{/if}
								</div>
								<div class="balance__topup-actions">
									<StatusBadge size="compact" status={smsCreditTopupStatusTone[request.status]}>
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

			<SectionBlock
				tone="inactive"
				title="Ledger"
				icon={historyIcon}
				level={2}
				class={ledgerEntries.length ? 'section-block--flush' : ''}
			>
				{#snippet actions()}
					<FilterChip
						id="balance-ledger-entry-kind"
						variant="toolbar"
						icon={filterIcon}
						label="Entry type"
						value={entryKindFilter}
						options={entryKindOptions}
						restValue=""
						onchange={(value) => (entryKindFilter = value)}
					/>
				{/snippet}

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
						variant="card"
						columns={ledgerColumns}
						items={ledgerEntries}
						rowId={(entry: SmsLedgerEntry) => entry.id}
						caption="Communication Balance ledger"
					>
						{#snippet row(entry: SmsLedgerEntry)}
							<td>{formatTime(entry.occurred_at)}</td>
							<td>
								<span class="balance__kind">
									<IconTile
										icon={ledgerKindIcon[entry.entry_kind]}
										tone={entry.entry_kind === 'credit' || entry.entry_kind === 'refund'
											? 'success'
											: 'inactive'}
										size={24}
									/>
									{smsLedgerEntryKindLabel[entry.entry_kind]}
								</span>
							</td>
							<td class="balance__reference">{entry.reference}</td>
							<td>Purchased</td>
							<td
								class={`align-end balance__amount${entry.amount_minor > 0 ? ' balance__amount--in' : ''}`}
							>
								{formatSmsMoney(entry.amount_minor, usage.balance.currency_code)}
							</td>
							<td class="align-end">
								{formatSmsMoney(entry.balance_after_minor, usage.balance.currency_code)}
							</td>
						{/snippet}
					</DataTable>
					<ListLoadMore
						count={ledgerEntries.length}
						recordName="entries"
						recordColor="inactive"
						variant="card"
						hasNextPage={ledgerQuery.hasNextPage}
						isFetchingNextPage={ledgerQuery.isFetchingNextPage}
						onLoadMore={() => void ledgerQuery.fetchNextPage()}
						endLabel="That’s the whole ledger."
					/>
				{/if}
			</SectionBlock>
		{/if}
	</div>
</PageContainer>

<Dialog open={requestOpen} title="Request a top-up" onClose={() => (requestOpen = false)}>
	<form class="balance__form" onsubmit={submitRequest}>
		<p>
			Send payment offsite, then log the request here. Jafar confirms once the money arrives and
			credits your balance.
		</p>
		<Input
			id="balance-topup-amount"
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
			id="balance-topup-reference"
			label="Payment reference (optional)"
			bind:value={offsiteReference}
			invalid={Boolean(requestFieldErrors.offsite_reference)}
			errorMessage={requestFieldErrors.offsite_reference}
		/>
		<Textarea
			id="balance-topup-note"
			label="Note (optional)"
			bind:value={requestNote}
			rows={3}
			maxlength={2000}
			invalid={Boolean(requestFieldErrors.note)}
			errorMessage={requestFieldErrors.note}
		/>
		<div class="balance__form-actions">
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
	.balance {
		display: flex;
		flex-direction: column;
		gap: 20px;

		/* One framed icon tile, used wherever the approved frame puts a soft coloured square. */
		&__hero {
			display: grid;
			grid-template-columns: minmax(0, 420fr) minmax(0, 712fr);
			gap: 16px;
		}
		&__available {
			position: relative;
			display: flex;
			flex-direction: column;
			justify-content: space-between;
			gap: var(--space-base);
			min-height: 268px;
			padding: 24px;
			overflow: hidden;
			border-radius: var(--radius-base);
			color: var(--color-base-white);
			background: var(--color-base-green--800);

			&::before,
			&::after {
				position: absolute;
				border: 1px solid color-mix(in srgb, var(--color-base-white) 12%, transparent);
				border-radius: 50%;
				content: '';
				pointer-events: none;
			}
			&::before {
				top: -120px;
				right: -140px;
				width: 360px;
				height: 360px;
			}
			&::after {
				top: -40px;
				right: -60px;
				width: 200px;
				height: 200px;
			}
			p {
				margin: 0;
				max-width: 30ch;
				color: color-mix(in srgb, var(--color-base-white) 82%, transparent);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
			}
		}
		&__available-top {
			display: flex;
			align-items: center;
			gap: 10px;
			color: color-mix(in srgb, var(--color-base-white) 86%, transparent);
			font-size: var(--typography--fontSize-overline);
			font-weight: 800;
			letter-spacing: 1.2px;
			text-transform: uppercase;
		}
		&__available-value {
			display: flex;
			align-items: baseline;
			gap: 8px;
			margin-top: auto;
			font-size: var(--typography--fontSize-extravagant);
			font-weight: 800;
			letter-spacing: -1.5px;
			line-height: 1;

			small {
				color: color-mix(in srgb, var(--color-base-white) 82%, transparent);
				font-size: var(--typography--fontSize-large);
				font-weight: 700;
				letter-spacing: 0;
			}
		}

		&__stats {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: 16px;
		}
		&__stat {
			display: flex;
			flex-direction: column;
			justify-content: center;
			gap: 8px;
			padding: 20px 20px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 800;
				letter-spacing: -0.5px;
				line-height: 1.1;

				small {
					color: var(--color-text--secondary);
					font-size: var(--typography--fontSize-small);
					font-weight: 700;
					letter-spacing: 0;
				}
			}
			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
			}
		}
		&__stat-top {
			display: flex;
			align-items: center;
			gap: 12px;
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__dot {
			flex: 0 0 auto;
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: currentcolor;
		}
		&__availability {
			display: flex;
			align-items: center;
			gap: 8px;

			&--success {
				color: var(--color-success--onSurface) !important;
			}
			&--warning {
				color: var(--color-warning--onSurface) !important;
			}
			&--critical {
				color: var(--color-critical--onSurface) !important;
			}
		}

		&__add-credit {
			display: flex;
			align-items: center;
			gap: 16px;
			padding: 14px 16px 14px 20px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}
		&__add-credit-copy {
			flex: 1;
			min-width: 0;

			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
			}
		}
		.balance__add-credit-title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}

		&__health-grid {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
			gap: 12px;
		}
		&__health {
			display: flex;
			flex-direction: column;
			gap: 6px;
			padding: 16px;
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-display);
				font-weight: 800;
				letter-spacing: -0.5px;
				line-height: 1.1;
			}
			small {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 500;
			}
			&--success strong {
				color: var(--color-success--onSurface);
			}
			&--critical strong {
				color: var(--color-critical--onSurface);
			}
		}
		&__health-label {
			display: flex;
			align-items: center;
			gap: 8px;
			color: var(--color-text);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;

			.balance__dot {
				width: 7px;
				height: 7px;
				color: var(--color-text--secondary);
			}
		}
		&__health--success &__health-label .balance__dot {
			color: var(--color-success);
		}
		&__health--critical &__health-label .balance__dot {
			color: var(--color-critical);
		}

		&__topups {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
			border-top: var(--border-base) solid var(--color-border);
		}
		&__topup {
			display: flex;
			align-items: center;
			gap: 16px;
			padding: 14px 24px;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}
		&__topup-copy {
			flex: 1;
			min-width: 0;
		}
		&__topup-amount {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}
		&__topup-meta {
			margin: 2px 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__topup-actions {
			display: flex;
			align-items: center;
			gap: 12px;
		}

		&__kind {
			display: inline-flex;
			white-space: nowrap;
			align-items: center;
			gap: 10px;
			font-weight: 600;
		}
		&__reference {
			max-width: 0;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
			color: var(--color-text--secondary);
			font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
			font-size: var(--typography--fontSize-small);
		}
		&__amount {
			white-space: nowrap;
			font-weight: 700;
		}
		td.balance__amount--in {
			color: var(--color-success--onSurface);
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

		/* App-look cards: the shared card rules (the `record-detail--cards` context) put each heading and hint
		   inside the card header; the page restores the framed icon tile beside the header lines. */
		&.record-detail--cards :global(.section-block > .section-block__title) {
			padding-left: 72px;
		}
		&.record-detail--cards :global(.section-block > .section-block__subtitle) {
			padding-left: 72px;
		}
		&.record-detail--cards :global(.section-block--flush > .section-block__actions) {
			padding-right: 24px;
		}
		&.record-detail--cards :global(.section-block--flush > .section-block__title) {
			padding-bottom: 20px;
		}
	}

	@media (max-width: 1079px) {
		.balance__hero {
			grid-template-columns: 1fr;
		}
	}
	@media (max-width: 639px) {
		.balance__stats {
			grid-template-columns: 1fr;
		}
		.balance__topup {
			flex-wrap: wrap;
		}
	}
</style>
