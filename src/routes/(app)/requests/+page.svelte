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
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import DataTable, {
		type DataTableColumn,
		type DataTableSort
	} from '$lib/components/data-display/DataTable.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import RecordListCard from '$lib/components/data-display/RecordListCard.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import AttentionCard, { type AttentionTile } from '$lib/components/work/AttentionCard.svelte';
	import MoneyFeatureCard from '$lib/components/work/MoneyFeatureCard.svelte';
	import { conversionRateCard, conversionTrend } from '$lib/requests/metrics';
	import {
		fetchRequestCounts,
		fetchRequests,
		requestCountsKey,
		requestsListKey,
		type RequestListItem,
		type RequestListPage,
		type RequestSortKey,
		fetchRequest,
		requestDetailKey
	} from '$lib/requests/api';
	import {
		REQUEST_STATUS_LABELS,
		REQUEST_STATUS_TONES,
		type DisplayRequestStatus
	} from '$lib/requests/statuses';
	import clipboardIcon from '@tabler/icons/outline/clipboard-list.svg?raw';
	import dashedCircleIcon from '@tabler/icons/outline/circle-dashed.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import dotsIcon from '@tabler/icons/outline/dots.svg?raw';

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<DisplayRequestStatus | ''>('');
	let selectedIds = $state<Set<string>>(new Set());
	let sortKey = $state<RequestSortKey>('requested');
	let sortDir = $state<'asc' | 'desc'>('desc');

	// Click a header to sort by it ascending; click it again for descending. Clicking a different
	// sortable header switches to that column, starting ascending again — one sort column at a time.
	function handleSortChange(key: string) {
		if (key === sortKey) {
			sortDir = sortDir === 'asc' ? 'desc' : 'asc';
		} else {
			sortKey = key as RequestSortKey;
			sortDir = 'asc';
		}
	}

	// Nothing behind these yet. Each says why rather than sitting there dead, the way the Clients page does.
	const bulkReason = 'Not ready yet — this arrives with the request actions.';
	const moreActionsReason = 'Booking form settings arrive with the public request form.';

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({
		search: debouncedSearch,
		statuses: status ? [status] : [],
		sort: sortKey,
		dir: sortDir
	});
	const sort = $derived<DataTableSort>({ key: sortKey, direction: sortDir });

	// Keyset pagination, so there is no page to jump to — each page hands back the cursor for the next one
	// and Load more asks for it. That is what keeps the query fast however many requests an office has.
	const queryClient = useQueryClient();
	const requestsQuery = createInfiniteQuery(() => ({
		queryKey: requestsListKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchRequests(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: RequestListPage) => lastPage.next_cursor ?? undefined
	}));

	const countsQuery = createQuery(() => ({
		queryKey: requestCountsKey,
		queryFn: fetchRequestCounts
	}));

	const requests = $derived(requestsQuery.data?.pages.flatMap((page) => page.requests) ?? []);
	const hasActiveFilters = $derived(status !== '');

	// The five the office acts on, most urgent first, each with a line saying what it means. Picking one
	// sets the Status filter beside the search to it; picking it again, or choosing another status there,
	// clears it.
	const attentionOrder = [
		{ key: 'overdue', hint: 'Assessment date passed, not done' },
		{ key: 'needs_approval', hint: 'Website bookings asking for a time' },
		{ key: 'new', hint: 'No assessment or quote yet' },
		{ key: 'unscheduled', hint: 'Assessment needed, no time set' },
		{ key: 'assessment_completed', hint: 'Assessed, no quote yet' }
	] as const;

	const attentionTiles = $derived<AttentionTile[]>(
		attentionOrder.map(({ key, hint }) => ({
			key,
			label: REQUEST_STATUS_LABELS[key],
			hint,
			count: countsQuery.data?.counts[key] ?? 0,
			tone: REQUEST_STATUS_TONES[key]
		}))
	);
	const selectedTile = $derived(attentionOrder.some(({ key }) => key === status) ? status : '');

	// One dark card for the two 30-day figures: the share of new requests that became a quote or job
	// (with how it moved against the 30 days before) and how many new requests there were.
	const conversion = $derived(
		countsQuery.data
			? conversionRateCard(countsQuery.data.last_30_days, countsQuery.data.previous_30_days)
			: { value: '—', note: 'Loading…' }
	);
	const conversionNote = $derived.by(() => {
		const data = countsQuery.data;
		if (!data) return 'Loading…';
		if (data.last_30_days.new === 0) return conversion.note;
		const trend = conversionTrend(data.last_30_days, data.previous_30_days);
		const base = `${data.last_30_days.converted} of ${data.last_30_days.new} became a quote or job`;
		return trend ? `${base} · ${trend}` : base;
	});

	// Every status a badge can show, calendar ones included, so picking one lists exactly the rows
	// wearing that badge.
	const statusOptions = [
		{ value: '', label: 'All' },
		...(Object.keys(REQUEST_STATUS_LABELS) as DisplayRequestStatus[]).map((value) => ({
			value,
			label: REQUEST_STATUS_LABELS[value]
		}))
	];

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});

	const sortSummary = $derived.by(() => {
		if (sortKey === 'title') return sortDir === 'asc' ? 'Title A to Z' : 'Title Z to A';
		return sortDir === 'asc' ? 'Oldest first' : 'Newest first';
	});

	// The street on one line, the town and region under it. A request with no property says so on the first line.
	function propertyStreet(property: RequestListItem['property']) {
		return property?.address_line1 || 'No property';
	}
	function propertyArea(property: RequestListItem['property']) {
		if (!property) return '';
		return [property.city, property.state_region].filter(Boolean).join(', ');
	}

	// When the assessment is, in the person's own time: the day ("Today", "Fri, Oct 17") with its hours
	// under it, or "Done Oct 10" once it has happened. A request with nothing booked says so.
	const dayFormat = new Intl.DateTimeFormat(undefined, {
		weekday: 'short',
		month: 'short',
		day: 'numeric'
	});
	const shortDayFormat = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });
	const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
	function isToday(date: Date) {
		return date.toDateString() === new Date().toDateString();
	}
	function assessmentText(request: RequestListItem) {
		const assessment = request.assessment;
		if (!assessment) return null;
		if (assessment.completed_at) {
			return { main: `Done ${shortDayFormat.format(new Date(assessment.completed_at))}`, sub: '' };
		}
		if (!assessment.starts_at) return null;
		const start = new Date(assessment.starts_at);
		const day = isToday(start) ? 'Today' : dayFormat.format(start);
		if (assessment.all_day) return { main: day, sub: 'All day' };
		const end = assessment.ends_at ? new Date(assessment.ends_at) : null;
		return {
			main: day,
			sub: end
				? `${timeFormat.format(start)} – ${timeFormat.format(end)}`
				: timeFormat.format(start)
		};
	}
	function clientName(request: RequestListItem) {
		return request.client?.display_name ?? 'Client removed';
	}

	function requestHref(request: RequestListItem) {
		return resolve('/(app)/requests/[id=uuid]', { id: request.id });
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client', width: '220px' },
		{ key: 'title', label: 'Request', sortable: true },
		{ key: 'property', label: 'Property', width: '180px' },
		{ key: 'assessment', label: 'Assessment', width: '140px' },
		{ key: 'requested', label: 'Requested', sortable: true, width: '108px' },
		{ key: 'status', label: 'Status', width: '150px' }
	];

	function prefetchRequest(item: { id: string }) {
		void queryClient.prefetchQuery({
			queryKey: requestDetailKey(item.id),
			queryFn: () => fetchRequest(item.id),
			staleTime: 30_000
		});
	}
