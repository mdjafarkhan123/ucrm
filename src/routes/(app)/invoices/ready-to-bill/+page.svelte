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
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ReadyToBillVisitsPanel from '$lib/components/invoices/ReadyToBillVisitsPanel.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		createInvoicesInBatch,
		fetchReadyToBill,
		readyToBillKey,
		type ReadyToBillJob,
		type ReadyToBillPage
	} from '$lib/invoices/api';
	import { fetchJob, jobDetailKey } from '$lib/jobs/api';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// The ready-to-bill queue: every job that owes an invoice today, across every client, oldest first. It has
	// one order and one filter on purpose — a billing queue is only ever asked "what has been waiting longest",
	// and the Invoices list next door is where bills are sliced and sorted.
	//
	// Part 8a added the other half: ticking rows and billing them together. One invoice per client (a client's
	// several jobs merge onto one bill), split when their properties carry different tax rates. The grouping
	// happens in the database, so this screen never promises a number of invoices it cannot know.
	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Jafar's cap: one page of the queue at a time.
	const BATCH_MAX = 25;

	let search = $state('');
	let debouncedSearch = $state('');

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const queueQuery = createInfiniteQuery(() => ({
		queryKey: readyToBillKey(debouncedSearch),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchReadyToBill(debouncedSearch, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: ReadyToBillPage) => lastPage.next_cursor ?? undefined
	}));

	const jobs = $derived(queueQuery.data?.pages.flatMap((page) => page.jobs) ?? []);
	const locale = $derived(queueQuery.data?.pages[0]?.locale ?? 'en-US');

	// --- Selection ------------------------------------------------------------------------------------------
	//
	// Three pieces of state, each reassigned rather than mutated so the table and the bar follow it: which
	// jobs are ticked, which rows are open, and which unfinished visits the contractor asked to complete.
	let selectedIds = $state(new Set<string>());
	let expandedIds = $state(new Set<string>());
	let tickedVisitIds = $state(new Set<string>());
	// Which job each ticked visit belongs to, so unticking a job takes its visits with it.
	const visitOwner = new Map<string, string>();
	let saving = $state(false);
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	// A ticked visit only means anything while its job is selected, so the two can never disagree.
	$effect(() => {
		const chosen = selectedIds;
		let changed = false;
		const next = new Set(tickedVisitIds);
		for (const visitId of next) {
			const owner = visitOwner.get(visitId);
			if (!owner || !chosen.has(owner)) {
				next.delete(visitId);
				changed = true;
			}
		}
		if (changed) tickedVisitIds = next;
	});

	function toggleExpanded(jobId: string) {
		const next = new Set(expandedIds);
		if (next.has(jobId)) next.delete(jobId);
		else next.add(jobId);
		expandedIds = next;
	}

	// Opening a row shows that job's visits, and the answer is fetched on hover so the click usually lands on
	// data that is already there. Nothing about the row loads until somebody reaches for it.
	function prefetchJob(jobId: string) {
		void queryClient.prefetchQuery({
			queryKey: jobDetailKey(jobId),
			queryFn: () => fetchJob(jobId)
		});
	}

	function toggleVisit(jobId: string, visitId: string, checked: boolean) {
		const next = new Set(tickedVisitIds);
		if (checked) {
			next.add(visitId);
			visitOwner.set(visitId, jobId);
			// Ticking a visit is a statement about billing this job, so the job comes with it rather than
			// leaving a tick that quietly does nothing.
			if (!selectedIds.has(jobId)) {
				const chosen = new Set(selectedIds);
				chosen.add(jobId);
				selectedIds = chosen;
			}
		} else {
			next.delete(visitId);
		}
		tickedVisitIds = next;
	}

	function clearSelection() {
		selectedIds = new Set();
		tickedVisitIds = new Set();
	}

	const selectedCount = $derived(selectedIds.size);
	const tickedCount = $derived(tickedVisitIds.size);
	const overCap = $derived(selectedCount > BATCH_MAX);

	// A short, stable fingerprint of what is being saved, so the command can tell a replay of this batch from
	// a fresh one carrying the same key. FNV-1a over the ordered selection, the same shape the single-invoice
	// form uses.
	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	async function billSelected() {
		if (saving || selectedCount === 0 || overCap) return;

		const core = {
			job_ids: [...selectedIds].sort(),
			complete_visit_ids: [...tickedVisitIds].sort()
		};
		const hash = fingerprint(core);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			const result = await createInvoicesInBatch({
				...core,
				idempotency_key: idempotencyKey,
				request_hash: hash
			});

			// The bills, the jobs whose reminders they answered, and the queue itself all just changed.
			await queryClient.invalidateQueries({ queryKey: ['invoices'] });
			await queryClient.invalidateQueries({ queryKey: ['jobs'] });

			const invoiceWord = result.invoice_count === 1 ? 'draft invoice' : 'draft invoices';
			const jobWord = result.job_count === 1 ? 'job' : 'jobs';
			toast.success(
				`Created ${result.invoice_count} ${invoiceWord}`,
				result.visits_completed > 0
					? `From ${result.job_count} ${jobWord}, and ${result.visits_completed} visit${result.visits_completed === 1 ? '' : 's'} marked complete.`
					: `From ${result.job_count} ${jobWord}.`
			);
			clearSelection();
			// A fresh batch after a successful one is a new intent, not a replay of this one.
			lastHash = '';
		} catch (error) {
			toast.error(
				'Those invoices could not be created',
				error instanceof Error ? error.message : 'Try again.'
			);
		} finally {
			saving = false;
		}
	}

	// --- Formatting -----------------------------------------------------------------------------------------

	const dateFormat = $derived(
		new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric' })
	);
	// A `date` column arrives as `YYYY-MM-DD`; `new Date` on that reads it as UTC midnight and shifts the day
	// back one in negative-offset timezones. Appending `T00:00` parses it as local midnight.
	function formatDay(value: string) {
		return dateFormat.format(new Date(`${value}T00:00`));
	}

	// One formatter per currency rather than one per figure.
	const moneyFormatters: Record<string, Intl.NumberFormat> = {};
	function formatMoney(amountMinor: number, currency: string) {
		const key = `${locale}:${currency}`;
		let formatter = moneyFormatters[key];
		if (!formatter) {
			formatter = new Intl.NumberFormat(locale, { style: 'currency', currency });
			moneyFormatters[key] = formatter;
		}
		return formatter.format(amountMinor / 100);
	}

	function clientName(job: ReadyToBillJob) {
		return job.client?.company_name || job.client?.display_name || 'Client removed';
	}

	// What is actually waiting on this job, said the way the job's own billing card says it.
	function waitingFor(job: ReadyToBillJob) {
		if (job.unit_kind === 'visits') {
			return job.unit_count === 1 ? '1 completed visit' : `${job.unit_count} completed visits`;
		}
		if (job.unit_kind === 'periods') {
			return job.unit_count === 1 ? '1 billing period' : `${job.unit_count} billing periods`;
		}
		return 'The whole job';
	}

	// Where the bill actually gets made when only one row is wanted, which is a screen that already exists in
	// every case. A whole-job bill goes straight to the composer, which opens the same "select work to
	// invoice" picker the job's own Create invoice menu item opens. Visits and periods are chosen on the job
	// page, where the card that lists them is the picker.
	function billHref(job: ReadyToBillJob) {
		if (job.unit_kind === 'job' && job.client) {
			return `${resolve('/(app)/invoices/new')}?client=${job.client.id}&job=${job.job_id}`;
		}
		return resolve('/(app)/jobs/[id]', { id: job.job_id });
	}

	// How long a job has been waiting, which is the queue's whole reason for existing. Same-day work reads
	// "Today" rather than "0 days", because a queue that says nothing is due today is confusing.
	function waitingSince(dueOn: string) {
		const due = new Date(`${dueOn}T00:00`);
		const now = new Date();
		const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
		const days = Math.round((today.getTime() - due.getTime()) / 86400000);
		if (days <= 0) return 'Today';
		if (days === 1) return '1 day';
		return `${days} days`;
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'job', label: 'Job' },
		{ key: 'waiting-for', label: 'Ready to bill' },
		{ key: 'since', label: 'Waiting' },
		{ key: 'due', label: 'Since' },
		{ key: 'amount', label: 'Uninvoiced' },
		{ key: 'action', label: '' }
	];
