<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PipelineColumn from '$lib/components/pipeline/PipelineColumn.svelte';
	import OpportunityBriefDrawer from '$lib/components/pipeline/OpportunityBriefDrawer.svelte';
	import BoardControls from '$lib/components/pipeline/BoardControls.svelte';
	import {
		boardCountsKey,
		fetchBoardSummary,
		type OpportunityCard as Card
	} from '$lib/pipeline/api';
	import {
		boardFilterParams,
		filtersAreComplete,
		filtersAreDefault,
		readBoardFilters,
		type BoardFilters
	} from '$lib/pipeline/filters';
	import { BOARD_STAGES } from '$lib/pipeline/stages';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';

	// The board. Part 1 draws the Requests group only: the Quotes group and the money it carries arrive
	// with Part 5, and the Won and Lost tiles with outcomes in Part 4, so there is room left for both
	// rather than a placeholder standing in for them.
	//
	// Nothing here creates work. A card appears because a Request exists, and it moves because that
	// Request moved.
	let selected = $state<Card | null>(null);

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
	const canViewValue = $derived(summaryQuery.data?.can_view_value ?? false);
	// Absent from the payload entirely for a member without money, so there is nothing to guard against here.
	const valueTotals = $derived(summaryQuery.data?.value_totals ?? null);
	const isFiltered = $derived(!filtersAreDefault(applied));

	// An empty board and a filter that matched nothing are different answers and must not look the same:
	// only a genuinely empty board gets the new-account message. A filtered board with no matches keeps its
	// columns and its controls, so the person can see what they asked for and change it.
	const boardIsEmpty = $derived(requestsTotal === 0 && !isFiltered);

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

<PageContainer>
	<div class="pipeline">
		<PageHeader
			title="Pipeline"
			description="Every open request, in the order it moves through your sales work."
		/>

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

			<SectionBlock title="Requests" icon={inboxIcon} class="pipeline__group">
				{#snippet actions()}
					<span class="pipeline__total">
						{requestsTotal ?? '—'}
						<span class="pipeline__total-label">open</span>
					</span>
				{/snippet}

				<div class="pipeline__columns">
					{#each BOARD_STAGES as stage (stage)}
						<PipelineColumn
							{stage}
							count={counts?.[stage]}
							valueTotal={valueTotals?.[stage]}
							filters={applied}
							{formatting}
							onOpen={(card) => (selected = card)}
						/>
					{/each}
				</div>
			</SectionBlock>
		{/if}
	</div>
</PageContainer>

<OpportunityBriefDrawer opportunity={selected} {formatting} onClose={() => (selected = null)} />

<style lang="scss">
	.pipeline {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}
	// The columns grow with their cards and the page does the scrolling, so a long column never hides
	// its own bottom behind a second scrollbar.
	.pipeline__columns {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		align-items: start;
	}
	// The rules belong to the board, not to a column: a column cannot know whether it has one beside it.
	.pipeline__columns :global(section + section) {
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
	@media (max-width: 1079px) {
		.pipeline__columns {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
</style>
