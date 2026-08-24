<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PipelineColumn from '$lib/components/pipeline/PipelineColumn.svelte';
	import OpportunityBriefDrawer from '$lib/components/pipeline/OpportunityBriefDrawer.svelte';
	import BoardControls from '$lib/components/pipeline/BoardControls.svelte';
	import OutcomeTile from '$lib/components/pipeline/OutcomeTile.svelte';
	import {
		boardCountsKey,
		fetchBoardSummary,
		outcomeTilesKey,
		fetchOutcomeTiles,
		type OpportunityCard as Card
	} from '$lib/pipeline/api';
	import {
		boardFilterParams,
		filtersAreComplete,
		filtersAreDefault,
		readBoardFilters,
		type BoardFilters
	} from '$lib/pipeline/filters';
	import {
		BOARD_STAGES,
		QUOTE_BOARD_STAGES,
		REQUEST_COLUMNS_COLLAPSED,
		REQUEST_COLUMNS_DETAILED,
		QUOTE_COLUMNS,
		type OpportunityStage
	} from '$lib/pipeline/stages';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import fileInvoiceIcon from '@tabler/icons/outline/file-invoice.svg?raw';

	// The board. Part 1 draws the Requests group only: the Quotes group and the money it carries arrive
	// with Part 5, and the Won and Lost tiles with outcomes in Part 4, so there is room left for both
	// rather than a placeholder standing in for them.
	//
	// Nothing here creates work. A card appears because a Request exists, and it moves because that
	// Request moved.
	let selected = $state<Card | null>(null);

	// The one piece of state a drag actually needs to share across columns: which stage a card is being
	// pulled out of, so every other column can tell whether it may accept the drop. Nothing else about a
	// drag crosses a column boundary -- each column still owns its own cards and its own write.
	let draggingFromStage = $state<OpportunityStage | null>(null);
	// A dropped card stays in its confirmed column while its protected action is being collected or saved.
	// Locking the board during that short window prevents a second gesture from racing the same server truth.
	let dragBusy = $state(false);

	// The Brief edits an opportunity in place. The board behind it refetches itself on every write, but
	// `selected` is a snapshot from the moment the card was clicked — nothing else brings it back into
	// view, so a successful edit patches it here directly.
	function updateSelected(patch: Partial<Card>) {
		if (selected) selected = { ...selected, ...patch };
	}

	// Mark as lost can be fired from a card in the column while that same card's Brief sits open behind
	// it. The board refetches and drops the card on its own; the Brief holds a separate snapshot that
	// nothing else would think to close.
	function closeSelectedIfLost(opportunityId: string) {
		if (selected?.id === opportunityId) selected = null;
	}

	// The URL is the board's memory. Everything the controls set lives there and nowhere else, which is what
	// makes a refresh and the back button work without a line of code for either.
	const urlFilters = $derived(readBoardFilters(page.url.searchParams));

	// What the board is actually asking about. It differs from the URL in one case only: a custom range with
	// neither end chosen yet is not a question the API will answer, so the range simply is not applied until
	// a day is picked. Everything else the person filtered by still counts in the meantime.
	//
	// This is derived, never held in state and written from an effect. An effect runs after the render that
	// read it, which left the summary a tick behind the columns — on the back button the cards came back
	// filtered while the counts, totals and result line still described the board you had just left.
	const applied = $derived<BoardFilters>(
		filtersAreComplete(urlFilters)
			? urlFilters
			: { ...urlFilters, date: 'all', from: undefined, to: undefined }
	);

	function setFilters(next: BoardFilters) {
		const params = boardFilterParams(next);
		const query = params.toString();
		// Each change is its own history entry, so Back steps through the filters the way it steps through
		// pages. Focus stays where it was, and the board does not jump to the top.
		void goto(`${page.url.pathname}${query ? `?${query}` : ''}`, {
			keepFocus: true,
			noScroll: true
		});
	}

	const summaryQuery = createQuery(() => ({
		queryKey: boardCountsKey(applied),
		queryFn: () => fetchBoardSummary(applied),
		// Same window as the columns, so the headings and the cards under them never disagree about
		// how fresh they are.
		staleTime: 30_000
	}));

	// The Won/Lost tiles: a fixed rolling 30 days, never the board's own salesperson or date controls, so
	// this is its own query rather than riding along with the filtered summary above.
	const tilesQuery = createQuery(() => ({
		queryKey: outcomeTilesKey,
		queryFn: fetchOutcomeTiles,
		staleTime: 30_000
	}));

	function outcomeHref(type: 'won' | 'lost') {
		const params = new URLSearchParams({ type, date: 'last_30_days' });
		return `${resolve('/(app)/pipeline/outcomes')}?${params.toString()}`;
	}

	// A refused board is refused for one of two reasons, and they need different words: the plan does
	// not include the pipeline, or this person is not allowed to see it. Anything else is a failure.
	const refusal = $derived.by(() => {
		const error = summaryQuery.error as (Error & { status?: number; reason?: string }) | null;
		if (!error || error.status !== 403) return null;
		return error.reason === 'feature_unavailable' ? 'feature' : 'permission';
	});

	const counts = $derived(summaryQuery.data?.counts ?? null);
	// How this organization writes money and dates. Null until the summary answers, so nothing is
	// briefly formatted the browser's way and then corrected.
	const formatting = $derived(
		summaryQuery.data
			? {
					currency_code: summaryQuery.data.currency_code,
					locale: summaryQuery.data.locale,
					timezone: summaryQuery.data.timezone
				}
			: null
	);
	const requestsTotal = $derived(
		counts ? BOARD_STAGES.reduce((total, stage) => total + counts[stage], 0) : null
	);
	const quotesTotal = $derived(
		counts ? QUOTE_BOARD_STAGES.reduce((total, stage) => total + counts[stage], 0) : null
	);
	const canViewValue = $derived(summaryQuery.data?.can_view_value ?? false);
	const canEdit = $derived(summaryQuery.data?.can_edit ?? false);
	// Absent from the payload entirely for a member without money, so there is nothing to guard against here.
	const valueTotals = $derived(summaryQuery.data?.value_totals ?? null);
	const isFiltered = $derived(!filtersAreDefault(applied));
	// Which board this organization shows: the five-column default with one collapsed Assessment column,
	// or the seven-column detailed view. Presentation only -- rides on the same summary query the board
	// already holds, so saving the Settings toggle changes the board without a reload.
	const detailedAssessmentStages = $derived(summaryQuery.data?.detailed_assessment_stages ?? false);
	const requestColumns = $derived(
		detailedAssessmentStages ? REQUEST_COLUMNS_DETAILED : REQUEST_COLUMNS_COLLAPSED
	);

	// An empty board and a filter that matched nothing are different answers and must not look the same:
	// only a genuinely empty board gets the new-account message. A filtered board with no matches keeps its
	// columns and its controls, so the person can see what they asked for and change it.
	const boardIsEmpty = $derived(requestsTotal === 0 && quotesTotal === 0 && !isFiltered);

	// The board's own horizontal scrollbar sits at the bottom of `.pipeline__board`, which grows as tall as
	// the longest column's cards -- reaching it would mean scrolling the whole page down first. A second,
	// pinned strip mirrors the same scroll position from a fixed spot near the bottom of the viewport, so
	// it stays reachable regardless of how many cards a column holds. `.pipeline__board`'s own scrollbar
	// stays fully functional (wheel, trackpad, keyboard) -- only its visible track is hidden in CSS, so
	// this is a second control on the same scroll position, not a replacement for it.
	let boardViewport = $state<HTMLDivElement | null>(null);
	let pinnedTrack = $state<HTMLDivElement | null>(null);
	let pinnedBarHeight = $state(0);
	let boardScrollWidth = $state(0);
	let boardClientWidth = $state(0);
	const pinnedScrollbarVisible = $derived(boardScrollWidth > boardClientWidth + 1);

	function measureBoard() {
		if (!boardViewport) return;
		boardScrollWidth = boardViewport.scrollWidth;
		boardClientWidth = boardViewport.clientWidth;
	}

	// Two different reasons the board's width can change: the viewport itself resizing (window resize, the
	// sidebar collapsing) and the content resizing while the viewport does not (columns added by the
	// detailed-stages toggle, or more cards loaded into a column). A `ResizeObserver` on the scroll
	// container alone only ever catches the first one -- overflowing content does not change its own box
	// size. The `MutationObserver` catches the second by re-measuring whenever a card or column is added
	// or removed anywhere under it.
	$effect(() => {
		if (!boardViewport) return;
		const resize = new ResizeObserver(measureBoard);
		resize.observe(boardViewport);
		const mutation = new MutationObserver(measureBoard);
		mutation.observe(boardViewport, { childList: true, subtree: true });
		measureBoard();
		return () => {
			resize.disconnect();
			mutation.disconnect();
		};
	});

	// The pinned strip starts wherever the real board already is -- otherwise it would silently reset the
	// scroll position the moment it first appears (e.g. right after the detailed-stages toggle adds enough
	// columns to overflow).
	$effect(() => {
		if (pinnedTrack && boardViewport) pinnedTrack.scrollLeft = boardViewport.scrollLeft;
	});

	// Both scrollbars move the same one position; each handler only ever answers the gesture that started
	// on it, so the two never fight over the position on every frame.
	let syncingScroll = false;
	function handleBoardScroll() {
		if (syncingScroll || !boardViewport || !pinnedTrack) return;
		syncingScroll = true;
		pinnedTrack.scrollLeft = boardViewport.scrollLeft;
		syncingScroll = false;
	}
	function handlePinnedScroll() {
		if (syncingScroll || !boardViewport || !pinnedTrack) return;
		syncingScroll = true;
		boardViewport.scrollLeft = pinnedTrack.scrollLeft;
		syncingScroll = false;
	}

	// Sorting by value is reading value, and the route refuses it. A link carrying `sort=value` into the
	// hands of someone who may not see money would break all four columns, so the board quietly drops back
	// to its default order as soon as the summary says which world this member is in.
	$effect(() => {
		if (summaryQuery.data && !canViewValue && urlFilters.sort === 'value') {
			setFilters({ ...urlFilters, sort: 'stage', direction: 'desc' });
		}
	});
