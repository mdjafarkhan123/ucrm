<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
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
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import StatusOverviewCard from '$lib/components/work/StatusOverviewCard.svelte';
	import type { StatusOverviewRow } from '$lib/components/work/types';
	import {
		bulkArchiveQuotes,
		fetchQuoteOverview,
		fetchQuotes,
		quoteCountsKey,
		quotesListKey,
		type QuoteListItem,
		type QuoteListPage,
		type QuoteSortKey
	} from '$lib/quotes/api';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		QUOTE_OVERVIEW_STATUSES,
		QUOTE_STATUS_LABELS,
		QUOTE_STATUS_TONES,
		STORED_QUOTE_STATUSES,
		type StoredQuoteStatus
	} from '$lib/quotes/statuses';
	import fileInvoiceIcon from '@tabler/icons/outline/file-invoice.svg?raw';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import chartIcon from '@tabler/icons/outline/chart-bar.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import trendingIcon from '@tabler/icons/outline/trending-up.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<StoredQuoteStatus | ''>('');
	let createdFrom = $state('');
	let createdTo = $state('');
	let filtersOpen = $state(false);
	let selectedIds = $state<Set<string>>(new Set());
	let sortKey = $state<QuoteSortKey>('created');
	let sortDir = $state<'asc' | 'desc'>('desc');
	let bulkArchiving = $state(false);

	// Click a header to sort by it ascending; click it again for descending. Clicking a different
	// sortable header switches to that column, starting ascending again — one sort column at a time.
	function handleSortChange(key: string) {
		if (key === sortKey) {
			sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		} else {
			sortKey = key as QuoteSortKey;
			sortDir = 'asc';
		}
	}

	// Nothing behind this yet. It says why rather than sitting there dead, the way the Requests page does.
	const moreActionsReason = 'Templates and importing arrive later.';

	async function bulkArchive() {
		if (bulkArchiving || selectedIds.size === 0) return;
		bulkArchiving = true;
		try {
			const result = await bulkArchiveQuotes([...selectedIds]);
			selectedIds = new Set();
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: ['quotes', 'list'] }),
				queryClient.invalidateQueries({ queryKey: quoteCountsKey })
			]);
			if (result.skipped === 0) {
				toast.success(
					result.archived === 1 ? '1 quote archived.' : `${result.archived} quotes archived.`
				);
			} else {
				toast.success(
					`${result.archived} archived, ${result.skipped} skipped (already archived or converted).`
				);
			}
		} catch {
			toast.error('Those quotes could not be archived. Try again.');
		} finally {
			bulkArchiving = false;
		}
	}

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
		created_from: dayStart(createdFrom),
		created_to: dayEnd(createdTo),
		sort: sortKey,
		dir: sortDir
	});
	const sort = $derived<DataTableSort>({ key: sortKey, direction: sortDir });

	// Keyset pagination, so there is no page to jump to — each page hands back the cursor for the next
	// one and Load more asks for it. That is what keeps the query fast however many quotes an office has.
	const quotesQuery = createInfiniteQuery(() => ({
		queryKey: quotesListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) => fetchQuotes(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: QuoteListPage) => lastPage.next_cursor ?? undefined
	}));

	const countsQuery = createQuery(() => ({
		queryKey: quoteCountsKey,
		queryFn: fetchQuoteOverview
	}));

	const quotes = $derived(quotesQuery.data?.pages.flatMap((page) => page.quotes) ?? []);
	const locale = $derived(quotesQuery.data?.pages[0]?.locale ?? 'en-US');
	const hasActiveFilters = $derived(status !== '' || createdFrom !== '' || createdTo !== '');

	function clearFilters() {
		status = '';
		createdFrom = '';
		createdTo = '';
	}

	// The number the composer just saved, carried across in the URL so the list can say so out loud.
	const savedNumber = $derived(page.url.searchParams.get('saved') ?? '');

	// The four the office acts on. Counted, never clickable — filtering lives on the Status field in the
	// filter panel below, the same split Jobber uses.
	const overviewRows = $derived<StatusOverviewRow[]>(
		QUOTE_OVERVIEW_STATUSES.map((key) => ({
			label: QUOTE_STATUS_LABELS[key],
			count: countsQuery.data?.counts[key] ?? 0,
			tone: QUOTE_STATUS_TONES[key]
		}))
	);

	const statusOptions = [
		{ value: '', label: 'All statuses' },
		...STORED_QUOTE_STATUSES.map((value) => ({ value, label: QUOTE_STATUS_LABELS[value] }))
	];

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});

	// One formatter per currency rather than one per figure — a page of quotes writes a total on every row.
	const moneyFormatters = new Map<string, Intl.NumberFormat>();
	function formatTotal(quote: QuoteListItem) {
		if (quote.total_minor === null) return '—';
		const key = `${locale}:${quote.currency_code}`;
		let formatter = moneyFormatters.get(key);
		if (!formatter) {
			formatter = new Intl.NumberFormat(locale, {
				style: 'currency',
				currency: quote.currency_code
			});
			moneyFormatters.set(key, formatter);
		}
		return formatter.format(quote.total_minor / 100);
	}

	function propertyAddress(property: QuoteListItem['property']) {
		if (!property) return 'No property';
		return [property.address_line1, property.city, property.state_region]
			.filter(Boolean)
			.join(', ');
	}
	function clientName(quote: QuoteListItem) {
		return quote.client?.display_name ?? 'Client removed';
	}
	function quoteTitle(quote: QuoteListItem) {
		return quote.title ?? 'Untitled quote';
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'number', label: 'Quote', sortable: true },
		{ key: 'property', label: 'Property' },
		{ key: 'created', label: 'Created', sortable: true },
		{ key: 'status', label: 'Status' },
		{ key: 'total', label: 'Total' }
	];
