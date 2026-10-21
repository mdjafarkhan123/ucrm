<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
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
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import RecordListCard from '$lib/components/data-display/RecordListCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import AttentionCard, {
		type AttentionFact,
		type AttentionTile
	} from '$lib/components/work/AttentionCard.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import type { MoneyFigureRow } from '$lib/components/work/MoneyFeatureCard.svelte';
	import {
		conversionChange,
		fetchQuoteListOverview,
		followUpText,
		percentText,
		quoteListOverviewKey,
		quoteStatusDetail
	} from '$lib/quotes/list-overview';
	import {
		bulkArchiveQuotes,
		fetchQuoteOverview,
		fetchQuotes,
		quoteCountsKey,
		quotesListKey,
		type QuoteListItem,
		type QuoteListPage,
		type QuoteSortKey,
		fetchQuote,
		quoteDetailKey
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
	import dashedCircleIcon from '@tabler/icons/outline/circle-dashed.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import eyeOffIcon from '@tabler/icons/outline/eye-off.svg?raw';
	import mailCheckIcon from '@tabler/icons/outline/mail-check.svg?raw';
	import filePencilIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import thumbUpIcon from '@tabler/icons/outline/thumb-up.svg?raw';
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import fileTextPageIcon from '@tabler/icons/outline/file-text.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<StoredQuoteStatus | ''>('');
	let createdFrom = $state('');
	let createdTo = $state('');
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

	// The money per status, the conversion card and the follow-up strip. Its key sits under the counts key,
	// so everything that already refreshes the counts after a quote changes refreshes this too.
	const overviewQuery = createQuery(() => ({
		queryKey: quoteListOverviewKey,
		queryFn: fetchQuoteListOverview
	}));
	const overview = $derived(overviewQuery.data);
	const overviewLoading = $derived(overviewQuery.isPending);

	// Whole currency units on the overview cards; the table keeps cents.
	const wholeFormatter = $derived(
		new Intl.NumberFormat(countsQuery.data?.locale ?? 'en-US', {
			style: 'currency',
			currency: countsQuery.data?.currency_code ?? 'USD',
			maximumFractionDigits: 0
		})
	);
	function formatWhole(amountMinor: number | null | undefined) {
		if (amountMinor === null || amountMinor === undefined) return '—';
		return wholeFormatter.format(amountMinor / 100);
	}
	const shortDay = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });
	function formatShortDay(iso: string) {
		return shortDay.format(new Date(iso));
	}
	// A YYYY-MM-DD calendar day, kept on its own date wherever the browser is.
	function formatCalendarDay(day: string) {
		return day ? shortDay.format(new Date(`${day}T00:00`)) : '';
	}

	// A Field member holds no quotes.view -- the list query is the thing that actually finds out. Default
	// to visible so a permitted member's buttons aren't delayed behind this fetch, and hide only once a
	// real denial comes back.
	const quotesActionsAllowed = $derived(
		quotesQuery.isError ? (quotesQuery.error as { status?: number })?.status !== 403 : true
	);
	const quotes = $derived(quotesQuery.data?.pages.flatMap((page) => page.quotes) ?? []);
	const locale = $derived(quotesQuery.data?.pages[0]?.locale ?? 'en-US');
	const hasActiveFilters = $derived(status !== '' || createdFrom !== '' || createdTo !== '');

	// The number the composer just saved, carried across in the URL so the list can say so out loud.
	const savedNumber = $derived(page.url.searchParams.get('saved') ?? '');

	// The four the office acts on, each with a line saying what it means. Picking one sets the Status
	// filter in the list's header to it; picking it again, or choosing another status there, clears it.
	// With money the line reads "$8,920 not sent yet"; without it the plain sentence stands alone.
	const attentionHints: Record<(typeof QUOTE_OVERVIEW_STATUSES)[number], string> = {
		draft: 'not sent yet',
		awaiting_response: 'waiting on the client',
		changes_requested: 'client asked for edits',
		approved: 'ready for a job'
	};
	const attentionIcons: Record<(typeof QUOTE_OVERVIEW_STATUSES)[number], string> = {
		draft: filePencilIcon,
		awaiting_response: sendIcon,
		changes_requested: messageIcon,
		approved: thumbUpIcon
	};
	const statusMoney = $derived(overview?.status_minor ?? null);
	function sentence(text: string) {
		return text.charAt(0).toUpperCase() + text.slice(1);
	}
	const attentionTiles = $derived<AttentionTile[]>(
		QUOTE_OVERVIEW_STATUSES.map((key) => ({
			key,
			label: QUOTE_STATUS_LABELS[key],
			amount: statusMoney ? formatWhole(statusMoney[key]) : undefined,
			hint: statusMoney ? attentionHints[key] : sentence(attentionHints[key]),
			count: countsQuery.data?.counts[key] ?? 0,
			tone: QUOTE_STATUS_TONES[key],
			icon: attentionIcons[key]
		}))
	);
	// The headline: what the open quotes are worth, or a dash for someone who may not see prices.
	const openSummary = $derived(
		overview
			? {
					value: formatWhole(overview.open_minor),
					label: `${overview.open_count} ${overview.open_count === 1 ? 'quote' : 'quotes'} not yet a job`
				}
			: undefined
	);
	const followUpFacts = $derived<AttentionFact[]>(
		overview
			? [
					{
						icon: hourglassIcon,
						value: String(overview.waiting_over_7_days),
						label: 'waiting more than 7 days'
					},
					{
						icon: eyeOffIcon,
						value: String(overview.sent_not_opened),
						label: 'sent but not opened yet'
					},
					{
						icon: mailCheckIcon,
						value: '',
						label: followUpText(overview.follow_up_days),
						align: 'end'
					}
				]
			: []
	);

	// The dark card: of the quotes first sent in the past 30 days, how many became jobs.
	const conversionValue = $derived(
		overview?.rate_basis_points != null ? percentText(overview.rate_basis_points) : '—'
	);
	const conversionNote = $derived.by(() => {
		if (!overview) return 'Loading…';
		const range = `${formatCalendarDay(overview.window_start)} – ${formatCalendarDay(overview.window_end)}`;
		if (overview.sent_count === 0) return `No quotes sent ${range}`;
		return `Sent quotes that became jobs, ${range}`;
	});
	const conversionRows = $derived<MoneyFigureRow[]>(
		overview
			? [
					{
						label: 'Quotes sent',
						count: String(overview.sent_count),
						value: formatWhole(overview.sent_minor)
					},
					{
						label: 'Converted to jobs',
						count: String(overview.converted_count),
						value: formatWhole(overview.converted_minor)
					}
				]
			: []
	);
	const selectedTile = $derived(
		(QUOTE_OVERVIEW_STATUSES as readonly string[]).includes(status) ? status : ''
	);

	const statusOptions = [
		{ value: '', label: 'All' },
		...STORED_QUOTE_STATUSES.map((value) => ({ value, label: QUOTE_STATUS_LABELS[value] }))
	];

	const sortSummary = $derived.by(() => {
		if (sortKey === 'number')
			return sortDir === 'asc' ? 'Lowest quote number first' : 'Highest quote number first';
		return sortDir === 'asc' ? 'Oldest first' : 'Newest first';
	});

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});

	// One formatter per currency rather than one per figure — a page of quotes writes a total on every row.
	// A plain object, not a Map: nothing reads it reactively, it is only a cache the formatter fills.
	const moneyFormatters: Record<string, Intl.NumberFormat> = {};
	function formatTotal(quote: QuoteListItem) {
		if (quote.total_minor === null) return '—';
		const key = `${locale}:${quote.currency_code}`;
		let formatter = moneyFormatters[key];
		if (!formatter) {
			formatter = new Intl.NumberFormat(locale, {
				style: 'currency',
				currency: quote.currency_code
			});
			moneyFormatters[key] = formatter;
		}
		return formatter.format(quote.total_minor / 100);
	}

	// The street on one line, the town and region under it. A quote sent earlier keeps the one-line address
	// its version froze at send, so that row shows it whole on the first line.
	function propertyStreet(quote: QuoteListItem) {
		if (quote.property_address) return quote.property_address;
		return quote.property?.address_line1 || 'No property';
	}
	function propertyArea(quote: QuoteListItem) {
		if (quote.property_address || !quote.property) return '';
		return [quote.property.city, quote.property.state_region].filter(Boolean).join(', ');
	}
	function clientName(quote: QuoteListItem) {
		return quote.client_display_name ?? quote.client?.display_name ?? 'Client removed';
	}
	function quoteTitle(quote: QuoteListItem) {
		return quote.title ?? 'Untitled quote';
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client', width: '200px' },
		{ key: 'number', label: 'Quote', sortable: true },
		{ key: 'property', label: 'Property', width: '170px' },
		{ key: 'created', label: 'Created', sortable: true, width: '120px' },
		{ key: 'status', label: 'Status', width: '160px' },
		{ key: 'total', label: 'Total', align: 'end', width: '100px' },
		{ key: 'open', label: 'Open quote', hideLabel: true, width: '48px' }
	];

	function prefetchQuote(item: { id: string }) {
		void queryClient.prefetchQuery({
			queryKey: quoteDetailKey(item.id),
			queryFn: () => fetchQuote(item.id),
			staleTime: 15_000
		});
	}
