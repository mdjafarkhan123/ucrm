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
		fetchInvoiceOverview,
		fetchInvoices,
		fetchReadyToBillCount,
		invoiceCountsKey,
		invoicesListKey,
		readyToBillCountKey,
		type InvoiceListItem,
		type InvoiceListPage,
		type InvoiceSortKey
	} from '$lib/invoices/api';
	import {
		INVOICE_FILTERABLE_STATUSES,
		INVOICE_OVERVIEW_STATUSES,
		INVOICE_STATUS_LABELS,
		INVOICE_STATUS_TONES,
		type InvoiceDerivedStatus
	} from '$lib/invoices/statuses';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import chartIcon from '@tabler/icons/outline/chart-bar.svg?raw';

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<InvoiceDerivedStatus | ''>('');
	let createdFrom = $state('');
	let createdTo = $state('');
	let filtersOpen = $state(false);
	let sortKey = $state<InvoiceSortKey>('created');
	let sortDir = $state<'asc' | 'desc'>('desc');

	// Click a header to sort by it ascending; click it again for descending. Clicking a different sortable
	// header switches to that column, starting ascending again — one sort column at a time.
	function handleSortChange(key: string) {
		if (key === sortKey) {
			sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		} else {
			sortKey = key as InvoiceSortKey;
			sortDir = 'asc';
		}
	}

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	// A date picked in the filter means the whole of that day where the person is, so From starts at midnight
	// and To runs to the last moment — otherwise "to today" would hide everything made today.
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

	// Keyset pagination, so there is no page to jump to — each page hands back the cursor for the next one and
	// Load more asks for it. That is what keeps the query fast however many invoices an office has.
	const invoicesQuery = createInfiniteQuery(() => ({
		queryKey: invoicesListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchInvoices(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: InvoiceListPage) => lastPage.next_cursor ?? undefined
	}));

	const countsQuery = createQuery(() => ({
		queryKey: invoiceCountsKey,
		queryFn: fetchInvoiceOverview
	}));

	// How many jobs owe an invoice today, counted over exactly the predicate the queue lists, so the number on
	// the button and the rows behind it can never disagree. A member who may not bill is answered 0, and the
	// button simply carries no number.
	const readyQuery = createQuery(() => ({
		queryKey: readyToBillCountKey,
		queryFn: fetchReadyToBillCount
	}));
	const readyCount = $derived(readyQuery.data ?? 0);

	const invoices = $derived(invoicesQuery.data?.pages.flatMap((page) => page.invoices) ?? []);
	const locale = $derived(invoicesQuery.data?.pages[0]?.locale ?? 'en-US');
	const hasActiveFilters = $derived(status !== '' || createdFrom !== '' || createdTo !== '');

	function clearFilters() {
		status = '';
		createdFrom = '';
		createdTo = '';
	}

	// The four the office watches. Counted, never clickable — filtering lives on the Status field in the
	// filter panel below, the same split Jobber uses.
	const overviewRows = $derived<StatusOverviewRow[]>(
		INVOICE_OVERVIEW_STATUSES.map((key) => ({
			label: INVOICE_STATUS_LABELS[key],
			count: countsQuery.data?.counts[key] ?? 0,
			tone: INVOICE_STATUS_TONES[key]
		}))
	);

	const statusOptions = [
		{ value: '', label: 'All statuses' },
		...INVOICE_FILTERABLE_STATUSES.map((value) => ({ value, label: INVOICE_STATUS_LABELS[value] }))
	];

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	// A `date` column arrives as `YYYY-MM-DD`; `new Date` on that reads it as UTC midnight and shifts the day
	// back one in negative-offset timezones. Appending `T00:00` parses it as local midnight so the calendar
	// date is kept.
	function formatDay(value: string) {
		return dateFormat.format(new Date(`${value}T00:00`));
	}

	// One formatter per currency rather than one per figure — a page of invoices writes a total and a balance
	// on every row. A plain object, not a Map: nothing reads it reactively, it is only a cache.
	const moneyFormatters: Record<string, Intl.NumberFormat> = {};
	function formatMoney(amountMinor: number | null, currency: string) {
		if (amountMinor === null) return '—';
		const key = `${locale}:${currency}`;
		let formatter = moneyFormatters[key];
		if (!formatter) {
			formatter = new Intl.NumberFormat(locale, { style: 'currency', currency });
			moneyFormatters[key] = formatter;
		}
		return formatter.format(amountMinor / 100);
	}

	function clientName(invoice: InvoiceListItem) {
		return invoice.client?.company_name || invoice.client?.display_name || 'Client removed';
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'number', label: 'Invoice', sortable: true },
		{ key: 'status', label: 'Status' },
		{ key: 'created', label: 'Created', sortable: true },
		{ key: 'due', label: 'Due' },
		{ key: 'total', label: 'Total' },
		{ key: 'balance', label: 'Balance' }
	];
</script>

