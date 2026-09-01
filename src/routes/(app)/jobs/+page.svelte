<script lang="ts">
	import { createInfiniteQuery, createQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import FilterBar from '$lib/components/data-display/FilterBar.svelte';
	import FilterField from '$lib/components/data-display/FilterField.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import StatusOverviewCard from '$lib/components/work/StatusOverviewCard.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import type { StatusOverviewRow } from '$lib/components/work/types';
	import {
		fetchJobOverview,
		fetchJobs,
		jobCountsKey,
		jobsListKey,
		type JobListItem,
		type JobListPage,
		type JobSortKey
	} from '$lib/jobs/api';
	import {
		JOB_FILTERABLE_STATUSES,
		JOB_OVERVIEW_STATUSES,
		JOB_STATUS_LABELS,
		JOB_STATUS_TONES,
		JOB_TYPES,
		JOB_TYPE_LABELS,
		type JobDerivedStatus,
		type JobType
	} from '$lib/jobs/statuses';
	import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-stats.svg?raw';
	import checksIcon from '@tabler/icons/outline/checks.svg?raw';
	import chartIcon from '@tabler/icons/outline/chart-bar.svg?raw';

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<JobDerivedStatus | ''>('');
	let jobType = $state<JobType | ''>('');
	let createdFrom = $state('');
	let createdTo = $state('');
	let filtersOpen = $state(false);
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

	function clearFilters() {
		status = '';
		jobType = '';
		createdFrom = '';
		createdTo = '';
	}

	// The five the office acts on. Counted, never clickable — filtering lives on the Status field in the
	// filter panel below, the same split Jobber uses.
	const overviewRows = $derived<StatusOverviewRow[]>(
		JOB_OVERVIEW_STATUSES.map((key) => ({
			label: JOB_STATUS_LABELS[key],
			count: countsQuery.data?.counts[key] ?? 0,
			tone: JOB_STATUS_TONES[key]
		}))
	);

	// Only the statuses the read model can currently produce. Visits and invoice reminders arrive later,
	// and a filter that can never match anything is worse than one that is honestly short.
	const statusOptions = [
		{ value: '', label: 'All statuses' },
		...JOB_FILTERABLE_STATUSES.map((value) => ({ value, label: JOB_STATUS_LABELS[value] }))
	];

	const typeOptions = [
		{ value: '', label: 'All types' },
		...JOB_TYPES.map((value) => ({ value, label: JOB_TYPE_LABELS[value] }))
	];

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

	function propertyAddress(property: JobListItem['property']) {
		if (!property) return 'No property';
		return (
			[property.address_line1, property.city, property.state_region].filter(Boolean).join(', ') ||
			'No property'
		);
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
		{ key: 'client', label: 'Client' },
		{ key: 'number', label: 'Job', sortable: true },
		{ key: 'property', label: 'Property' },
		{ key: 'type', label: 'Type' },
		{ key: 'created', label: 'Created', sortable: true },
		{ key: 'status', label: 'Status' },
		{ key: 'total', label: 'Total' }
	];
</script>

<svelte:head><title>Jobs · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<PageHeader title="Jobs" description="The work you have agreed to do.">
			{#snippet actions()}
				<Button variant="primary" href={resolve('/(app)/jobs/new')}>New Job</Button>
				<span class="jobs-header__action" title={moreActionsReason}>
					<Button variant="secondary" disabled>More Actions</Button>
					<span class="jobs-header__reason">{moreActionsReason}</span>
				</span>
			{/snippet}
		</PageHeader>

		<div class="jobs-stats">
			<StatusOverviewCard rows={overviewRows} loading={countsQuery.isPending} />
			<KpiCard
				label="Visits today"
				value="—"
				note="Once visits are being scheduled"
				icon={calendarIcon}
				variant="compact"
			/>
			<KpiCard
				label="Completed this month"
				value="—"
				note="Once visits are being completed"
				icon={checksIcon}
				variant="compact"
			/>
			<KpiCard
				label="Revenue this month"
				value="—"
				note="Once jobs are being invoiced and paid"
				icon={chartIcon}
				variant="compact"
			/>
		</div>

		<div class="jobs-toolbar">
			<div class="jobs-toolbar__search">
				<SearchInput id="jobs-search" bind:value={search} placeholder="Search jobs" />
			</div>
			<!-- eslint-disable svelte/no-at-html-tags -->
			<button
				type="button"
				class="jobs-toolbar__filters-toggle"
				class:jobs-toolbar__filters-toggle--active={hasActiveFilters}
				aria-pressed={filtersOpen}
				onclick={() => (filtersOpen = !filtersOpen)}
			>
				<span aria-hidden="true">{@html filterIcon}</span>
				Filters{hasActiveFilters ? ' •' : ''}
			</button>
			<!-- eslint-enable svelte/no-at-html-tags -->
		</div>

		{#if filtersOpen}
			<FilterBar onClear={hasActiveFilters ? clearFilters : undefined}>
				<FilterField id="jobs-status-filter" label="Status">
					<Select
						id="jobs-status-filter"
						value={status}
						onchange={(value) => (status = value as JobDerivedStatus | '')}
						options={statusOptions}
					/>
				</FilterField>
				<FilterField id="jobs-type-filter" label="Job type">
					<Select
						id="jobs-type-filter"
						value={jobType}
						onchange={(value) => (jobType = value as JobType | '')}
						options={typeOptions}
					/>
				</FilterField>
				<FilterField id="jobs-created-from" label="Created from">
					<CalendarPicker
						id="jobs-created-from"
						label="Created from"
						hideLabel
						value={calendarDateFromString(createdFrom)}
						maxValue={calendarDateFromString(createdTo)}
						onchange={(value) => (createdFrom = calendarDateToString(value))}
					/>
				</FilterField>
				<FilterField id="jobs-created-to" label="Created to">
					<CalendarPicker
						id="jobs-created-to"
						label="Created to"
						hideLabel
						value={calendarDateFromString(createdTo)}
						minValue={calendarDateFromString(createdFrom)}
						onchange={(value) => (createdTo = calendarDateToString(value))}
					/>
				</FilterField>
			</FilterBar>
		{/if}

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
				{columns}
				items={jobs}
				rowId={(job) => job.id}
				caption="Jobs"
				{sort}
				onSortChange={handleSortChange}
				onRowActivate={(job) => goto(resolve('/(app)/jobs/[id]', { id: job.id }))}
			>
				{#snippet row(job: JobListItem)}
					<th scope="row">
						<div class="jobs-table__client">
							<Avatar id={job.client?.id ?? job.id} name={clientName(job)} size="small" />
							<a class="jobs-table__client-link" href={resolve('/(app)/jobs/[id]', { id: job.id })}
								>{clientName(job)}</a
							>
						</div>
					</th>
					<td>
						<div class="jobs-table__number">#{job.job_number}</div>
						<div class="jobs-table__title">{job.title}</div>
					</td>
					<td>{propertyAddress(job.property)}</td>
					<td>{jobTypeLabel(job)}</td>
					<td>{dateFormat.format(new Date(job.created_at))}</td>
					<td>
						<StatusBadge status={JOB_STATUS_TONES[job.derived_status]}>
							{JOB_STATUS_LABELS[job.derived_status]}
						</StatusBadge>
					</td>
					<td>{formatTotal(job)}</td>
				{/snippet}
				{#snippet footer()}
					<ListLoadMore
						hasNextPage={jobsQuery.hasNextPage}
						isFetchingNextPage={jobsQuery.isFetchingNextPage}
						onLoadMore={() => jobsQuery.fetchNextPage()}
					/>
				{/snippet}
			</DataTable>
		{/if}
	</PageContainer>
</div>

<style lang="scss">
	.jobs-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	/* The row's real navigation link — carries keyboard focus, new-tab and cmd-click, while a plain click
	   anywhere on the row still opens the job through the table's onRowActivate. */
	.jobs-table__client-link {
		color: var(--color-heading);
		font-weight: 700;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
	}

	.jobs-table__number {
		color: var(--color-heading);
		font-weight: 700;
	}

	.jobs-table__title {
		color: var(--color-text--secondary);
	}

	.jobs-header__action {
		position: relative;
		display: inline-flex;
	}

	.jobs-header__reason {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	/* Overview card plus three metric tiles, the same top row as Requests and Quotes. The tiles read "—"
	   until visits and invoicing exist to fill them. */
	.jobs-stats {
		display: grid;
		gap: var(--space-base);
		grid-template-columns: repeat(4, minmax(0, 1fr));
		margin-top: var(--space-large);
	}

	.jobs-toolbar {
		display: flex;
		gap: var(--space-small);
		margin: var(--space-large) 0;

		&__search {
			flex: 1;
			min-width: 0;
		}
		&__filters-toggle {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-smaller);
			padding: 0 var(--space-base);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface);
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
			&:hover {
				background: var(--color-surface--hover);
			}
			&--active {
				border-color: var(--color-interactive);
				color: var(--color-interactive);
			}
		}
	}

	@media (max-width: 1023px) {
		.jobs-stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 639px) {
		.jobs-stats {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