</script>

<svelte:head><title>Quotes · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="open">
		{#if savedNumber}
			<p class="quotes__saved" role="status">Quote #{savedNumber} was saved.</p>
		{/if}
		<PageHeader
			icon={fileTextPageIcon}
			tone="quote"
			class="quotes-page__header"
			title="Quotes"
			description="Every price you have put in front of a client, from draft to approved."
		>
			{#snippet actions()}
				{#if quotesActionsAllowed}
					<DropdownMenu triggerText="More" unavailableReason={moreActionsReason} />
					<Button variant="primary" href={resolve('/(app)/quotes/new')}>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="quotes-header__icon" aria-hidden="true">{@html plusIcon}</span>
						New quote
					</Button>
				{/if}
			{/snippet}
		</PageHeader>

		<div class="quotes-overview">
			<AttentionCard
				icon={fileTextPageIcon}
				tone="quote"
				title="Open quotes"
				description="Where every unfinished quote stands. Pick one to see only those quotes."
				tiles={attentionTiles}
				selectedKey={selectedTile}
				onSelect={(key) => (status = key as StoredQuoteStatus | '')}
				summary={openSummary}
				facts={followUpFacts}
				loading={countsQuery.isPending || overviewLoading}
			>
				{#snippet feature()}
					<KpiCard
						tone="feature"
						icon={trendingUpIcon}
						label="Conversion rate · past 30 days"
						value={conversionValue}
						change={overview
							? conversionChange(overview.rate_basis_points, overview.prior_rate_basis_points)
							: null}
						note={conversionNote}
						rows={conversionRows}
						loading={overviewLoading}
					/>
				{/snippet}
			</AttentionCard>
		</div>

		<RecordListCard
			title="All quotes"
			subtitle={sortSummary}
			padBody={quotesQuery.isPending || quotesQuery.isError || quotes.length === 0}
		>
			{#snippet toolbar()}
				<div class="quotes-card__search">
					<SearchInput
						id="quotes-search"
						bind:value={search}
						placeholder="Search quotes"
						size="compact"
					/>
				</div>
				<FilterChip
					id="quotes-status-filter"
					variant="toolbar"
					icon={dashedCircleIcon}
					label="Status"
					value={status}
					options={statusOptions}
					restValue=""
					onchange={(value) => (status = value as StoredQuoteStatus | '')}
				/>
				<DateRangeChip
					id="quotes-created"
					label="Created"
					from={createdFrom}
					to={createdTo}
					onchange={(range) => {
						createdFrom = range.from;
						createdTo = range.to;
					}}
				/>
			{/snippet}

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
					variant="card"
					{columns}
					items={quotes}
					rowId={(quote) => quote.id}
					caption="Quotes"
					selectable
					bind:selectedIds
					rowLabel={(quote) => `Select quote #${quote.quote_number}`}
					onRowHover={prefetchQuote}
					onRowActivate={(quote) => void goto(resolve('/(app)/quotes/[id=uuid]', { id: quote.id }))}
					{sort}
					onSortChange={handleSortChange}
				>
					{#snippet row(quote: QuoteListItem)}
						{@const detail = quoteStatusDetail(quote, formatShortDay)}
						<th scope="row">
							<div class="quotes-table__client">
								<Avatar id={quote.client?.id ?? quote.id} name={clientName(quote)} size="base" />
								<a
									class="quotes-table__client-link"
									href={resolve('/(app)/quotes/[id=uuid]', { id: quote.id })}>{clientName(quote)}</a
								>
							</div>
						</th>
						<td>
							<div class="quotes-table__title">{quoteTitle(quote)}</div>
							<div class="quotes-table__meta">
								#{quote.quote_number}{quote.from_request
									? ' · From request'
									: ''}{(quote.published_version_number ?? 0) > 1
									? ` · Version ${quote.published_version_number}`
									: ''}
							</div>
						</td>
						<td>
							<div class="quotes-table__street">{propertyStreet(quote)}</div>
							{#if propertyArea(quote)}
								<div class="quotes-table__meta">{propertyArea(quote)}</div>
							{/if}
						</td>
						<td class="quotes-table__date">{dateFormat.format(new Date(quote.created_at))}</td>
						<td>
							<StatusBadge size="compact" status={QUOTE_STATUS_TONES[quote.status]}>
								{QUOTE_STATUS_LABELS[quote.status]}
							</StatusBadge>
							{#if detail}
								<div class="quotes-table__meta quotes-table__detail">
									{detail.text}
									{#if detail.job}
										<a
											class="quotes-table__job-link"
											href={resolve('/(app)/jobs/[id=uuid]', { id: detail.job.id })}
											onclick={(event) => event.stopPropagation()}>{detail.job.label}</a
										>
									{/if}
								</div>
							{/if}
						</td>
						<td class="quotes-table__total">{formatTotal(quote)}</td>
						<td class="quotes-table__open">
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span aria-hidden="true">{@html chevronRightIcon}</span>
						</td>
					{/snippet}
					{#snippet footer()}
						<ListLoadMore
							count={quotes.length}
							recordName="quotes"
							recordColor="quote"
							variant="card"
							label="Load more quotes"
							hasNextPage={quotesQuery.hasNextPage}
							isFetchingNextPage={quotesQuery.isFetchingNextPage}
							onLoadMore={() => quotesQuery.fetchNextPage()}
							searchNarrowed={quotesQuery.data?.pages.at(-1)?.search_narrowed ?? false}
							narrowedLabel="Many quotes match — type more to see the rest."
						/>
					{/snippet}
				</DataTable>
			{/if}
		</RecordListCard>
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

	/* The page header sits straight on the app background; the cards under it share one 24px rhythm. */
	:global(.quotes-page__header) {
		margin-bottom: var(--space-large);
	}

	.quotes-header__icon {
		display: inline-flex;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	/* Open quotes takes the room it needs; the conversion card keeps a steady width beside it. */
	.quotes-overview {
		margin-bottom: var(--space-large);
	}

	.quotes-card__search {
		width: 260px;
		max-width: 100%;
	}

	.quotes-bulk-bar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
		font-weight: 600;
	}

	.quotes-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}

	/* The row's real navigation link — carries keyboard focus, new-tab and cmd-click, while a plain click
	   anywhere on the row still opens the quote through the table's onRowActivate. */
	.quotes-table__client-link {
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

	.quotes-table__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
	}
	.quotes-table__street {
		display: -webkit-box;
		overflow: hidden;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.quotes-table__meta {
		margin-top: 3px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}
	.quotes-table__detail {
		margin-top: 5px;
		white-space: nowrap;
	}
	.quotes-table__job-link {
		color: var(--color-interactive);
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
	.quotes-table__date {
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		white-space: nowrap;
	}
	.quotes-table__total {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-variant-numeric: tabular-nums;
		font-weight: 600;
		text-align: end;
		white-space: nowrap;
	}
	.quotes-table__open {
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
	}
</style>
