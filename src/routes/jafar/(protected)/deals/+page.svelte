<script lang="ts">
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import layoutKanbanIcon from '@tabler/icons/outline/layout-kanban.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import DealColumn from '$lib/components/jafar/deals/DealColumn.svelte';
	import DealBoardCard from '$lib/components/jafar/deals/DealBoardCard.svelte';
	import DealStepDialog from '$lib/components/jafar/deals/DealStepDialog.svelte';
	import DealShareDialog from '$lib/components/jafar/deals/DealShareDialog.svelte';
	import DealLostDialog from '$lib/components/jafar/deals/DealLostDialog.svelte';
	import { canUseJafarPath } from '$lib/jafar/team-access';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		DEAL_STAGE_LABELS,
		OPEN_DEAL_STAGES,
		STAGES_NEEDING_DATE,
		dealColumnKey,
		dealSummaryKey,
		fetchDealColumn,
		fetchDealSummary,
		isoDate,
		monthlyValue,
		prefetchDealPackages,
		refreshDeals,
		type DealCard,
		type DealColumnPage,
		type OpenDealStage
	} from '$lib/jafar/deals';

	// Jafar business management B4: Uplift's buying conversations, one column per stage (plan § 4). Lost Deals
	// stay out of the way behind their own view. A move that needs something -- a date, the packages shared, a
	// reason -- asks for it first; the rest save straight away.

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const showLost = $derived(page.url.searchParams.get('view') === 'lost');
	const today = isoDate(new Date());

	const canChange = $derived(
		canUseJafarPath(
			{ role: page.data.owner.role, access: page.data.owner.access },
			'/api/jafar/deals/00000000-0000-0000-0000-000000000000',
			'PATCH'
		)
	);

	const summary = createQuery(() => ({
		queryKey: dealSummaryKey,
		queryFn: fetchDealSummary,
		staleTime: 30_000
	}));

	const openCount = $derived(
		Object.values(summary.data?.columns ?? {}).reduce((sum, column) => sum + column.count, 0)
	);
	const openValue = $derived(
		Object.values(summary.data?.columns ?? {}).reduce(
			(sum, column) => sum + column.value_monthly_usd_cents,
			0
		)
	);

	const lostList = createInfiniteQuery(() => ({
		queryKey: dealColumnKey('lost'),
		queryFn: ({ pageParam }: { pageParam: string | null }) => fetchDealColumn('lost', pageParam),
		initialPageParam: null as string | null,
		getNextPageParam: (lastPage: DealColumnPage) => lastPage.next_cursor ?? undefined,
		staleTime: 30_000,
		enabled: showLost
	}));
	const lostDeals = $derived(lostList.data?.pages.flatMap((entry) => entry.deals) ?? []);

	function showView(lost: boolean) {
		// eslint-disable-next-line svelte/no-navigation-without-resolve -- the path comes from resolve(); only the query string is added.
		void goto(`${resolve('/jafar/deals')}${lost ? '?view=lost' : ''}`, {
			keepFocus: true,
			noScroll: true
		});
	}

	// Warms the Lost view while its button is hovered, so opening it is instant.
	function prefetchLost() {
		void queryClient.prefetchInfiniteQuery({
			queryKey: dealColumnKey('lost'),
			queryFn: ({ pageParam }: { pageParam: string | null }) => fetchDealColumn('lost', pageParam),
			initialPageParam: null as string | null,
			staleTime: 30_000
		});
	}

	function prefetchPackages() {
		void prefetchDealPackages(queryClient);
	}

	// What the board is waiting on: a dialog for one Deal, or a move being saved. While it is set nothing else
	// can be dragged, and closing a dialog without saving puts every column back.
	type Pending =
		| { kind: 'step'; deal: DealCard; stage: OpenDealStage }
		| { kind: 'share'; deal: DealCard }
		| { kind: 'lost'; deal: DealCard };
	let pending = $state<Pending | null>(null);
	let saving = $state(false);
	let saved = false;
	let resync = $state(0);

	function begin(deal: DealCard, stage: OpenDealStage) {
		if (pending || saving || stage === deal.stage) return;
		saved = false;
		if (stage === 'pricing_shared') pending = { kind: 'share', deal };
		else if (STAGES_NEEDING_DATE.includes(stage)) pending = { kind: 'step', deal, stage };
		else void moveNow(deal, stage);
	}

	// Interested and Needs understood keep the Deal's next step, so they save at once.
	async function moveNow(deal: DealCard, stage: OpenDealStage) {
		saving = true;
		const result = await sendLeadWrite(`/api/jafar/deals/${encodeURIComponent(deal.id)}`, 'PATCH', {
			stage
		});
		if (result.ok) {
			await refreshDeals(queryClient, deal.relationship_id);
			toast.success(`${deal.business_name} moved to ${DEAL_STAGE_LABELS[stage]}`);
		} else {
			resync += 1;
			await refreshDeals(queryClient, deal.relationship_id).catch(() => undefined);
			toast.error('That Deal could not be moved.', result.error);
		}
		saving = false;
	}

	function closeDialog() {
		if (!saved) resync += 1;
		pending = null;
	}

	const pendingCurrent = $derived(
		pending?.deal.next_action && pending.deal.next_action_due_on
			? { text: pending.deal.next_action, due_on: pending.deal.next_action_due_on }
			: null
	);
