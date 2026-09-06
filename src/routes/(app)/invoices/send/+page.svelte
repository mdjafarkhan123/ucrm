<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import StickyActionBar from '$lib/components/layout/StickyActionBar.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		deliverInvoicesInBatch,
		fetchDeliverableInvoices,
		deliverableInvoicesKey,
		type BatchDeliverItem,
		type BatchDeliverOutcome,
		type DeliverableInvoice,
		type DeliverableInvoicesPage
	} from '$lib/invoices/api';
	import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

	// The "Send invoices" picker: pick several unsent (or unpaid) bills and email them in one action, the same
	// batch-send Jobber's invoice list offers. It reuses the ready-to-bill screen's shape — a selectable table
	// plus a sticky bar that counts what is chosen — because a billing office does the same thing here: scan a
	// list, tick a handful, act on them together.
	//
	// Two rules the picker exists to keep. A bill only ever re-sends on purpose, so nothing is ticked by
	// default and a bill that already went out is marked so. And a bill with no email address behind it cannot
	// be sent, so that is flagged before submit and blocks the send until it is unticked.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	// The send window is 20 emails per 5 minutes per person; the picker caps a batch at that same number, so a
	// full batch has a chance of clearing rather than stopping half way. It is a ceiling, not a promise all 20
	// queue — the server still meters each one.
	const SEND_MAX = 20;

	let search = $state('');
	let debouncedSearch = $state('');

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	// The list is not searched server-side — the deliverable read is a small, newest-first queue — so search
	// filters the loaded rows in the browser. Kept debounced to match the other invoice screens' feel.
	const queueQuery = createInfiniteQuery(() => ({
		queryKey: deliverableInvoicesKey,
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchDeliverableInvoices(pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: DeliverableInvoicesPage) => lastPage.next_cursor ?? undefined
	}));

	const allInvoices = $derived(queueQuery.data?.pages.flatMap((page) => page.invoices) ?? []);
	const locale = $derived(queueQuery.data?.pages[0]?.locale ?? 'en-US');

	function clientName(invoice: DeliverableInvoice) {
		return invoice.client?.company_name || invoice.client?.display_name || 'Client removed';
	}

	const invoices = $derived.by(() => {
		const term = debouncedSearch.trim().toLowerCase();
		if (!term) return allInvoices;
		return allInvoices.filter(
			(invoice) =>
				clientName(invoice).toLowerCase().includes(term) ||
				invoice.subject.toLowerCase().includes(term) ||
				`#${invoice.invoice_number}`.includes(term)
		);
	});

	// The loaded rows keyed by id, so both the action bar (which selected bills lack an email) and the send
	// itself (each bill's revision) can answer from the id alone.
	const byId = $derived(new Map(allInvoices.map((invoice) => [invoice.id, invoice])));

	// --- Selection ------------------------------------------------------------------------------------------
	let selectedIds = $state(new Set<string>());

	// A stable send key per invoice, kept for the life of this batch. A retry re-sends the not-queued bills
	// under the SAME key so a bill that actually went out (but answered uncertainly) returns its first result
	// instead of a second email; a fresh batch, after Send more, wipes these so it is a genuinely new send.
	let deliverKeys = new Map<string, string>();
	function keyFor(id: string) {
		let key = deliverKeys.get(id);
		if (!key) {
			key = crypto.randomUUID();
			deliverKeys.set(id, key);
		}
		return key;
	}

	let sending = $state(false);
	// The per-invoice outcomes of the last send. Null means the picker is still choosing; a value flips the
	// screen to its result view.
	let results = $state<BatchDeliverOutcome[] | null>(null);

	const selectedCount = $derived(selectedIds.size);
	const overCap = $derived(selectedCount > SEND_MAX);
	const missingEmailCount = $derived(
		[...selectedIds].filter((id) => byId.get(id)?.has_email === false).length
	);
	const canSend = $derived(!sending && selectedCount > 0 && !overCap && missingEmailCount === 0);

	function clearSelection() {
		selectedIds = new Set();
	}

	function itemsFor(ids: string[]): BatchDeliverItem[] {
		return ids.map((id) => ({
			invoice_id: id,
			expected_revision: byId.get(id)?.revision ?? 0,
			idempotency_key: keyFor(id)
		}));
	}

	async function send() {
		if (!canSend) return;
		sending = true;
		try {
			const result = await deliverInvoicesInBatch(itemsFor([...selectedIds]));
			results = result.results;
			// The bills just changed — drafts became awaiting-payment, and every one carries a fresh
			// last-sent stamp the list reads.
			await queryClient.invalidateQueries({ queryKey: ['invoices'] });

			const { queued, rate_limited, failed, skipped } = result.summary;
			if (queued > 0 && rate_limited === 0 && failed === 0 && skipped === 0) {
				toast.success(
					`Sent ${queued} ${queued === 1 ? 'invoice' : 'invoices'}`,
					'Each one is on its way to the client.'
				);
			} else if (queued > 0) {
				toast.success(
					`Queued ${queued} of ${result.summary.total}`,
					'Some could not be sent — the rest are below.'
				);
			} else {
				toast.error('Nothing was sent', 'See what happened to each one below.');
			}
		} catch (error) {
			toast.error(
				'Those invoices could not be sent',
				error instanceof Error ? error.message : 'Try again.'
			);
		} finally {
			sending = false;
		}
	}

	// What the last send left unsent — everything that is not queued. These are the only bills a retry touches.
	const retryable = $derived(results ? results.filter((r) => r.outcome !== 'queued') : []);

	async function retry() {
		if (sending || retryable.length === 0) return;
		sending = true;
		try {
			const result = await deliverInvoicesInBatch(itemsFor(retryable.map((r) => r.invoice_id)));
			// Keep the bills that already queued exactly as they were — a retry never re-sends them — and
			// overlay the fresh outcome onto the ones we tried again.
			const merged = new Map((results ?? []).map((r) => [r.invoice_id, r]));
			for (const outcome of result.results) merged.set(outcome.invoice_id, outcome);
			results = [...merged.values()];
			await queryClient.invalidateQueries({ queryKey: ['invoices'] });

			if (result.summary.queued > 0) {
				toast.success(
					`Sent ${result.summary.queued} more`,
					result.results.some((r) => r.outcome !== 'queued')
						? 'Some still need another try.'
						: 'That clears the batch.'
				);
			}
		} catch (error) {
			toast.error(
				'Those invoices could not be sent',
				error instanceof Error ? error.message : 'Try again.'
			);
		} finally {
			sending = false;
		}
	}

	// Back to a clean picker for a new batch: fresh keys so this is a new send, not a replay of the last one.
	function sendMore() {
		results = null;
		deliverKeys = new Map();
		clearSelection();
	}

	// --- Formatting -----------------------------------------------------------------------------------------
	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	// A `date` column arrives as `YYYY-MM-DD`; `new Date` reads that as UTC midnight and shifts the day back
	// one in negative-offset timezones. Appending `T00:00` parses it as local midnight.
	function formatDay(value: string) {
		return dateFormat.format(new Date(`${value}T00:00`));
	}
	function formatSentAt(value: string) {
		return dateFormat.format(new Date(value));
	}

	// The limiter hands back seconds; a person reads minutes. Round up so "retry in a moment" never undershoots
	// the real wait.
	function retryDelayLabel(seconds: number) {
		if (seconds <= 60) return 'try again in about a minute';
		const minutes = Math.ceil(seconds / 60);
		return `try again in about ${minutes} minute${minutes === 1 ? '' : 's'}`;
	}

	function invoiceLabel(id: string) {
		const invoice = byId.get(id);
		if (!invoice) return 'Invoice';
		return `#${invoice.invoice_number} · ${clientName(invoice)}`;
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'invoice', label: 'Invoice' },
		{ key: 'status', label: 'Status' },
		{ key: 'due', label: 'Due' },
		{ key: 'sent', label: 'Last sent' }
	];