<svelte:head><title>Invoices · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="fill">
		<PageHeader title="Invoices" description="The bills you have sent your customers.">
			{#snippet actions()}
				<Button href={resolve('/(app)/invoices/ready-to-bill')}>
					Ready to bill{readyCount > 0 ? ` (${readyCount})` : ''}
				</Button>
				<Button variant="primary" href={resolve('/(app)/invoices/new')}>New Invoice</Button>
			{/snippet}
		</PageHeader>

		<div class="invoices-stats">
			<StatusOverviewCard rows={overviewRows} loading={countsQuery.isPending} />
			<KpiCard
				label="Outstanding"
				value="—"
				note="Once billed amounts roll up"
				icon={cashIcon}
				variant="compact"
			/>
			<KpiCard
				label="Overdue"
				value="—"
				note="Once bills start coming due"
				icon={alertIcon}
				variant="compact"
			/>
			<KpiCard
				label="Collected this month"
				value="—"
				note="Once payments are recorded"
				icon={chartIcon}
				variant="compact"
			/>
		</div>

		<div class="invoices-toolbar">
			<div class="invoices-toolbar__search">
				<SearchInput id="invoices-search" bind:value={search} placeholder="Search invoices" />
			</div>
			<!-- eslint-disable svelte/no-at-html-tags -->
			<button
				type="button"
				class="invoices-toolbar__filters-toggle"
				class:invoices-toolbar__filters-toggle--active={hasActiveFilters}
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
				<FilterField id="invoices-status-filter" label="Status">
					<Select
						id="invoices-status-filter"
						value={status}
						onchange={(value) => (status = value as InvoiceDerivedStatus | '')}
						options={statusOptions}
					/>
				</FilterField>
				<FilterField id="invoices-created-from" label="Created from">
					<CalendarPicker
						id="invoices-created-from"
						label="Created from"
						hideLabel
						value={calendarDateFromString(createdFrom)}
						maxValue={calendarDateFromString(createdTo)}
						onchange={(value) => (createdFrom = calendarDateToString(value))}
					/>
				</FilterField>
				<FilterField id="invoices-created-to" label="Created to">
					<CalendarPicker
						id="invoices-created-to"
						label="Created to"
						hideLabel
						value={calendarDateFromString(createdTo)}
						minValue={calendarDateFromString(createdFrom)}
						onchange={(value) => (createdTo = calendarDateToString(value))}
					/>
				</FilterField>
			</FilterBar>
		{/if}

		{#if invoicesQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading invoices" rows={5} />
		{:else if invoicesQuery.isError}
			<ErrorState description="Invoices could not be loaded. Refresh and try again." />
		{:else if invoices.length === 0}
			<EmptyState
				icon={receiptIcon}
				title={hasActiveFilters || debouncedSearch ? 'No matching invoices' : 'No invoices yet'}
				description={hasActiveFilters || debouncedSearch
					? 'Try a different search term or clear your filters.'
					: 'Bills you send your customers will show up here.'}
			/>
		{:else}
			<DataTable
				{columns}
				items={invoices}
				rowId={(invoice) => invoice.id}
				caption="Invoices"
				{sort}
				onSortChange={handleSortChange}
				onRowActivate={(invoice) => goto(resolve('/(app)/invoices/[id]', { id: invoice.id }))}
			>
				{#snippet row(invoice: InvoiceListItem)}
					<th scope="row">
						<div class="invoices-table__client">
							<Avatar
								id={invoice.client?.id ?? invoice.id}
								name={clientName(invoice)}
								size="small"
							/>
							<a
								class="invoices-table__client-link"
								href={resolve('/(app)/invoices/[id]', { id: invoice.id })}
								onclick={(event) => event.stopPropagation()}
							>
								{clientName(invoice)}
							</a>
						</div>
					</th>
					<td>
						<div class="invoices-table__number">
							#{invoice.invoice_number}
							{#if invoice.is_replaced}<span class="invoices-table__replaced">Replaced</span>{/if}
						</div>
						<div class="invoices-table__subject">{invoice.subject}</div>
					</td>
					<td>
						<StatusBadge status={INVOICE_STATUS_TONES[invoice.derived_status]}>
							{INVOICE_STATUS_LABELS[invoice.derived_status]}
						</StatusBadge>
					</td>
					<td>{dateFormat.format(new Date(invoice.created_at))}</td>
					<td>{formatDay(invoice.due_date)}</td>
					<td>{formatMoney(invoice.total_minor, invoice.currency_code)}</td>
					<td>{formatMoney(invoice.remaining_minor, invoice.currency_code)}</td>
				{/snippet}
				{#snippet footer()}
					<ListLoadMore
						hasNextPage={invoicesQuery.hasNextPage}
						isFetchingNextPage={invoicesQuery.isFetchingNextPage}
						onLoadMore={() => invoicesQuery.fetchNextPage()}
					/>
				{/snippet}
			</DataTable>
		{/if}
	</PageContainer>
</div>

<style lang="scss">
	.invoices-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}

	.invoices-table__client-link {
		color: var(--color-heading);
		font-weight: 700;
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

	.invoices-table__number {
		display: flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-heading);
		font-weight: 700;
	}

	/* A superseded bill: its correction or rebill is the live one. A quiet mark, not a status badge. */
	.invoices-table__replaced {
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.invoices-table__subject {
		color: var(--color-text--secondary);
	}

	/* Overview card plus three metric tiles, the same top row as Jobs and Quotes. The tiles read "—" until
	   the money rollups they need are built in later parts. */
	.invoices-stats {
		display: grid;
		gap: var(--space-base);
		grid-template-columns: repeat(4, minmax(0, 1fr));
		margin-top: var(--space-large);
	}

	.invoices-toolbar {
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
		.invoices-stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 639px) {
		.invoices-stats {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
