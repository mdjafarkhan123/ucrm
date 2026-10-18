<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DateRangeChip from '$lib/components/data-display/DateRangeChip.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import RecordListCard from '$lib/components/data-display/RecordListCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import AttentionCard, {
		type AttentionFact,
		type AttentionTile
	} from '$lib/components/work/AttentionCard.svelte';
	import MoneyFeatureCard from '$lib/components/work/MoneyFeatureCard.svelte';
	import {
		fetchJobOverview,
		fetchJobs,
		jobCountsKey,
		jobsListKey,
		type JobListItem,
		type JobListPage,
		type JobSortKey,
		fetchJob,
		jobDetailKey
	} from '$lib/jobs/api';
	import {
		JOB_FILTERABLE_STATUSES,
		JOB_STATUS_LABELS,
		JOB_STATUS_TONES,
		JOB_TYPES,
		JOB_TYPE_LABELS,
		type JobDerivedStatus,
		type JobType
	} from '$lib/jobs/statuses';
	import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import dashedCircleIcon from '@tabler/icons/outline/circle-dashed.svg?raw';
	import repeatIcon from '@tabler/icons/outline/repeat.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import alarmIcon from '@tabler/icons/outline/alarm.svg?raw';
	import calendarOffIcon from '@tabler/icons/outline/calendar-x.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash-banknote.svg?raw';

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<JobDerivedStatus | ''>('');
	let jobType = $state<JobType | ''>('');
	let createdFrom = $state('');
	let createdTo = $state('');
	let sortKey = $state<JobSortKey>('created');
	let sortDir = $state<'asc' | 'desc'>('desc');

	// Click a header to sort by it ascending; click it again for descending. Clicking a different
	// sortable header switches to that column, starting ascending again — one sort column at a time.
	function handleSortChange(key: string) {
		if (key === sortKey) {
			sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		} else {
			sortKey = key as JobSortKey;
			sortDir = 'asc';
		}
	}

	// Nothing behind these yet. They say why rather than sitting there dead, the way Quotes does.
	const moreActionsReason = 'Bulk actions and exporting arrive later.';

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	// A date picked in the filter means the whole of that day where the person is, so From starts at
	// midnight and To runs to the last moment — otherwise "to today" would hide everything made today.
	function dayStart(day: string) {
		if (!day) return '';
		const [year, month, date] = day.split('-').map(Number);
		return new Date(year, month - 1, date, 0, 0, 0, 0).toISOString();
	}
	function dayEnd(day: string) {
		if (!day) return '';
		const [year, month, date] = day.split('-').map(Number);
		return new Date(year, month - 1, date, 23, 59, 59, 999).toISOString();
	}

	const filters = $derived({
		search: debouncedSearch,
		statuses: status ? [status] : [],
		types: jobType ? [jobType] : [],
		created_from: dayStart(createdFrom),
		created_to: dayEnd(createdTo),
		sort: sortKey,
		dir: sortDir
	});
	const sort = $derived<DataTableSort>({ key: sortKey, direction: sortDir });

	// Keyset pagination, so there is no page to jump to — each page hands back the cursor for the next
	// one and Load more asks for it. That is what keeps the query fast however many jobs an office has.
	const queryClient = useQueryClient();
	const jobsQuery = createInfiniteQuery(() => ({
		queryKey: jobsListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) => fetchJobs(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: JobListPage) => lastPage.next_cursor ?? undefined
	}));

	const countsQuery = createQuery(() => ({
		queryKey: jobCountsKey,
		queryFn: fetchJobOverview
	}));

	const jobs = $derived(jobsQuery.data?.pages.flatMap((page) => page.jobs) ?? []);
	const locale = $derived(jobsQuery.data?.pages[0]?.locale ?? 'en-US');
	const hasActiveFilters = $derived(
		status !== '' || jobType !== '' || createdFrom !== '' || createdTo !== ''
	);

	// The five the office acts on, most urgent first, each with a line saying what it means. Picking one
	// sets the Status filter below to it; picking it again, or choosing another status there, clears it.
	const attentionOrder = [
		{ key: 'late', hint: 'A visit date passed, not done', icon: alarmIcon },
		{ key: 'unscheduled', hint: 'Visits not booked yet', icon: calendarOffIcon },
		{ key: 'action_required', hint: 'No upcoming visit booked', icon: alertIcon },
		{ key: 'requires_invoicing', hint: 'Work done, not billed yet', icon: receiptIcon },
		{ key: 'ending_soon', hint: 'Recurring, ends within 30 days', icon: hourglassIcon }
	] as const;

	const attentionTiles = $derived<AttentionTile[]>(
		attentionOrder.map(({ key, hint, icon }) => ({
			key,
			icon,
			label: JOB_STATUS_LABELS[key],
			hint,
			count: countsQuery.data?.counts[key] ?? 0,
			tone: JOB_STATUS_TONES[key]
		}))
	);
	const selectedTile = $derived(attentionOrder.some(({ key }) => key === status) ? status : '');

	function overviewNumber(value: number | undefined) {
		return value === undefined ? '—' : String(value);
	}
	function plural(count: number | undefined, one: string, many: string) {
		return count === 1 ? one : many;
	}

	const attentionFacts = $derived<AttentionFact[]>([
		{
			icon: calendarIcon,
			tone: 'time',
			value: overviewNumber(countsQuery.data?.visits_today),
			label: `${plural(countsQuery.data?.visits_today, 'visit', 'visits')} scheduled today`
		},
		{
			icon: checkIcon,
			tone: 'success',
			value: overviewNumber(countsQuery.data?.completed_past_30_days),
			label: `${plural(countsQuery.data?.completed_past_30_days, 'visit', 'visits')} completed in the past 30 days`
		}
	]);

	// Two answers on one card, both from the Invoices figures: money already collected this calendar month, and
	// money still left to collect on open invoices. A role that cannot see invoice money gets dashes and a
	// reason rather than made-up zeros.
	const collectedMinor = $derived(countsQuery.data?.collected_this_month_minor ?? null);
	const outstandingMinor = $derived(countsQuery.data?.outstanding_minor ?? null);
	function formatOverviewMoney(amountMinor: number | null) {
		if (amountMinor === null) return '—';
		return new Intl.NumberFormat(countsQuery.data?.locale ?? 'en-US', {
			style: 'currency',
			currency: countsQuery.data?.currency_code ?? 'USD',
			maximumFractionDigits: 0
		}).format(amountMinor / 100);
	}
	const collectedValue = $derived(formatOverviewMoney(collectedMinor));
	const outstandingValue = $derived(formatOverviewMoney(outstandingMinor));
	const monthToDate = new Intl.DateTimeFormat(undefined, { month: 'short' });
	const collectedNote = $derived.by(() => {
		if (countsQuery.isPending) return 'Loading…';
		if (collectedMinor === null) return 'Needs invoice price access';
		const today = new Date();
		return `From paid invoices, ${monthToDate.format(today)} 1–${today.getDate()}`;
	});

	const statusOptions = [
		{ value: '', label: 'All' },
		...JOB_FILTERABLE_STATUSES.map((value) => ({ value, label: JOB_STATUS_LABELS[value] }))
	];

	const typeOptions = [
		{ value: '', label: 'All' },
		...JOB_TYPES.map((value) => ({ value, label: JOB_TYPE_LABELS[value] }))
	];

	const sortSummary = $derived.by(() => {
		if (sortKey === 'number')
			return sortDir === 'asc' ? 'Lowest job number first' : 'Highest job number first';
		return sortDir === 'asc' ? 'Oldest first' : 'Newest first';
	});

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});

	// One formatter per currency rather than one per figure — a page of jobs writes a total on every row.
	// A plain object, not a Map: nothing reads it reactively, it is only a cache the formatter fills.
	const moneyFormatters: Record<string, Intl.NumberFormat> = {};
	function formatTotal(job: JobListItem) {
		if (job.total_minor === null) return '—';
		const key = `${locale}:${job.currency_code}`;
		let formatter = moneyFormatters[key];
		if (!formatter) {
			formatter = new Intl.NumberFormat(locale, { style: 'currency', currency: job.currency_code });
			moneyFormatters[key] = formatter;
		}
		return formatter.format(job.total_minor / 100);
	}

	// The street on one line, the town and region under it. A job with no property says so on the first line.
	function propertyStreet(property: JobListItem['property']) {
		return property?.address_line1 || 'No property';
	}
	function propertyArea(property: JobListItem['property']) {
		if (!property) return '';
		return [property.city, property.state_region].filter(Boolean).join(', ');
	}
	function clientName(job: JobListItem) {
		return job.client?.display_name ?? 'Client removed';
	}
	function jobTypeLabel(job: JobListItem) {
		if (job.job_type === 'recurring') return job.is_as_needed ? 'As needed' : 'Recurring';
		return 'One-off';
	}

	// No Schedule column yet: a job's dates live on its visits, and visits arrive with the scheduling
	// part. Created is what the list is actually ordered by, so it is what the column shows.
	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client', width: '220px' },
		{ key: 'number', label: 'Job', sortable: true },
		{ key: 'property', label: 'Property', width: '200px' },
		{ key: 'created', label: 'Created', sortable: true, width: '120px' },
		{ key: 'status', label: 'Status', width: '150px' },
		{ key: 'total', label: 'Total', align: 'end', width: '100px' },
		{ key: 'open', label: 'Open job', hideLabel: true, width: '56px' }
	];

	function prefetchJob(item: { id: string }) {
		void queryClient.prefetchQuery({
			queryKey: jobDetailKey(item.id),
			queryFn: () => fetchJob(item.id),
			staleTime: 15_000
		});
	}
