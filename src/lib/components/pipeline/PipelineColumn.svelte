<script lang="ts">
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import OpportunityCard from './OpportunityCard.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		boardColumnKey,
		fetchBoardColumn,
		type BoardColumnPage,
		type OpportunityCard as Card
	} from '$lib/pipeline/api';
	import { BOARD_STAGE_LABELS, type BoardStage } from '$lib/pipeline/stages';
	import { formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import type { BoardFilters } from '$lib/pipeline/filters';

	// One column owns one query. A busy stage can keep loading its next page without making the other
	// three fetch again, and the header count comes from the board summary rather than from this query,
	// so paging never re-counts the board.
	let {
		stage,
		count,
		valueTotal,
		filters,
		formatting,
		canEdit,
		onOpen,
		onLost
	}: {
		stage: BoardStage;
		count: number | undefined;
		// Undefined while the summary is still answering or this member may not see money; null when nobody
		// has estimated anything in this column, which is not zero and never prints as $0.00.
		valueTotal: number | null | undefined;
		filters: BoardFilters;
		formatting: BoardFormatting | null;
		canEdit: boolean;
		onOpen: (card: Card) => void;
		onLost?: (opportunityId: string) => void;
	} = $props();

	const query = createInfiniteQuery(() => ({
		// The filters are in the key, so changing a control asks a new question rather than reusing the
		// answer to the old one, and paging restarts from the top of the new order on its own.
		queryKey: boardColumnKey(stage, filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchBoardColumn(stage, filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: BoardColumnPage) => page.next_cursor ?? undefined,
		// Cards only move when a Request or Assessment moves, and both of those invalidate this key
		// themselves. Half a minute stops a walk back and forth between pages from re-fetching four
		// columns every time, without letting the board go quietly out of date.
		staleTime: 30_000
	}));

	const cards = $derived(query.data?.pages.flatMap((page) => page.opportunities) ?? []);
	const headingId = $derived(`pipeline-column-${stage}`);
	// Only when there is real money in the column and somewhere to write it in this organization's currency.
	// Nothing estimated means nothing shown, never a zero.
	const total = $derived(
		valueTotal === undefined || valueTotal === null || !formatting
			? null
			: formatMoney(valueTotal, formatting)
	);
</script>

<section class="pipeline-column" aria-labelledby={headingId}>
	<header class="pipeline-column__header">
		<div class="pipeline-column__heading">
			<h3 id={headingId}>{BOARD_STAGE_LABELS[stage]}</h3>
			{#if count !== undefined}
				<span class="pipeline-column__count">{count}</span>
			{/if}
		</div>
		{#if total}
			<p class="pipeline-column__total">{total}</p>
		{/if}
	</header>

	<div class="pipeline-column__cards">
		{#if query.isPending}
			{#each { length: 3 }, index (index)}
				<LoadingSkeleton variant="card" label="Loading opportunities" />
			{/each}
		{:else if query.isError}
			<p class="pipeline-column__message pipeline-column__message--error">
				This column could not be loaded.
			</p>
		{:else if cards.length === 0}
			<p class="pipeline-column__message">Nothing here.</p>
		{:else}
			{#each cards as card (card.id)}
				<OpportunityCard
					opportunity={card}
					{formatting}
					{canEdit}
					onOpen={() => onOpen(card)}
					{onLost}
				/>
			{/each}
			{#if query.hasNextPage}
				<ListLoadMore
					hasNextPage={query.hasNextPage}
					isFetchingNextPage={query.isFetchingNextPage}
					onLoadMore={() => query.fetchNextPage()}
				/>
			{/if}
		{/if}
	</div>
</section>

<style lang="scss">
	.pipeline-column {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		padding: var(--space-base) var(--space-slim);
	}
	.pipeline-column__header {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
	}
	.pipeline-column__heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.pipeline-column__total {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}
	h3 {
		min-width: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
	}
	.pipeline-column__count {
		flex: 0 0 auto;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.pipeline-column__cards {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.pipeline-column__message {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--error {
			color: var(--color-critical--onSurface);
		}
	}
</style>
