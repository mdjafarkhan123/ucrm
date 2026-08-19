<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate } from '@internationalized/date';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import ReopenOpportunityDialog from '$lib/components/pipeline/ReopenOpportunityDialog.svelte';
	import {
		outcomesListKey,
		fetchOutcomes,
		outcomeTilesKey,
		fetchOutcomeTiles,
		invalidatePipeline,
		type OutcomeRow
	} from '$lib/pipeline/api';
	import { formatMoney } from '$lib/pipeline/money';
	import {
		OUTCOME_TYPES,
		OUTCOME_TYPE_LABELS,
		OUTCOME_DATE_PRESETS,
		OUTCOME_DATE_LABELS,
		DEFAULT_OUTCOME_FILTERS,
		readOutcomeFilters,
		outcomeFilterParams,
		outcomeFiltersAreComplete,
		type OutcomeFilters,
		type OutcomeDatePreset,
		type OutcomeSort
	} from '$lib/pipeline/outcomes';
	import trophyIcon from '@tabler/icons/outline/trophy.svg?raw';

	const queryClient = useQueryClient();

	// URL-derived, the same way the board's own filters are: a refresh or the back button has to land on
	// exactly what was showing, with nothing held only in memory.
	const urlFilters = $derived(readOutcomeFilters(page.url.searchParams));
	const applied = $derived<OutcomeFilters>(
		outcomeFiltersAreComplete(urlFilters)
			? urlFilters
			: { ...urlFilters, date: 'all', from: undefined, to: undefined }
	);

	function setFilters(next: OutcomeFilters) {
		const params = outcomeFilterParams(next);
		const query = params.toString();
		void goto(`${page.url.pathname}${query ? `?${query}` : ''}`, {
			keepFocus: true,
			noScroll: true
		});
	}

	function handleSortChange(key: string) {
		const sort = key as OutcomeSort;
		setFilters({
			...urlFilters,
			sort,
			direction: urlFilters.sort === sort && urlFilters.direction === 'desc' ? 'asc' : 'desc'
		});
	}

	function changeDate(date: OutcomeDatePreset) {
		setFilters(
			date === 'custom'
				? { ...urlFilters, date }
				: { ...urlFilters, date, from: undefined, to: undefined }
		);
	}

	function toCalendarDate(day: string | undefined) {
		if (!day) return undefined;
		const [year, month, date] = day.split('-').map(Number);
		return new CalendarDate(year, month, date);
	}
	function toDay(value: CalendarDate | undefined) {
		if (!value) return undefined;
		return `${value.year}-${String(value.month).padStart(2, '0')}-${String(value.day).padStart(2, '0')}`;
	}

	const outcomesQuery = createInfiniteQuery(() => ({
		queryKey: outcomesListKey(applied),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchOutcomes(applied, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined
	}));

	// Shares the board's own tiles query -- only its currency/locale/timezone answer is needed here, so a
	// visit that already warmed the tiles cache from the board pays nothing for it.
	const tilesQuery = createQuery(() => ({
		queryKey: outcomeTilesKey,
		queryFn: fetchOutcomeTiles,
		staleTime: 30_000
	}));
	const formatting = $derived(tilesQuery.data ?? null);

	const refusal = $derived.by(() => {
		const error = outcomesQuery.error as (Error & { status?: number; reason?: string }) | null;
		if (!error || error.status !== 403) return null;
		return error.reason === 'feature_unavailable' ? 'feature' : 'permission';
	});

	const firstPage = $derived(outcomesQuery.data?.pages[0]);
	const canViewValue = $derived(firstPage?.can_view_value ?? false);
	const canViewClients = $derived(firstPage?.can_view_clients ?? false);
	const rows = $derived(outcomesQuery.data?.pages.flatMap((p) => p.outcomes) ?? []);
	const hasAnyFilter = $derived(
		applied.date !== 'all' || Boolean(applied.from) || Boolean(applied.to)
	);

	const sort = $derived<DataTableSort>({ key: urlFilters.sort, direction: urlFilters.direction });
	const columns = $derived.by((): DataTableColumn[] => {
		const base: DataTableColumn[] = [
			{ key: 'title', label: 'Title', sortable: true },
			{ key: 'client', label: 'Client', sortable: canViewClients },
			{ key: 'created', label: 'Created At', sortable: true },
			{ key: 'outcome_at', label: applied.type === 'won' ? 'Won At' : 'Lost At', sortable: true }
		];
		if (canViewValue) base.push({ key: 'total', label: 'Total', align: 'end', sortable: true });
		return base;
	});

	function clientName(row: OutcomeRow) {
		return row.client?.display_name ?? 'Client removed';
	}
	// Written the organization's own way, not the browser's -- the same rule every other Pipeline money
	// and date value follows.
	function formatDate(value: string) {
		return new Intl.DateTimeFormat(formatting?.locale, {
			day: 'numeric',
			month: 'short',
			year: 'numeric'
		}).format(new Date(value));
	}
	function money(value: number | null | undefined) {
		if (value === null || value === undefined || !formatting) return '—';
		return formatMoney(value, formatting) ?? '—';
	}

	// A Reopen dialog operates on one row at a time; the id says which, null means closed.
	let reopeningId = $state<string | null>(null);
	function onReopened() {
		reopeningId = null;
		invalidatePipeline(queryClient);
	}
</script>

<svelte:head><title>Sales Outcomes · Pipeline</title></svelte:head>

<PageContainer variant="fill">
	<PageHeader title="Sales Outcomes" description="Every Opportunity that has closed, won or lost.">
		{#snippet actions()}
			<Button variant="secondary" href={resolve('/(app)/pipeline')}>Back to Pipeline</Button>
		{/snippet}
	</PageHeader>

	{#if refusal === 'feature'}
		<EmptyState
			title="Pipeline is not part of your plan"
			description="Ask your account owner to add it to see Sales Outcomes."
		/>
	{:else if refusal === 'permission'}
		<EmptyState
			title="You do not have access to Sales Outcomes"
			description="Ask an owner or admin to give you pipeline access."
		/>
	{:else if outcomesQuery.isError}
		<ErrorState
			title="Sales Outcomes could not be loaded"
			description="Something went wrong on our side. Try again."
			retry={() => outcomesQuery.refetch()}
		/>
	{:else}
		<div class="outcomes-toolbar">
			<span class="outcomes-toolbar__field">
				<label class="outcomes-toolbar__label" for="outcomes-type">Type</label>
				<Select
					id="outcomes-type"
					value={applied.type}
					options={OUTCOME_TYPES.map((type) => ({ value: type, label: OUTCOME_TYPE_LABELS[type] }))}
					onchange={(value) => setFilters({ ...urlFilters, type: value as 'won' | 'lost' })}
				/>
			</span>
			<span class="outcomes-toolbar__field">
				<label class="outcomes-toolbar__label" for="outcomes-date">Date</label>
				<Select
					id="outcomes-date"
					value={applied.date}
					options={OUTCOME_DATE_PRESETS.map((preset) => ({
						value: preset,
						label: OUTCOME_DATE_LABELS[preset]
					}))}
					onchange={(value) => changeDate(value as OutcomeDatePreset)}
				/>
			</span>
			{#if applied.date === 'custom'}
				<CalendarPicker
					id="outcomes-date-from"
					label="From"
					value={toCalendarDate(applied.from)}
					maxValue={toCalendarDate(applied.to)}
					onchange={(value) => setFilters({ ...urlFilters, from: toDay(value) })}
				/>
				<CalendarPicker
					id="outcomes-date-to"
					label="To"
					value={toCalendarDate(applied.to)}
					minValue={toCalendarDate(applied.from)}
					onchange={(value) => setFilters({ ...urlFilters, to: toDay(value) })}
				/>
			{/if}
			{#if hasAnyFilter}
				<Button
					variant="tertiary"
					size="small"
					onclick={() =>
						setFilters({
							...urlFilters,
							date: DEFAULT_OUTCOME_FILTERS.date,
							from: undefined,
							to: undefined
						})}
				>
					Clear filters
				</Button>
			{/if}
		</div>

		{#if outcomesQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading Sales Outcomes" rows={5} />
		{:else if rows.length === 0}
			<EmptyState
				icon={trophyIcon}
				title={hasAnyFilter
					? 'No matching results'
					: applied.type === 'won'
						? 'Nothing won yet'
						: 'Nothing lost yet'}
				description={hasAnyFilter
					? 'Try a different date range.'
					: applied.type === 'won'
						? 'Automatic Won arrives once Quotes and Jobs are part of the pipeline.'
						: 'A Request appears here once it is marked as lost.'}
			/>
		{:else}
			{#snippet reopenAction(item: OutcomeRow)}
				<Button variant="secondary" size="small" onclick={() => (reopeningId = item.id)}>
					Reopen
				</Button>
			{/snippet}
			<DataTable
				{columns}
				items={rows}
				rowId={(row) => row.id}
				caption="Sales Outcomes"
				{sort}
				onSortChange={handleSortChange}
				rowActions={applied.type === 'lost' ? reopenAction : undefined}
			>
				{#snippet row(item: OutcomeRow)}
					<th scope="row">{item.title}</th>
					<td>{clientName(item)}</td>
					<td>{formatDate(item.created_at)}</td>
					<td>{formatDate(item.outcome_at)}</td>
					{#if canViewValue}
						<td class="align-end">{money(item.estimated_value)}</td>
					{/if}
				{/snippet}
				{#snippet footer()}
					<ListLoadMore
						hasNextPage={outcomesQuery.hasNextPage}
						isFetchingNextPage={outcomesQuery.isFetchingNextPage}
						onLoadMore={() => outcomesQuery.fetchNextPage()}
					/>
				{/snippet}
			</DataTable>
		{/if}
	{/if}
</PageContainer>

{#if reopeningId}
	<ReopenOpportunityDialog
		open={Boolean(reopeningId)}
		opportunityId={reopeningId}
		onSaved={onReopened}
		onClose={() => (reopeningId = null)}
	/>
{/if}

<style lang="scss">
	.outcomes-toolbar {
		display: flex;
		flex-wrap: wrap;
		align-items: end;
		gap: var(--space-base);
		margin: var(--space-large) 0;

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}
	}
	.outcomes-toolbar__label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
</style>