</script>

<svelte:head><title>Requests · Contractor CRM</title></svelte:head>

<div class="page-scroller">
	<PageContainer variant="open">
		<PageHeader
			class="requests-page__header"
			eyebrow="Customers"
			title="Requests"
			description="Every job someone has asked you to look at."
		>
			{#snippet actions()}
				<span class="requests-header__action" title={moreActionsReason}>
					<Button variant="secondary" class="requests-header__button" disabled>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="requests-header__icon" aria-hidden="true">{@html dotsIcon}</span>
						More actions
					</Button>
					<span class="requests-header__reason">{moreActionsReason}</span>
				</span>
				<Button
					variant="primary"
					class="requests-header__button requests-header__button--primary"
					href={resolve('/(app)/requests/new')}
				>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span class="requests-header__icon" aria-hidden="true">{@html plusIcon}</span>
					New request
				</Button>
			{/snippet}
		</PageHeader>

		<div class="requests-overview">
			<AttentionCard
				title="Waiting on you"
				description="Requests that need a reply or a visit. Pick one to see only those requests."
				tiles={attentionTiles}
				selectedKey={selectedTile}
				onSelect={(key) => (status = key as DisplayRequestStatus | '')}
				loading={countsQuery.isPending}
			/>
			<MoneyFeatureCard
				eyebrow="Conversion · past 30 days"
				value={conversion.value}
				note={conversionNote}
				detailLabel="New requests · past 30 days"
				detailValue={countsQuery.data ? String(countsQuery.data.last_30_days.new) : '—'}
				loading={countsQuery.isPending}
			/>
		</div>

		{#if selectedIds.size > 0}
			<div class="requests-bulk-bar">
				<span>{selectedIds.size} selected</span>
				<span class="requests-bulk-bar__action" title={bulkReason}>
					<Button variant="secondary" size="small" disabled>Archive</Button>
					<span class="requests-bulk-bar__reason">{bulkReason}</span>
				</span>
			</div>
		{/if}

		<RecordListCard
			title="All requests"
			subtitle={sortSummary}
			padBody={requestsQuery.isPending || requestsQuery.isError || requests.length === 0}
		>
			{#snippet toolbar()}
				<div class="requests-card__search">
					<SearchInput
						id="requests-search"
						bind:value={search}
						placeholder="Search requests"
						size="compact"
					/>
				</div>
				<FilterChip
					id="requests-status-filter"
					variant="toolbar"
					icon={dashedCircleIcon}
					label="Status"
					value={status}
					options={statusOptions}
					restValue=""
					onchange={(value) => (status = value as DisplayRequestStatus | '')}
				/>
			{/snippet}

			{#if requestsQuery.isPending}
				<LoadingSkeleton variant="table" label="Loading requests" rows={5} />
			{:else if requestsQuery.isError}
				<ErrorState description="Requests could not be loaded. Refresh and try again." />
			{:else if requests.length === 0}
				<EmptyState
					icon={clipboardIcon}
					title={hasActiveFilters || debouncedSearch ? 'No matching requests' : 'No requests yet'}
					description={hasActiveFilters || debouncedSearch
						? 'Try a different search term or clear your filters.'
						: 'Work people ask you to look at will show up here.'}
				/>
			{:else}
				<DataTable
					variant="card"
					{columns}
					items={requests}
					rowId={(request) => request.id}
					caption="Requests"
					selectable
					bind:selectedIds
					rowLabel={(request) => `Select ${request.title}`}
					onRowHover={prefetchRequest}
					onRowActivate={(request) => goto(requestHref(request))}
					{sort}
					onSortChange={handleSortChange}
				>
					{#snippet row(request: RequestListItem)}
						{@const assessment = assessmentText(request)}
						<th scope="row">
							<div class="requests-table__client">
								<Avatar
									id={request.client?.id ?? request.id}
									name={clientName(request)}
									size="base"
								/>
								<div class="requests-table__client-text">
									<div class="requests-table__client-name">{clientName(request)}</div>
									{#if request.email ?? request.phone}
										<div class="requests-table__meta requests-table__meta--line">
											{request.email ?? request.phone}
										</div>
									{/if}
								</div>
							</div>
						</th>
						<td>
							<a class="requests-table__title" href={requestHref(request)}>{request.title}</a>
							{#if request.service_type}
								<div class="requests-table__meta">{request.service_type}</div>
							{/if}
						</td>
						<td>
							<div class="requests-table__street">{propertyStreet(request.property)}</div>
							{#if propertyArea(request.property)}
								<div class="requests-table__meta">{propertyArea(request.property)}</div>
							{/if}
						</td>
						<td class="requests-table__assessment">
							{#if assessment}
								<div class="requests-table__text">{assessment.main}</div>
								{#if assessment.sub}
									<div class="requests-table__meta">{assessment.sub}</div>
								{/if}
							{:else}
								<div class="requests-table__text requests-table__text--muted">Not booked</div>
							{/if}
						</td>
						<td class="requests-table__text">
							{dateFormat.format(new Date(request.requested_at))}
						</td>
						<td>
							<StatusBadge size="compact" status={REQUEST_STATUS_TONES[request.status]}>
								{REQUEST_STATUS_LABELS[request.status]}
							</StatusBadge>
						</td>
					{/snippet}
					{#snippet rowActions(request: RequestListItem)}
						<DropdownMenu
							items={[
								{ label: 'View request', onSelect: () => void goto(requestHref(request)) },
								{ label: 'Archive', onSelect: () => {}, disabled: true }
							]}
							triggerLabel={`Actions for ${request.title}`}
						/>
					{/snippet}
					{#snippet footer()}
						<ListLoadMore
							variant="card"
							label="Load more requests"
							hasNextPage={requestsQuery.hasNextPage}
							isFetchingNextPage={requestsQuery.isFetchingNextPage}
							onLoadMore={() => requestsQuery.fetchNextPage()}
							searchNarrowed={requestsQuery.data?.pages.at(-1)?.search_narrowed ?? false}
							narrowedLabel="Many requests match — type more to see the rest."
						/>
					{/snippet}
				</DataTable>
			{/if}
		</RecordListCard>
	</PageContainer>
</div>

<style lang="scss">
	/* The page header sits straight on the app background; the cards under it share one 24px rhythm. */
	:global(.requests-page__header) {
		margin-bottom: var(--space-large);
	}

	.requests-header__action,
	.requests-bulk-bar__action {
		position: relative;
		display: inline-flex;
	}

	.requests-header__reason,
	.requests-bulk-bar__reason {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}

	:global(.requests-header__button) {
		min-height: 44px;
		padding: 0 18px 0 14px;
		border-radius: 12px;
		border-color: var(--color-border);
		color: var(--color-text);
		gap: var(--space-small);
	}
	/* Unavailable, but still drawn as the white button it will become, so the header does not look half empty. */
	:global(.requests-header__button:disabled) {
		border-color: var(--color-border);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		opacity: 0.7;
	}
	:global(.requests-header__button--primary) {
		border-color: var(--color-interactive);
		color: var(--color-text--reverse);
		box-shadow: 0 6px 16px color-mix(in srgb, var(--color-interactive) 20%, transparent);
	}
	.requests-header__icon {
		display: inline-flex;

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	/* Waiting on you takes the room it needs; the conversion card keeps a steady width beside it. */
	.requests-overview {
		display: grid;
		gap: var(--space-large);
		grid-template-columns: minmax(0, 1fr) 336px;
		margin-bottom: var(--space-large);
	}

	.requests-bulk-bar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		margin-bottom: var(--space-large);
		padding: var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		font-weight: 600;
	}

	.requests-card__search {
		width: 260px;
		max-width: 100%;
	}

	.requests-table__client {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
	}
	.requests-table__client-text {
		min-width: 0;
	}
	/* An automatic table sizes a column to its widest nowrap line, so the cap is what lets a long email
	   shorten with an ellipsis instead of pushing the other columns narrow. */
	.requests-table__meta--line {
		max-width: 170px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.requests-table__client-name {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	/* The row's real navigation link — carries keyboard focus, new-tab and cmd-click, while a plain click
	   anywhere on the row still opens the request through the table's onRowActivate. */
	.requests-table__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;
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
	.requests-table__street {
		display: -webkit-box;
		overflow: hidden;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		color: var(--color-text);
		font-size: 13px;
		font-weight: 500;
	}
	.requests-table__meta {
		margin-top: 3px;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		overflow-wrap: anywhere;
	}
	.requests-table__text {
		color: var(--color-text);
		font-size: 13px;
		font-weight: 500;
	}
	.requests-table__text--muted {
		color: var(--color-text--secondary);
	}
	td.requests-table__text,
	.requests-table__assessment .requests-table__meta {
		white-space: nowrap;
	}

	@media (max-width: 1199px) {
		.requests-overview {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