</script>

<svelte:head><title>Deals · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="deals">
	<header class="deals__header">
		<div>
			<p class="deals__eyebrow">Business management</p>
			<h1>Deals</h1>
			<p class="deals__description">
				Businesses in a buying conversation with Uplift, from first interest to a decision.
			</p>
		</div>
		<div class="deals__header-actions">
			{#if showLost}
				<Button variant="secondary" onclick={() => showView(false)}>
					<span class="deals__button-icon" aria-hidden="true">{@html layoutKanbanIcon}</span>Open
					Deals
				</Button>
			{:else}
				<Button variant="secondary" onclick={() => showView(true)} onhover={prefetchLost}>
					<span class="deals__button-icon" aria-hidden="true">{@html archiveIcon}</span>Lost
					{#if summary.data}<span class="deals__count">{summary.data.lost}</span>{/if}
				</Button>
			{/if}
		</div>
	</header>

	{#if showLost}
		<section class="deals__lost" aria-labelledby="deals-lost-title">
			<div class="deals__lost-head">
				<h2 id="deals-lost-title">Lost Deals</h2>
				<p>Most recent first. Open one to see why it was lost or to reopen it.</p>
			</div>
			{#if lostList.isPending}
				<div class="deals__lost-grid">
					{#each { length: 6 }, index (index)}
						<LoadingSkeleton variant="card" label="Loading Lost Deals" />
					{/each}
				</div>
			{:else if lostList.isError}
				<ErrorState
					title="Lost Deals could not be loaded"
					description={lostList.error.message}
					retry={() => lostList.refetch()}
				/>
			{:else if lostDeals.length === 0}
				<EmptyState title="No Lost Deals" description="Deals marked Lost will be listed here." />
			{:else}
				<div class="deals__lost-grid">
					{#each lostDeals as deal (deal.id)}
						<DealBoardCard
							{deal}
							canChange={false}
							{today}
							onMove={() => undefined}
							onSharePricing={() => undefined}
							onLost={() => undefined}
							onPrefetchPackages={() => undefined}
						/>
					{/each}
				</div>
				{#if lostList.hasNextPage}
					<ListLoadMore
						hasNextPage={lostList.hasNextPage}
						isFetchingNextPage={lostList.isFetchingNextPage}
						onLoadMore={() => lostList.fetchNextPage()}
					/>
				{/if}
			{/if}
		</section>
	{:else}
		<p class="deals__summary" aria-live="polite">
			{#if summary.data}
				<strong>{openCount}</strong>
				{openCount === 1 ? 'open Deal' : 'open Deals'}{#if openValue > 0}<span
						class="deals__dot"
						aria-hidden="true">·</span
					><strong>{monthlyValue(openValue)}</strong> in prices shared{/if}
			{:else if summary.isError}
				The totals could not be loaded.
			{:else}
				&nbsp;
			{/if}
		</p>

		<div class="deals__board-wrap">
			<div class="deals__board">
				{#each OPEN_DEAL_STAGES as stage (stage)}
					<DealColumn
						{stage}
						count={summary.data ? (summary.data.columns[stage]?.count ?? 0) : undefined}
						totalCents={summary.data?.columns[stage]?.value_monthly_usd_cents}
						{canChange}
						busy={pending !== null || saving}
						{today}
						{resync}
						onDrop={begin}
						onMove={begin}
						onSharePricing={(deal) => begin(deal, 'pricing_shared')}
						onLost={(deal) => {
							saved = false;
							pending = { kind: 'lost', deal };
						}}
						onPrefetchPackages={prefetchPackages}
					/>
				{/each}
			</div>
		</div>
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

{#if pending?.kind === 'step'}
	<DealStepDialog
		action={{
			kind: 'move',
			dealId: pending.deal.id,
			relationshipId: pending.deal.relationship_id,
			stage: pending.stage
		}}
		businessName={pending.deal.business_name}
		current={pendingCurrent}
		onDone={() => (saved = true)}
		onClose={closeDialog}
	/>
{:else if pending?.kind === 'share'}
	<DealShareDialog
		dealId={pending.deal.id}
		relationshipId={pending.deal.relationship_id}
		businessName={pending.deal.business_name}
		onDone={() => (saved = true)}
		onClose={closeDialog}
	/>
{:else if pending?.kind === 'lost'}
	<DealLostDialog
		dealId={pending.deal.id}
		relationshipId={pending.deal.relationship_id}
		businessName={pending.deal.business_name}
		onDone={() => (saved = true)}
		onClose={closeDialog}
	/>
{/if}

<style lang="scss">
	.deals {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.deals h1,
	.deals h2,
	.deals p {
		margin: 0;
	}

	.deals h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.deals__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.deals__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.deals__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.deals__header-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.deals__button-icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	.deals__count {
		min-width: 22px;
		margin-left: var(--space-small);
		padding: 0 var(--space-smaller);
		border-radius: var(--radius-circle);
		background: var(--color-inactive--surface);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: 22px;
		text-align: center;
	}

	.deals__summary {
		min-height: 24px;
		padding: 0 var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		strong {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-variant-numeric: tabular-nums;
		}
	}

	.deals__dot {
		margin: 0 var(--space-small);
	}

	// Six stages side by side; on a narrower screen the board scrolls sideways and each column keeps its width.
	.deals__board-wrap {
		overflow-x: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
		box-shadow: var(--shadow-low);
		overscroll-behavior-x: contain;
		scroll-snap-type: x proximity;
	}

	.deals__board {
		display: grid;
		grid-template-columns: repeat(6, minmax(248px, 1fr));
		min-height: 60vh;

		> :global(*) {
			scroll-snap-align: start;
		}
	}

	.deals__lost {
		display: grid;
		gap: var(--space-base);
	}

	.deals__lost-head {
		display: grid;
		gap: var(--space-smaller);

		h2 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
		}

		p {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	.deals__lost-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
		gap: var(--space-base);
	}

	@media (max-width: 767px) {
		.deals__header {
			flex-direction: column;
		}

		.deals__board {
			grid-template-columns: repeat(6, minmax(78vw, 1fr));
		}
	}

	@media (max-width: 639px) {
		.deals h1 {
			font-size: 28px;
		}
	}
</style>