</script>

<svelte:head><title>Quotes · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		{#if savedNumber}
			<p class="quotes__saved" role="status">Quote #{savedNumber} was saved.</p>
		{/if}
		<PageHeader title="Quotes" description="Every price you have put in front of a client.">
			{#snippet actions()}
				<Button variant="primary" href={resolve('/(app)/quotes/new')}>New Quote</Button>
				<span class="quotes-header__action" title={moreActionsReason}>
					<Button variant="secondary" disabled>More Actions</Button>
					<span class="quotes-header__reason">{moreActionsReason}</span>
				</span>
			{/snippet}
		</PageHeader>

		<div class="quotes-stats">
			<StatusOverviewCard rows={overviewRows} loading={countsQuery.isPending} />
			<KpiCard
				label="Conversion rate"
				value="—"
				note="Once quotes are being sent and approved"
				icon={chartIcon}
				variant="compact"
			/>
			<KpiCard
				label="Sent"
				value="—"
				note="Once there are 30 days of sent quotes"
				icon={sendIcon}
				variant="compact"
			/>
			<KpiCard
				label="Converted"
				value="—"
				note="Once approved quotes turn into jobs"
				icon={trendingIcon}
				variant="compact"
			/>
		</div>

		<div class="quotes-toolbar">
			<div class="quotes-toolbar__search">
				<SearchInput id="quotes-search" bind:value={search} placeholder="Search quotes" />
			</div>
			<!-- eslint-disable svelte/no-at-html-tags -->
			<button
				type="button"
				class="quotes-toolbar__filters-toggle"
				class:quotes-toolbar__filters-toggle--active={hasActiveFilters}
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
				<FilterField id="quotes-status-filter" label="Status">
					<Select
						id="quotes-status-filter"
						value={status}
						onchange={(value) => (status = value as StoredQuoteStatus | '')}
						options={statusOptions}
					/>
				</FilterField>
				<FilterField id="quotes-created-from" label="Created from">
					<CalendarPicker
						id="quotes-created-from"
						label="Created from"
						hideLabel
						value={calendarDateFromString(createdFrom)}
						maxValue={calendarDateFromString(createdTo)}
						onchange={(value) => (createdFrom = calendarDateToString(value))}
					/>
				</FilterField>
				<FilterField id="quotes-created-to" label="Created to">
					<CalendarPicker
						id="quotes-created-to"
						label="Created to"
						hideLabel
						value={calendarDateFromString(createdTo)}
						minValue={calendarDateFromString(createdFrom)}
						onchange={(value) => (createdTo = calendarDateToString(value))}
					/>
				</FilterField>
			</FilterBar>
		{/if}

		{#if selectedIds.size > 0}
			<div class="quotes-bulk-bar">
				<span>{selectedIds.size} selected</span>
				<Button
					variant="secondary"
					size="small"
					loading={bulkArchiving}
					onclick={() => void bulkArchive()}
				>
					Archive
				</Button>
			</div>
		{/if}

		{#if quotesQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading quotes" rows={5} />
		{:else if quotesQuery.isError}
			<ErrorState description="Quotes could not be loaded. Refresh and try again." />
		{:else if quotes.length === 0}
			<EmptyState
				icon={fileInvoiceIcon}
				title={hasActiveFilters || debouncedSearch ? 'No matching quotes' : 'No quotes yet'}
				description={hasActiveFilters || debouncedSearch
					? 'Try a different search term or clear your filters.'
					: 'Prices you send out will show up here.'}
			/>
		{:else}
			<DataTable
				{columns}
				items={quotes}
				rowId={(quote) => quote.id}
				caption="Quotes"
				selectable
				bind:selectedIds
				rowLabel={(quote) => `Select quote #${quote.quote_number}`}
				onRowActivate={(quote) => void goto(resolve('/(app)/quotes/[id]', { id: quote.id }))}
				{sort}
				onSortChange={handleSortChange}
			>
				{#snippet row(quote: QuoteListItem)}
					<th scope="row">
						<div class="quotes-table__client">
							<Avatar id={quote.client?.id ?? quote.id} name={clientName(quote)} size="small" />
							<span>{clientName(quote)}</span>
						</div>
					</th>
					<td>
						<div class="quotes-table__number">
							<a href={resolve('/(app)/quotes/[id]', { id: quote.id })}>#{quote.quote_number}</a>
						</div>
						<div class="quotes-table__title">{quoteTitle(quote)}</div>
					</td>
					<td>{propertyAddress(quote.property)}</td>
					<td>{dateFormat.format(new Date(quote.created_at))}</td>
					<td>
						<StatusBadge status={QUOTE_STATUS_TONES[quote.status]}>
							{QUOTE_STATUS_LABELS[quote.status]}
						</StatusBadge>
					</td>
					<td>{formatTotal(quote)}</td>
				{/snippet}
				{#snippet footer()}
					<ListLoadMore
						hasNextPage={quotesQuery.hasNextPage}
						isFetchingNextPage={quotesQuery.isFetchingNextPage}
						onLoadMore={() => quotesQuery.fetchNextPage()}
					/>
				{/snippet}
			</DataTable>
		{/if}
	</PageContainer>
</div>

<style lang="scss">
	.quotes__saved {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-bottom: var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: var(--typography--fontSize-small);
	}

	.quotes-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.quotes-table__number {
		color: var(--color-heading);
		font-weight: 700;

		a {
			color: inherit;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}
	}

	.quotes-table__title {
		color: var(--color-text--secondary);
	}

	.quotes-header__action {
		position: relative;
		display: inline-flex;
	}

	.quotes-header__reason {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	.quotes-stats {
		display: grid;
		gap: var(--space-base);
		grid-template-columns: repeat(4, minmax(0, 1fr));
		margin-top: var(--space-large);
	}

	.quotes-toolbar {
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

	.quotes-bulk-bar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		margin-bottom: var(--space-base);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		font-weight: 600;
	}

	@media (max-width: 1023px) {
		.quotes-stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 639px) {
		.quotes-stats {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
