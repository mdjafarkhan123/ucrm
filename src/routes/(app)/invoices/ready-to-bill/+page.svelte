<script lang="ts">
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		fetchReadyToBill,
		readyToBillKey,
		type ReadyToBillJob,
		type ReadyToBillPage
	} from '$lib/invoices/api';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

	// The ready-to-bill queue: every job that owes an invoice today, across every client, oldest first. It has
	// one order and one filter on purpose — a billing queue is only ever asked "what has been waiting longest",
	// and the Invoices list next door is where bills are sliced and sorted.
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

	// Where the bill actually gets made, which is a screen that already exists in every case. A whole-job bill
	// goes straight to the composer, which opens the same "select work to invoice" picker the job's own
	// Create invoice menu item opens. Visits and periods are chosen on the job page, where the card that lists
	// them is the picker — so that is where the queue sends you rather than building a second one here.
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
					<td>{waitingFor(job)}</td>
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
				{#snippet footer()}
					<ListLoadMore
						hasNextPage={queueQuery.hasNextPage}
						isFetchingNextPage={queueQuery.isFetchingNextPage}
						onLoadMore={() => queueQuery.fetchNextPage()}
					/>
				{/snippet}
			</DataTable>
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
</style>