</script>

<svelte:head><title>Jobs · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="open">
		<PageHeader
			class="jobs-page__header"
			icon={hammerIcon}
			tone="job"
			title="Jobs"
			description="The work you have agreed to do, from first visit to final invoice."
		>
			{#snippet actions()}
				<DropdownMenu triggerText="More" unavailableReason={moreActionsReason} />
				<Button
					variant="primary"
					href={resolve('/(app)/jobs/new')}
				>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span class="jobs-header__icon" aria-hidden="true">{@html plusIcon}</span>
					New job
				</Button>
			{/snippet}
		</PageHeader>

		<div class="jobs-overview">
			<AttentionCard
				description="Jobs waiting on you. Pick one to see only those jobs."
				tiles={attentionTiles}
				selectedKey={selectedTile}
				onSelect={(key) => (status = key as JobDerivedStatus | '')}
				facts={attentionFacts}
				loading={countsQuery.isPending}
			/>
			<MoneyFeatureCard
				icon={cashIcon}
				eyebrow="Collected this month"
				value={collectedValue}
				note={collectedNote}
				detailLabel="Left to collect on open invoices"
				detailValue={outstandingValue}
				loading={countsQuery.isPending}
			/>
		</div>

		<RecordListCard
			title="All jobs"
			subtitle={sortSummary}
			padBody={jobsQuery.isPending || jobsQuery.isError || jobs.length === 0}
		>
			{#snippet toolbar()}
				<div class="jobs-card__search">
					<SearchInput
						id="jobs-search"
						bind:value={search}
						placeholder="Search jobs"
						size="compact"
					/>
				</div>
				<FilterChip
					id="jobs-status-filter"
					variant="toolbar"
					icon={dashedCircleIcon}
					label="Status"
					value={status}
					options={statusOptions}
					restValue=""
					onchange={(value) => (status = value as JobDerivedStatus | '')}
				/>
				<FilterChip
					id="jobs-type-filter"
					variant="toolbar"
					icon={repeatIcon}
					label="Type"
					value={jobType}
					options={typeOptions}
					restValue=""
					onchange={(value) => (jobType = value as JobType | '')}
				/>
				<DateRangeChip
					id="jobs-created"
					label="Created"
					from={createdFrom}
					to={createdTo}
					onchange={(range) => {
						createdFrom = range.from;
						createdTo = range.to;
					}}
				/>
			{/snippet}

			{#if jobsQuery.isPending}
				<LoadingSkeleton variant="table" label="Loading jobs" rows={5} />
			{:else if jobsQuery.isError}
				<ErrorState description="Jobs could not be loaded. Refresh and try again." />
			{:else if jobs.length === 0}
				<EmptyState
					icon={toolsIcon}
					title={hasActiveFilters || debouncedSearch ? 'No matching jobs' : 'No jobs yet'}
					description={hasActiveFilters || debouncedSearch
						? 'Try a different search term or clear your filters.'
						: 'Work you have agreed to do will show up here.'}
				/>
			{:else}
				<DataTable
					variant="card"
					{columns}
					items={jobs}
					rowId={(job) => job.id}
					caption="Jobs"
					{sort}
					onSortChange={handleSortChange}
					onRowHover={prefetchJob}
					onRowActivate={(job) => goto(resolve('/(app)/jobs/[id=uuid]', { id: job.id }))}
				>
					{#snippet row(job: JobListItem)}
						<th scope="row">
							<div class="jobs-table__client">
								<Avatar id={job.client?.id ?? job.id} name={clientName(job)} size="base" />
								<a
									class="jobs-table__client-link"
									href={resolve('/(app)/jobs/[id=uuid]', { id: job.id })}>{clientName(job)}</a
								>
							</div>
						</th>
						<td>
							<div class="jobs-table__title">{job.title}</div>
							<div class="jobs-table__meta">#{job.job_number} · {jobTypeLabel(job)}</div>
						</td>
						<td>
							<div class="jobs-table__street">{propertyStreet(job.property)}</div>
							{#if propertyArea(job.property)}
								<div class="jobs-table__meta">{propertyArea(job.property)}</div>
							{/if}
						</td>
						<td class="jobs-table__date">{dateFormat.format(new Date(job.created_at))}</td>
						<td>
							<StatusBadge size="compact" status={JOB_STATUS_TONES[job.derived_status]}>
								{JOB_STATUS_LABELS[job.derived_status]}
							</StatusBadge>
						</td>
						<td class="jobs-table__total">{formatTotal(job)}</td>
						<td class="jobs-table__open">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span aria-hidden="true">{@html chevronRightIcon}</span>
						</td>
					{/snippet}
					{#snippet footer()}
						<ListLoadMore
							variant="card"
							label="Load more jobs"
							hasNextPage={jobsQuery.hasNextPage}
							isFetchingNextPage={jobsQuery.isFetchingNextPage}
							onLoadMore={() => jobsQuery.fetchNextPage()}
							searchNarrowed={jobsQuery.data?.pages.at(-1)?.search_narrowed ?? false}
							narrowedLabel="Many jobs match — type more to see the rest."
						/>
					{/snippet}
				</DataTable>
			{/if}
		</RecordListCard>
	</PageContainer>
</div>

<style lang="scss">
	/* The page header sits straight on the app background; the cards under it share one 24px rhythm. */
	:global(.jobs-page__header) {
		margin-bottom: var(--space-large);
	}

	.jobs-header__icon {
		display: inline-flex;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	/* Needs attention takes the room it needs; the money card keeps a steady width beside it. */
	.jobs-overview {
		display: grid;
		gap: var(--space-large);
		grid-template-columns: minmax(0, 1fr) 312px;
		margin-bottom: var(--space-large);
	}

	.jobs-card__search {
		width: 260px;
		max-width: 100%;
	}

	.jobs-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	/* The row's real navigation link — carries keyboard focus, new-tab and cmd-click, while a plain click
	   anywhere on the row still opens the job through the table's onRowActivate. */
	.jobs-table__client-link {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}

	.jobs-table__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
	}
	.jobs-table__street {
		display: -webkit-box;
		overflow: hidden;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		color: var(--color-text);
		font-size: 13px;
		font-weight: 500;
	}
	.jobs-table__meta {
		margin-top: 3px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.jobs-table__date {
		color: var(--color-text);
		font-size: 13px;
		font-weight: 500;
		white-space: nowrap;
	}
	.jobs-table__total {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-variant-numeric: tabular-nums;
		font-weight: 600;
		text-align: end;
		white-space: nowrap;
	}
	.jobs-table__open {
		color: var(--color-icon--secondary);

		span {
			display: inline-flex;
			vertical-align: middle;
		}
		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	@media (max-width: 1199px) {
		.jobs-overview {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