</script>

<svelte:head><title>Pipeline</title></svelte:head>

<div class="page-scroller">
	<PageContainer>
		<div class="pipeline">
			<PageHeader
				title="Pipeline"
				description="Every open request, in the order it moves through your sales work."
			>
				{#snippet actions()}
					<div class="pipeline__tiles">
						<OutcomeTile
							label="Won"
							variant="won"
							count={tilesQuery.data?.won.count ?? 0}
							valueTotal={tilesQuery.data?.won.value_total}
							formatting={tilesQuery.data ?? null}
							href={outcomeHref('won')}
						/>
						<OutcomeTile
							label="Lost"
							variant="lost"
							count={tilesQuery.data?.lost.count ?? 0}
							valueTotal={tilesQuery.data?.lost.value_total}
							formatting={tilesQuery.data ?? null}
							href={outcomeHref('lost')}
						/>
					</div>
				{/snippet}
			</PageHeader>

			{#if refusal === 'feature'}
				<EmptyState
					title="Pipeline is not part of your plan"
					description="Ask your account owner to add it, and every open request will show up here."
				/>
			{:else if refusal === 'permission'}
				<EmptyState
					title="You do not have access to the pipeline"
					description="Ask an owner or admin to give you pipeline access."
				/>
			{:else if summaryQuery.isError}
				<ErrorState
					title="The pipeline could not be loaded"
					description="Something went wrong on our side. Try again."
					retry={() => summaryQuery.refetch()}
				/>
			{:else if boardIsEmpty}
				<EmptyState
					title="Nothing in the pipeline yet"
					description="Requests land here the moment they come in, and move along as you book and finish assessments."
				/>
			{:else}
				<BoardControls
					filters={urlFilters}
					resultCount={summaryQuery.data?.result_count ?? null}
					{canViewValue}
					onChange={setFilters}
				/>

				<!-- One journey, left to right: both groups scroll together as a single board rather than each
				     wrapping its own columns onto a second row -- Requests and Quotes keep a useful fixed column
				     width and the board grows sideways instead of compressing five (or seven) columns to fit. -->
				<div class="pipeline__board" bind:this={boardViewport} onscroll={handleBoardScroll}>
					<SectionBlock title="Requests" icon={inboxIcon} class="pipeline__group">
						{#snippet actions()}
							<span class="pipeline__total">
								{requestsTotal ?? '—'}
								<span class="pipeline__total-label">open</span>
							</span>
						{/snippet}

						<div class="pipeline__columns">
							{#each requestColumns as stage (stage)}
								<PipelineColumn
									{stage}
									count={counts?.[stage]}
									valueTotal={valueTotals?.[stage]}
									filters={applied}
									{formatting}
									{canEdit}
									onOpen={(card) => (selected = card)}
									onLost={closeSelectedIfLost}
									{draggingFromStage}
									onDragStageChange={(stage) => (draggingFromStage = stage)}
									{dragBusy}
									onDragBusyChange={(busy) => (dragBusy = busy)}
								/>
							{/each}
						</div>
					</SectionBlock>

					<!-- The subtle boundary the contract calls for: two bordered, titled groups sitting side by
					     side already read as separate journeys without a second decorative element. -->
					<SectionBlock title="Quotes" icon={fileInvoiceIcon} class="pipeline__group">
						{#snippet actions()}
							<span class="pipeline__total">
								{quotesTotal ?? '—'}
								<span class="pipeline__total-label">open</span>
							</span>
						{/snippet}

						<div class="pipeline__columns">
							{#each QUOTE_COLUMNS as stage (stage)}
								<PipelineColumn
									{stage}
									count={counts?.[stage]}
									valueTotal={valueTotals?.[stage]}
									filters={applied}
									{formatting}
									{canEdit}
									onOpen={(card) => (selected = card)}
									onLost={closeSelectedIfLost}
									{draggingFromStage}
									onDragStageChange={(stage) => (draggingFromStage = stage)}
									{dragBusy}
									onDragBusyChange={(busy) => (dragBusy = busy)}
								/>
							{/each}
						</div>
					</SectionBlock>
				</div>

				{#if pinnedScrollbarVisible}
					<div
						class="pipeline__pinned-scrollbar-spacer"
						style={`height: calc(${pinnedBarHeight}px + var(--space-base))`}
						aria-hidden="true"
					></div>
				{/if}
			{/if}
		</div>
	</PageContainer>
</div>

{#if pinnedScrollbarVisible}
	<!-- A pointer/trackpad convenience only -- `.pipeline__board` itself already carries the real
	     scrollable content and remains reachable by wheel, trackpad, and its own (visually hidden)
	     scrollbar, so this mirror is hidden from assistive tech rather than offered as a second way in. -->
	<div
		class="pipeline__pinned-scrollbar"
		bind:this={pinnedTrack}
		bind:clientHeight={pinnedBarHeight}
		onscroll={handlePinnedScroll}
		aria-hidden="true"
	>
		<div class="pipeline__pinned-scrollbar-track" style={`width: ${boardScrollWidth}px`}></div>
	</div>
{/if}

<OpportunityBriefDrawer
	opportunity={selected}
	{formatting}
	{canEdit}
	onClose={() => (selected = null)}
	onUpdate={updateSelected}
/>

<style lang="scss">
	.pipeline {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	// Won/Lost live in the page header's actions slot: PageHeader already splits copy and actions with
	// space-between, so the tiles park at the far right of the title.
	.pipeline__tiles {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 220px));
		gap: var(--space-base);
	}
	@media (max-width: 639px) {
		.pipeline__tiles {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	// One board, one scroll: both groups sit in a single horizontal-scrolling row so Requests and Quotes
	// always read as one journey rather than two independently wrapping panels.
	.pipeline__board {
		display: flex;
		// Both groups stretch to the taller one's height, so Requests and Quotes always end on the same
		// line rather than whichever group's busiest column happens to have fewer cards today.
		align-items: stretch;
		gap: var(--space-large);
		overflow-x: auto;
		// This scrollbar stays fully functional -- wheel, trackpad, and keyboard all still move it -- only
		// its own visible track is hidden, because `.pipeline__pinned-scrollbar` below is the one meant to
		// be grabbed with a mouse: it stays reachable at the bottom of the viewport, while this one sits at
		// the bottom of a box that can grow to any height.
		scrollbar-width: none;
		&::-webkit-scrollbar {
			display: none;
		}
	}
	// Reserves the room `.pipeline__pinned-scrollbar` actually floats over, the same technique
	// `StickyActionBar` uses -- otherwise the fixed strip would sit on top of the last visible content
	// once the page is scrolled all the way down.
	.pipeline__pinned-scrollbar-spacer {
		flex: 0 0 auto;
	}
	// The reachable scrollbar: pinned to the bottom of the viewport rather than sticky within the page, so
	// it stays in the same spot regardless of how tall the board gets -- the same reasoning
	// `StickyActionBar` documents for its own bar, and the same published `AppShell` edges so it lines up
	// with the page underneath it.
	.pipeline__pinned-scrollbar {
		position: fixed;
		right: var(--shell-content-right, var(--space-large));
		bottom: var(--shell-edge, var(--space-large));
		left: var(--shell-content-left, var(--space-large));
		z-index: var(--elevation-menu);
		padding: 6px var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		overflow-x: auto;
		overflow-y: hidden;
		transition:
			left var(--timing-base) ease-out,
			right var(--timing-base) ease-out;
	}
	// Gives the strip a real native scrollbar sized to the actual board: same scroll width, so the thumb
	// is proportioned the same way the board's own (hidden) scrollbar would have been.
	.pipeline__pinned-scrollbar-track {
		height: 1px;
	}
	// A group's own width is the sum of its fixed-width columns -- it never shrinks to fit the viewport,
	// which is what pushes the board into horizontal scroll instead of compressing every column. `:global`
	// because this class only lands on `SectionBlock`'s own root element through its `class` prop -- the
	// compiler cannot see that pass-through and would otherwise prune the rule as unused.
	.pipeline__board :global(.pipeline__group) {
		flex: 0 0 auto;
	}
	// The columns grow with their cards and the page does the scrolling vertically; horizontally each one
	// keeps a useful fixed width instead of stretching or compressing to fill the group. `flex: 1 1 auto`
	// is what actually carries the equalized group height (above) down into the columns themselves -- a
	// shorter group's drop zones extend to fill it rather than leaving blank space under a short row.
	.pipeline__columns {
		display: flex;
		flex: 1 1 auto;
		align-items: stretch;
	}
	.pipeline__columns :global(.pipeline-column) {
		flex: 0 0 280px;
	}
	// The rules belong to the board, not to a column: a column cannot know whether it has one beside it.
	.pipeline__columns :global(.pipeline-column + .pipeline-column) {
		border-left: var(--border-base) solid var(--color-border);
	}
	.pipeline__total {
		display: inline-flex;
		align-items: baseline;
		gap: 6px;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.pipeline__total-label {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}
	// Below this width a 280px column leaves too little of the next one in view to read as "more to
	// scroll to" -- narrowing the column keeps that affordance instead of widening the scrollable area.
	@media (max-width: 639px) {
		.pipeline__columns :global(.pipeline-column) {
			flex-basis: 240px;
		}
	}
</style>
