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
	import { averagePaidFact, invoiceRowNote, overdueReminderFact } from '$lib/invoices/list-facts';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import boltIcon from '@tabler/icons/outline/bolt.svg?raw';
	import MoneyFeatureCard, {
		type MoneyBreakdownPart
	} from '$lib/components/work/MoneyFeatureCard.svelte';
	import {
		fetchInvoiceOverview,
		fetchInvoices,
		fetchReadyToBillCount,
		invoiceCountsKey,
		invoicesListKey,
		readyToBillCountKey,
		type InvoiceListItem,
		type InvoiceListPage,
		type InvoiceSortKey,
		fetchInvoice,
		invoiceDetailKey
	} from '$lib/invoices/api';
	import {
		INVOICE_FILTERABLE_STATUSES,
		INVOICE_OVERVIEW_STATUSES,
		INVOICE_STATUS_LABELS,
		INVOICE_STATUS_TONES,
		type InvoiceDerivedStatus
	} from '$lib/invoices/statuses';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import dashedCircleIcon from '@tabler/icons/outline/circle-dashed.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import clipboardCheckIcon from '@tabler/icons/outline/clipboard-check.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import alarmIcon from '@tabler/icons/outline/alarm.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import filePencilIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<InvoiceDerivedStatus | ''>('');
	let createdFrom = $state('');
	let createdTo = $state('');
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
	const queryClient = useQueryClient();
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

	// Seeing the bills and writing them are separate rights: office is read-only here. The list answers both,
	// so a member who may write keeps their buttons from the first page rather than waiting on a second fetch.
	const firstPage = $derived(invoicesQuery.data?.pages[0]);
	const canCreateInvoice = $derived(firstPage?.can_create ?? false);
	const canSendInvoices = $derived(firstPage?.can_send ?? false);
	const invoices = $derived(invoicesQuery.data?.pages.flatMap((page) => page.invoices) ?? []);
	const locale = $derived(invoicesQuery.data?.pages[0]?.locale ?? 'en-US');
	const hasActiveFilters = $derived(status !== '' || createdFrom !== '' || createdTo !== '');

	const overviewCurrency = $derived(countsQuery.data?.currency_code ?? 'USD');
	// Overdue/Outstanding/Collected read from the same overview fetch as the status counts, so one loading
	// state covers the whole top row. A signed-in reader without invoices.view_price gets null money back from
	// the database, not a wrong number, and the card says so instead of showing a dash with no explanation.
	const canSeeInvoiceMoney = $derived(
		countsQuery.data != null && countsQuery.data.outstanding_minor !== null
	);
	const outstandingMinor = $derived(countsQuery.data?.outstanding_minor ?? null);
	const overdueMinor = $derived(countsQuery.data?.overdue_minor ?? null);
	const notDueMinor = $derived(
		outstandingMinor === null || overdueMinor === null
			? null
			: Math.max(outstandingMinor - overdueMinor, 0)
	);

	// Whole currency units on the overview cards; the table keeps cents.
	function formatWhole(amountMinor: number | null) {
		if (amountMinor === null) return '—';
		return new Intl.NumberFormat(countsQuery.data?.locale ?? 'en-US', {
			style: 'currency',
			currency: overviewCurrency,
			maximumFractionDigits: 0
		}).format(amountMinor / 100);
	}

	// The four the office watches, each with a line saying what it means. Picking one sets the Status filter
	// below to it; picking it again, or choosing another status there, clears it.
	const attentionIcons: Record<(typeof INVOICE_OVERVIEW_STATUSES)[number], string> = {
		past_due: alarmIcon,
		awaiting_payment: clockIcon,
		draft: filePencilIcon,
		paid: circleCheckIcon
	};
	const attentionTiles = $derived<AttentionTile[]>(
		INVOICE_OVERVIEW_STATUSES.map((key) => {
			// With money the amount is drawn in bold before the words ("$8,940 still owed").
			let hint: string;
			let amount: string | undefined;
			if (key === 'past_due') {
				amount = overdueMinor === null ? undefined : formatWhole(overdueMinor);
				hint = overdueMinor === null ? 'Past the due date' : 'still owed';
			} else if (key === 'awaiting_payment') {
				amount = notDueMinor === null ? undefined : formatWhole(notDueMinor);
				hint = notDueMinor === null ? 'Sent, not due yet' : 'owed, not due yet';
			} else if (key === 'draft') {
				hint = 'Not sent yet';
			} else {
				hint = 'Settled in full';
			}
			return {
				key,
				label: INVOICE_STATUS_LABELS[key],
				hint,
				amount,
				count: countsQuery.data?.counts[key] ?? 0,
				tone: INVOICE_STATUS_TONES[key],
				icon: attentionIcons[key]
			};
		})
	);
	const selectedTile = $derived(
		(INVOICE_OVERVIEW_STATUSES as readonly string[]).includes(status) ? status : ''
	);

	// The strip under the tiles: how long bills take to get paid, and whether overdue reminders go out.
	const gettingPaidFacts = $derived.by<AttentionFact[]>(() => {
		const facts = countsQuery.data?.facts;
		if (!facts) return [];
		const average = averagePaidFact(facts);
		const reminders = overdueReminderFact(facts);
		return [
			{ icon: hourglassIcon, value: average.value, label: average.label },
			{
				icon: boltIcon,
				value: reminders.value,
				label: reminders.label,
				tone: facts.overdue_reminders_on ? 'warning' : undefined
			}
		];
	});

	const openCount = $derived(
		(countsQuery.data?.counts.awaiting_payment ?? 0) + (countsQuery.data?.counts.past_due ?? 0)
	);
	const moneyEyebrow = $derived(
		countsQuery.isPending
			? 'Owed to you'
			: `Owed to you · ${openCount} open ${openCount === 1 ? 'invoice' : 'invoices'}`
	);
	const moneyNote = $derived.by(() => {
		if (countsQuery.isPending) return 'Loading…';
		if (!canSeeInvoiceMoney) return 'You do not have access to invoice amounts';
		return `Collected ${formatWhole(countsQuery.data?.collected_this_month_minor ?? null)} so far this month`;
	});
	const moneyBreakdown = $derived<MoneyBreakdownPart[]>(
		overdueMinor === null || notDueMinor === null
			? []
			: [
					{
						label: 'Overdue',
						value: formatWhole(overdueMinor),
						share: overdueMinor,
						tone: 'critical'
					},
					{
						label: 'Not due yet',
						value: formatWhole(notDueMinor),
						share: notDueMinor,
						tone: 'neutral'
					}
				]
	);

	const statusOptions = [
		{ value: '', label: 'All' },
		...INVOICE_FILTERABLE_STATUSES.map((value) => ({ value, label: INVOICE_STATUS_LABELS[value] }))
	];

	const sortSummary = $derived.by(() => {
		if (sortKey === 'number')
			return sortDir === 'asc' ? 'Lowest invoice number first' : 'Highest invoice number first';
		return sortDir === 'asc' ? 'Oldest first' : 'Newest first';
	});

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

	// How far the due date is from today, for a bill that is still waiting on money. Counted in whole days
	// between local calendar dates.
	function dueNote(invoice: InvoiceListItem): { text: string; late: boolean } | null {
		if (invoice.derived_status !== 'awaiting_payment' && invoice.derived_status !== 'past_due')
			return null;
		const today = new Date();
		const todayMidnight = new Date(today.getFullYear(), today.getMonth(), today.getDate());
		const due = new Date(`${invoice.due_date}T00:00`);
		const days = Math.round((due.getTime() - todayMidnight.getTime()) / 86_400_000);
		if (days === 0) return { text: 'Due today', late: false };
		if (days > 0) return { text: `In ${days} ${days === 1 ? 'day' : 'days'}`, late: false };
		return { text: `${-days} ${days === -1 ? 'day' : 'days'} late`, late: true };
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
	// Money has been taken against the bill but not all of it.
	function isPartPaid(invoice: InvoiceListItem) {
		return (
			invoice.total_minor !== null &&
			invoice.remaining_minor !== null &&
			invoice.remaining_minor > 0 &&
			invoice.remaining_minor < invoice.total_minor &&
			invoice.derived_status !== 'draft'
		);
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client', width: '210px' },
		{ key: 'number', label: 'Invoice', sortable: true },
		{ key: 'created', label: 'Created', sortable: true, width: '120px' },
		{ key: 'due', label: 'Due', width: '130px' },
		{ key: 'status', label: 'Status', width: '150px' },
		{ key: 'total', label: 'Total', align: 'end', width: '100px' },
		{ key: 'balance', label: 'Balance', align: 'end', width: '110px' },
		{ key: 'open', label: 'Open invoice', hideLabel: true, width: '56px' }
	];

	function prefetchInvoice(item: { id: string }) {
		void queryClient.prefetchQuery({
			queryKey: invoiceDetailKey(item.id),
			queryFn: () => fetchInvoice(item.id),
			staleTime: 15_000
		});
	}
</script>

<svelte:head><title>Invoices · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="open">
		<PageHeader
			class="invoices-page__header"
			eyebrow="Work & money"
			title="Invoices"
			description="The bills you have sent your customers, and what is still owed on them."
		>
			{#snippet actions()}
				{#if canCreateInvoice}
					<Button
						class="invoices-header__button"
						variant="secondary"
						href={resolve('/(app)/invoices/ready-to-bill')}
					>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="invoices-header__icon" aria-hidden="true">{@html clipboardCheckIcon}</span>
						Ready to bill
						{#if readyCount > 0}
							<span class="invoices-header__count" aria-label={`${readyCount} jobs ready`}
								>{readyCount}</span
							>
						{/if}
					</Button>
				{/if}
				{#if canSendInvoices}
					<Button
						class="invoices-header__button"
						variant="secondary"
						href={resolve('/(app)/invoices/send')}
					>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="invoices-header__icon" aria-hidden="true">{@html sendIcon}</span>
						Send invoices
					</Button>
				{/if}
				{#if canCreateInvoice}
					<Button
						class="invoices-header__button"
						variant="primary"
						href={resolve('/(app)/invoices/new')}
					>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="invoices-header__icon" aria-hidden="true">{@html plusIcon}</span>
						New invoice
					</Button>
				{/if}
			{/snippet}
		</PageHeader>

		<div class="invoices-overview">
			<AttentionCard
				title="Getting paid"
				description="Where every bill stands. Pick one to see only those invoices."
				tiles={attentionTiles}
				selectedKey={selectedTile}
				onSelect={(key) => (status = key as InvoiceDerivedStatus | '')}
				facts={gettingPaidFacts}
				loading={countsQuery.isPending}
			/>
			<MoneyFeatureCard
				icon={receiptIcon}
				eyebrow={moneyEyebrow}
				value={formatWhole(outstandingMinor)}
				note={moneyNote}
				breakdown={moneyBreakdown}
				loading={countsQuery.isPending}
			/>
		</div>

		<RecordListCard
			title="All invoices"
			subtitle={sortSummary}
			padBody={invoicesQuery.isPending || invoicesQuery.isError || invoices.length === 0}
		>
			{#snippet toolbar()}
				<div class="invoices-card__search">
					<SearchInput
						id="invoices-search"
						bind:value={search}
						placeholder="Search invoices"
						size="compact"
					/>
				</div>
				<FilterChip
					id="invoices-status-filter"
					variant="toolbar"
					icon={dashedCircleIcon}
					label="Status"
					value={status}
					options={statusOptions}
					restValue=""
					onchange={(value) => (status = value as InvoiceDerivedStatus | '')}
				/>
				<DateRangeChip
					id="invoices-created"
					label="Created"
					from={createdFrom}
					to={createdTo}
					onchange={(range) => {
						createdFrom = range.from;
						createdTo = range.to;
					}}
				/>
			{/snippet}

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
					variant="card"
					{columns}
					items={invoices}
					rowId={(invoice) => invoice.id}
					caption="Invoices"
					{sort}
					onSortChange={handleSortChange}
					onRowHover={prefetchInvoice}
					onRowActivate={(invoice) =>
						goto(resolve('/(app)/invoices/[id=uuid]', { id: invoice.id }))}
				>
					{#snippet row(invoice: InvoiceListItem)}
						{@const note = dueNote(invoice)}
						{@const rowNote = invoiceRowNote({ ...invoice, part_paid: isPartPaid(invoice) })}
						<th scope="row">
							<div class="invoices-table__client">
								<Avatar
									id={invoice.client?.id ?? invoice.id}
									name={clientName(invoice)}
									size="base"
								/>
								<a
									class="invoices-table__client-link"
									href={resolve('/(app)/invoices/[id=uuid]', { id: invoice.id })}
									onclick={(event) => event.stopPropagation()}
								>
									{clientName(invoice)}
								</a>
							</div>
						</th>
						<td>
							<div class="invoices-table__title">{invoice.subject}</div>
							<div class="invoices-table__meta">
								#{invoice.invoice_number}
								{#if invoice.is_replaced}<span class="invoices-table__replaced">Replaced</span>{/if}
								{#if rowNote}<span>·</span>
									<span class={[rowNote.unopened && 'invoices-table__unopened']}
										>{rowNote.text}</span
									>
								{/if}
							</div>
						</td>
						<td class="invoices-table__date">{dateFormat.format(new Date(invoice.created_at))}</td>
						<td>
							<div class="invoices-table__date">{formatDay(invoice.due_date)}</div>
							{#if note}
								<div class={['invoices-table__meta', note.late && 'invoices-table__meta--late']}>
									{note.text}
								</div>
							{/if}
						</td>
						<td>
							<StatusBadge size="compact" status={INVOICE_STATUS_TONES[invoice.derived_status]}>
								{INVOICE_STATUS_LABELS[invoice.derived_status]}
							</StatusBadge>
						</td>
						<td class="invoices-table__total">
							{formatMoney(invoice.total_minor, invoice.currency_code)}
						</td>
						<td class="invoices-table__balance">
							{formatMoney(invoice.remaining_minor, invoice.currency_code)}
						</td>
						<td class="invoices-table__open">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span aria-hidden="true">{@html chevronRightIcon}</span>
						</td>
					{/snippet}
					{#snippet footer()}
						<ListLoadMore
							variant="card"
							label="Load more invoices"
							hasNextPage={invoicesQuery.hasNextPage}
							isFetchingNextPage={invoicesQuery.isFetchingNextPage}
							onLoadMore={() => invoicesQuery.fetchNextPage()}
						/>
					{/snippet}
				</DataTable>
			{/if}
		</RecordListCard>
	</PageContainer>
</div>

<style lang="scss">
	/* The page header sits straight on the app background; the cards under it share one 24px rhythm. */
	:global(.invoices-page__header) {
		margin-bottom: var(--space-large);
	}

	.invoices-header__icon {
		display: inline-flex;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
	/* The number of jobs waiting to be billed, in the same warning tint as a warning status. */
	.invoices-header__count {
		padding: 2px 8px;
		border-radius: 10px;
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
		font-size: 11px;
		font-weight: 700;
		line-height: 1.2;
	}

	/* Getting paid takes the room it needs; the money card keeps a steady width beside it. */
	.invoices-overview {
		display: grid;
		gap: var(--space-large);
		grid-template-columns: minmax(0, 1fr) 336px;
		margin-bottom: var(--space-large);
	}

	.invoices-card__search {
		width: 260px;
		max-width: 100%;
	}

	.invoices-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	/* The row's real navigation link — carries keyboard focus, new-tab and cmd-click, while a plain click
	   anywhere on the row still opens the invoice through the table's onRowActivate. */
	.invoices-table__client-link {
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

	.invoices-table__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
	}
	.invoices-table__meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-smaller);
		margin-top: 3px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;

		&--late {
			color: var(--color-critical);
		}
	}
	/* Sent and still owed, and the client has not opened it: worth chasing. */
	.invoices-table__unopened {
		color: var(--color-critical);
		font-weight: 600;
	}
	/* A superseded bill: its correction or rebill is the live one. A quiet mark, not a status badge. */
	.invoices-table__replaced {
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-small);
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		font-weight: 600;
	}
	.invoices-table__date {
		color: var(--color-text);
		font-size: 13px;
		font-weight: 500;
		white-space: nowrap;
	}
	.invoices-table__total {
		color: var(--color-text--secondary);
		font-size: 13px;
		font-variant-numeric: tabular-nums;
		font-weight: 500;
		text-align: end;
		white-space: nowrap;
	}
	.invoices-table__balance {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-variant-numeric: tabular-nums;
		font-weight: 700;
		text-align: end;
		white-space: nowrap;
	}
	.invoices-table__open {
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
		.invoices-overview {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