</script>

<svelte:head><title>Ready to bill · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<PageHeader
			title="Ready to bill"
			description="Finished work that still needs an invoice, oldest first."
		>
			{#snippet actions()}
				<Button href={resolve('/(app)/invoices')}>All invoices</Button>
			{/snippet}
		</PageHeader>

		<div class="ready-toolbar">
			<SearchInput
				id="ready-to-bill-search"
				bind:value={search}
				placeholder="Search by client or job"
			/>
		</div>

		{#if queueQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading work ready to bill" rows={5} />
		{:else if queueQuery.isError}
			<ErrorState description="This list could not be loaded. Refresh and try again." />
		{:else if jobs.length === 0}
			<EmptyState
				icon={receiptIcon}
				title={debouncedSearch ? 'No matching work' : 'Nothing waiting to be billed'}
				description={debouncedSearch
					? 'Try a different client or job name.'
					: 'When a job is ready to invoice, it shows up here.'}
			/>
		{:else}
			<DataTable
				{columns}
				items={jobs}
				rowId={(job) => job.job_id}
				caption="Work ready to bill"
				selectable
				bind:selectedIds
				rowLabel={(job) => `Select job #${job.job_number} for ${clientName(job)}`}
				isExpanded={(job) => expandedIds.has(job.job_id)}
				onRowActivate={(job) => goto(resolve('/(app)/jobs/[id]', { id: job.job_id }))}
			>
				{#snippet row(job: ReadyToBillJob)}
					<th scope="row">
						<div class="ready-table__client">
							<Avatar id={job.client?.id ?? job.job_id} name={clientName(job)} size="small" />
							<span class="ready-table__client-name">{clientName(job)}</span>
						</div>
					</th>
					<td>
						<a
							class="ready-table__job-link"
							href={resolve('/(app)/jobs/[id]', { id: job.job_id })}
							onclick={(event) => event.stopPropagation()}
						>
							#{job.job_number}
							{job.title}
						</a>
						{#if job.property.address_line1 || job.property.label}
							<div class="ready-table__property">
								{job.property.label || job.property.address_line1}{job.property.city
									? `, ${job.property.city}`
									: ''}
							</div>
						{/if}
					</td>
					<td>
						{#if job.unit_kind === 'visits'}
							<!-- eslint-disable svelte/no-at-html-tags -->
							<button
								type="button"
								class="ready-table__expander"
								aria-expanded={expandedIds.has(job.job_id)}
								onclick={() => toggleExpanded(job.job_id)}
								onmouseenter={() => prefetchJob(job.job_id)}
								onfocus={() => prefetchJob(job.job_id)}
							>
								<span class="ready-table__expander-icon" aria-hidden="true"
									>{@html expandedIds.has(job.job_id) ? chevronDownIcon : chevronRightIcon}</span
								>
								{waitingFor(job)}
							</button>
							<!-- eslint-enable svelte/no-at-html-tags -->
						{:else}
							{waitingFor(job)}
						{/if}
					</td>
					<td>{waitingSince(job.oldest_due_on)}</td>
					<td>{formatDay(job.oldest_due_on)}</td>
					<td class="ready-table__amount">
						{formatMoney(job.uninvoiced_minor, job.currency_code)}
					</td>
					<td class="ready-table__action">
						<Button
							variant="primary"
							size="small"
							href={billHref(job)}
							onclick={(event: MouseEvent) => event.stopPropagation()}
						>
							Bill
						</Button>
					</td>
				{/snippet}
				{#snippet rowDetail(job: ReadyToBillJob)}
					<ReadyToBillVisitsPanel
						jobId={job.job_id}
						{locale}
						ticked={tickedVisitIds}
						onToggle={(visitId, checked) => toggleVisit(job.job_id, visitId, checked)}
					/>
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
				<div class="ready-bar__summary">
					<span class="ready-bar__count">
						{selectedCount}
						{selectedCount === 1 ? 'job' : 'jobs'} selected
					</span>
					{#if overCap}
						<span class="ready-bar__warning">
							You can bill {BATCH_MAX} jobs at a time. Clear a few and bill the rest next.
						</span>
					{:else if tickedCount > 0}
						<span class="ready-bar__note">
							Saving will also mark {tickedCount}
							{tickedCount === 1 ? 'visit' : 'visits'} complete.
						</span>
					{:else}
						<span class="ready-bar__note">One invoice per client, split by tax rate.</span>
					{/if}
				</div>
				<div class="ready-bar__actions">
					<Button variant="secondary" onclick={clearSelection} disabled={saving}>Clear</Button>
					<Button variant="primary" onclick={billSelected} disabled={saving || overCap}>
						{saving ? 'Creating…' : 'Create invoices'}
					</Button>
				</div>
			</StickyActionBar>
		{/if}
	</PageContainer>
</div>

<style lang="scss">
	.ready-toolbar {
		margin: var(--space-large) 0;
	}

	.ready-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.ready-table__client-name {
		color: var(--color-heading);
		font-weight: 700;
	}

	.ready-table__job-link {
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

	.ready-table__property {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.ready-table__expander {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		margin: calc(var(--space-slim) * -1);
		padding: var(--space-slim);
		border: 0;
		border-radius: var(--radius-small);
		background: none;
		color: inherit;
		font: inherit;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.ready-table__expander-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	.ready-table__amount {
		color: var(--color-heading);
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.ready-table__action {
		text-align: right;
		white-space: nowrap;
	}

	.ready-bar__summary {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
	}

	.ready-bar__count {
		color: var(--color-heading);
		font-weight: 700;
	}

	.ready-bar__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.ready-bar__warning {
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.ready-bar__actions {
		display: flex;
		gap: var(--space-small);
	}
</style>
