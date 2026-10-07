<script lang="ts">
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import { dndzone, TRIGGERS, type DndEvent } from 'svelte-dnd-action';
	import { flip } from 'svelte/animate';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import DealBoardCard from './DealBoardCard.svelte';
	import {
		DEAL_STAGE_HINTS,
		DEAL_STAGE_LABELS,
		dealColumnKey,
		fetchDealColumn,
		monthlyValue,
		type DealCard,
		type DealColumnPage,
		type OpenDealStage
	} from '$lib/jafar/deals';

	// Jafar business management B4: one stage of the Deals board. Each column owns its query and pages on its own
	// (30 at a time), so a busy stage never makes the others load again; the header's count and total come from
	// the board summary. A drop lands at once -- the card shows in its new column while the board saves or asks
	// for what the move needs -- and goes back if that is cancelled or refused.
	let {
		stage,
		count,
		totalCents,
		canChange,
		busy,
		today,
		resync,
		onDrop,
		onMove,
		onSharePricing,
		onLost,
		onPrefetchPackages
	}: {
		stage: OpenDealStage;
		count: number | undefined;
		totalCents: number | undefined;
		canChange: boolean;
		/** A move is saving or waiting in a dialog: nothing else can be dragged until it settles. */
		busy: boolean;
		today: string;
		/** Changes when the board wants every column back as the server last said. */
		resync: number;
		onDrop: (deal: DealCard, stage: OpenDealStage) => void;
		onMove: (deal: DealCard, stage: OpenDealStage) => void;
		onSharePricing: (deal: DealCard) => void;
		onLost: (deal: DealCard) => void;
		onPrefetchPackages: () => void;
	} = $props();

	const query = createInfiniteQuery(() => ({
		queryKey: dealColumnKey(stage),
		queryFn: ({ pageParam }: { pageParam: string | null }) => fetchDealColumn(stage, pageParam),
		initialPageParam: null as string | null,
		getNextPageParam: (page: DealColumnPage) => page.next_cursor ?? undefined,
		// Every Deal change invalidates the board itself; this only stops a quick walk away and back from
		// reloading six columns.
		staleTime: 30_000
	}));

	const cards = $derived(query.data?.pages.flatMap((page) => page.deals) ?? []);
	const headingId = $derived(`deal-column-${stage}`);
	const total = $derived(totalCents ? monthlyValue(totalCents) : null);

	// A drag-mutable copy of the column. It follows the query, and `resync` puts it back after a cancelled or
	// refused move; a drop changes it without touching either.
	let items = $state<DealCard[]>([]);
	$effect(() => {
		void resync;
		items = cards;
	});

	function handleConsider(event: CustomEvent<DndEvent<DealCard>>) {
		items = event.detail.items;
	}

	function handleFinalize(event: CustomEvent<DndEvent<DealCard>>) {
		if (event.detail.info.trigger === TRIGGERS.DROPPED_OUTSIDE_OF_ANY) {
			items = cards;
			return;
		}
		items = event.detail.items;
		// Only the column the card landed in acts; a reorder inside one column is not saved (the order is by date).
		const dropped = event.detail.items.find(
			(item) => item.id === event.detail.info.id && item.stage !== stage
		);
		if (dropped) onDrop(dropped, stage);
		else if (event.detail.items.some((item) => item.id === event.detail.info.id)) items = cards;
	}
</script>

<section class="deal-column" aria-labelledby={headingId}>
	<header class="deal-column__header">
		<div class="deal-column__heading">
			<h2 id={headingId}>{DEAL_STAGE_LABELS[stage]}</h2>
			{#if count !== undefined}<span class="deal-column__count">{count}</span>{/if}
		</div>
		<p class="deal-column__sub">
			{#if total}<strong>{total}</strong>{:else}{DEAL_STAGE_HINTS[stage]}{/if}
		</p>
	</header>

	{#if query.isPending}
		<div class="deal-column__cards">
			{#each { length: 2 }, index (index)}
				<LoadingSkeleton variant="card" label="Loading Deals" />
			{/each}
		</div>
	{:else if query.isError}
		<p class="deal-column__message deal-column__message--error">This stage could not be loaded.</p>
	{:else}
		<div class="deal-column__zone">
			<div
				class="deal-column__cards"
				use:dndzone={{
					items,
					flipDurationMs: 150,
					type: 'deal',
					dragDisabled: !canChange || busy,
					dropTargetStyle: {}
				}}
				onconsider={handleConsider}
				onfinalize={handleFinalize}
			>
				{#each items as deal (deal.id)}
					<div class="deal-column__card" animate:flip={{ duration: 150 }}>
						<DealBoardCard
							{deal}
							{canChange}
							{busy}
							{today}
							onMove={(target) => onMove(deal, target)}
							onSharePricing={() => onSharePricing(deal)}
							onLost={() => onLost(deal)}
							{onPrefetchPackages}
						/>
					</div>
				{/each}
			</div>
			{#if items.length === 0}
				<p class="deal-column__message">No Deals here</p>
			{/if}
		</div>
		{#if query.hasNextPage}
			<ListLoadMore
				hasNextPage={query.hasNextPage}
				isFetchingNextPage={query.isFetchingNextPage}
				onLoadMore={() => query.fetchNextPage()}
			/>
		{/if}
	{/if}
</section>

<style lang="scss">
	.deal-column {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		padding: var(--space-base) var(--space-slim);
		border-right: var(--border-base) solid var(--color-border);

		&:last-child {
			border-right: 0;
		}
	}

	.deal-column__header {
		display: grid;
		gap: var(--space-smallest);
		min-height: 44px;
		padding: 0 var(--space-smaller);
	}

	.deal-column__heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}

	h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
	}

	.deal-column__count {
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

	.deal-column__sub {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);

		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-variant-numeric: tabular-nums;
		}
	}

	// The zone fills the column, so an empty or short stage still takes a drop along its whole height.
	.deal-column__zone {
		position: relative;
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
	}

	.deal-column__cards {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		gap: var(--space-small);
		min-height: 96px;
		outline: none;
	}

	.deal-column__card {
		min-width: 0;
	}

	.deal-column__message {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: flex-start;
		justify-content: center;
		margin: 0;
		padding-top: var(--space-large);
		pointer-events: none;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--error {
			position: static;
			color: var(--color-critical--onSurface);
		}
	}
</style>