</script>

<svelte:head><title>Send invoices · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<PageHeader title="Send invoices" description="Email several bills to your customers at once.">
			{#snippet actions()}
				<Button href={resolve('/(app)/invoices')}>All invoices</Button>
			{/snippet}
		</PageHeader>

		{#if results !== null}
			<!-- Result view: what became of each bill we tried to send. -->
			<section class="send-results" aria-label="Send results">
				<ul class="send-results__list">
					{#each results as outcome (outcome.invoice_id)}
						<li class="send-results__item">
							<span class="send-results__name">{invoiceLabel(outcome.invoice_id)}</span>
							{#if outcome.outcome === 'queued'}
								<StatusBadge status="success">Sent</StatusBadge>
							{:else if outcome.outcome === 'rate_limited'}
								<span class="send-results__outcome">
									<StatusBadge status="warning">Rate limited</StatusBadge>
									<span class="send-results__reason">
										{retryDelayLabel(outcome.retry_after_seconds)}
									</span>
								</span>
							{:else if outcome.outcome === 'failed'}
								<span class="send-results__outcome">
									<StatusBadge status="critical">Failed</StatusBadge>
									<span class="send-results__reason">{outcome.reason}</span>
								</span>
							{:else}
								<span class="send-results__outcome">
									<StatusBadge status="inactive">Not sent</StatusBadge>
									<span class="send-results__reason">Stopped after the send limit.</span>
								</span>
							{/if}
						</li>
					{/each}
				</ul>
			</section>

			<StickyActionBar>
				<div class="send-bar__summary">
					{#if retryable.length === 0}
						<span class="send-bar__count">All sent</span>
						<span class="send-bar__note">Every invoice in this batch is on its way.</span>
					{:else}
						<span class="send-bar__count">
							{retryable.length} still to send
						</span>
						<span class="send-bar__note"
							>Retry sends only these — the ones already sent are left alone.</span
						>
					{/if}
				</div>
				<div class="send-bar__actions">
					<Button variant="secondary" onclick={sendMore} disabled={sending}>Send more</Button>
					{#if retryable.length > 0}
						<Button variant="primary" onclick={retry} disabled={sending}>
							{sending ? 'Sending…' : `Retry ${retryable.length}`}
						</Button>
					{:else}
						<Button variant="primary" href={resolve('/(app)/invoices')}>Done</Button>
					{/if}
				</div>
			</StickyActionBar>
		{:else if queueQuery.isPending}
			<div class="send-toolbar">
				<SearchInput
					id="send-search"
					bind:value={search}
					placeholder="Search by client or invoice"
				/>
			</div>
			<LoadingSkeleton variant="table" label="Loading invoices you can send" rows={5} />
		{:else if queueQuery.isError}
			<ErrorState description="This list could not be loaded. Refresh and try again." />
		{:else if allInvoices.length === 0}
			<EmptyState
				icon={receiptIcon}
				title="Nothing to send"
				description="Draft and unpaid invoices you can email will show up here."
			/>
		{:else}
			<div class="send-toolbar">
				<SearchInput
					id="send-search"
					bind:value={search}
					placeholder="Search by client or invoice"
				/>
			</div>

			{#if invoices.length === 0}
				<EmptyState
					icon={receiptIcon}
					title="No matching invoices"
					description="Try a different client or invoice number."
				/>
			{:else}
				<DataTable
					{columns}
					items={invoices}
					rowId={(invoice) => invoice.id}
					caption="Invoices you can send"
					selectable
					bind:selectedIds
					rowLabel={(invoice) =>
						`Select invoice #${invoice.invoice_number} for ${clientName(invoice)}`}
					onRowActivate={(invoice) => goto(resolve('/(app)/invoices/[id]', { id: invoice.id }))}
				>
					{#snippet row(invoice: DeliverableInvoice)}
						<th scope="row">
							<div class="send-table__client">
								<Avatar
									id={invoice.client?.id ?? invoice.id}
									name={clientName(invoice)}
									size="small"
								/>
								<span class="send-table__client-name">{clientName(invoice)}</span>
							</div>
						</th>
						<td>
							<a
								class="send-table__invoice-link"
								href={resolve('/(app)/invoices/[id]', { id: invoice.id })}
								onclick={(event) => event.stopPropagation()}
							>
								#{invoice.invoice_number}
							</a>
							<div class="send-table__subject">{invoice.subject}</div>
						</td>
						<td>
							<StatusBadge status={INVOICE_STATUS_TONES[invoice.derived_status]}>
								{INVOICE_STATUS_LABELS[invoice.derived_status]}
							</StatusBadge>
						</td>
						<td>{formatDay(invoice.due_date)}</td>
						<td>
							{#if !invoice.has_email}
								<span class="send-table__flag">No email on file</span>
							{:else if invoice.last_sent_at}
								<span class="send-table__sent">Sent {formatSentAt(invoice.last_sent_at)}</span>
							{:else}
								<span class="send-table__never">Not sent yet</span>
							{/if}
						</td>
					{/snippet}
					{#snippet footer()}
						<ListLoadMore
							hasNextPage={queueQuery.hasNextPage}
							isFetchingNextPage={queueQuery.isFetchingNextPage}
							onLoadMore={() => queueQuery.fetchNextPage()}
						/>
					{/snippet}
				</DataTable>
			{/if}

			{#if selectedCount > 0}
				<StickyActionBar>
					<div class="send-bar__summary">
						<span class="send-bar__count">
							{selectedCount}
							{selectedCount === 1 ? 'invoice' : 'invoices'} selected
						</span>
						{#if overCap}
							<span class="send-bar__warning">
								You can send {SEND_MAX} at a time. Clear a few and send the rest next.
							</span>
						{:else if missingEmailCount > 0}
							<span class="send-bar__warning">
								{missingEmailCount}
								{missingEmailCount === 1 ? 'invoice has' : 'invoices have'} no email on file. Untick
								{missingEmailCount === 1 ? 'it' : 'them'} to send the rest.
							</span>
						{:else}
							<span class="send-bar__note">Each client is emailed their invoice.</span>
						{/if}
					</div>
					<div class="send-bar__actions">
						<Button variant="secondary" onclick={clearSelection} disabled={sending}>Clear</Button>
						<Button variant="primary" onclick={send} disabled={!canSend}>
							{sending ? 'Sending…' : 'Send invoices'}
						</Button>
					</div>
				</StickyActionBar>
			{/if}
		{/if}
	</PageContainer>
</div>

<style lang="scss">
	.send-toolbar {
		margin: var(--space-large) 0;
	}

	.send-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.send-table__client-name {
		color: var(--color-heading);
		font-weight: 700;
	}

	.send-table__invoice-link {
		color: var(--color-heading);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			color: var(--color-interactive);
			text-decoration: underline;
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
			border-radius: var(--radius-small);
		}
	}

	.send-table__subject {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.send-table__sent,
	.send-table__never {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.send-table__flag {
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.send-results {
		margin: var(--space-large) 0;
	}

	.send-results__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.send-results__item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.send-results__name {
		color: var(--color-heading);
		font-weight: 600;
	}

	.send-results__outcome {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.send-results__reason {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.send-bar__summary {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.send-bar__count {
		color: var(--color-heading);
		font-weight: 700;
	}

	.send-bar__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.send-bar__warning {
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.send-bar__actions {
		display: flex;
		gap: var(--space-small);
	}
</style>
