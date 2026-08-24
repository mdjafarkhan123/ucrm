<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { dndzone, TRIGGERS, type DndEvent } from 'svelte-dnd-action';
	import { flip } from 'svelte/animate';
	import OpportunityCard from './OpportunityCard.svelte';
	import ScheduleAssessmentDialog from './ScheduleAssessmentDialog.svelte';
	import AssessmentEntryChoiceDialog from './AssessmentEntryChoiceDialog.svelte';
	import ConvertToQuoteDialog from './ConvertToQuoteDialog.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		boardColumnKey,
		dragOpportunity,
		invalidatePipeline,
		fetchBoardColumn,
		type BoardColumnPage,
		type OpportunityCard as Card
	} from '$lib/pipeline/api';
	import {
		ASSESSMENT_GROUP,
		BOARD_COLUMN_LABELS,
		stagesInColumn,
		type AnyBoardStage,
		type BoardColumnKey,
		type OpportunityStage
	} from '$lib/pipeline/stages';
	import {
		dragActionFor,
		allowedDragTargets,
		DRAG_ACTIONS_NEEDING_INPUT,
		DRAG_ACTIONS_NEEDING_CONFIRMATION
	} from '$lib/pipeline/transitions';
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
		onLost,
		draggingFromStage,
		onDragStageChange,
		dragBusy,
		onDragBusyChange
	}: {
		stage: BoardColumnKey;
		count: number | undefined;
		// Undefined while the summary is still answering or this member may not see money; null when nobody
		// has estimated anything in this column, which is not zero and never prints as $0.00.
		valueTotal: number | null | undefined;
		filters: BoardFilters;
		formatting: BoardFormatting | null;
		canEdit: boolean;
		onOpen: (card: Card) => void;
		onLost?: (opportunityId: string) => void;
		// The stage a card is currently being dragged out of, board-wide, or null between gestures. Every
		// column reads this to decide whether it may accept a drop from somewhere else -- there is no other
		// way for a sibling column to know a drag is even happening.
		draggingFromStage: OpportunityStage | null;
		onDragStageChange: (stage: OpportunityStage | null) => void;
		// A protected move is confirmed one at a time. While its dialog is open or its server action is
		// saving, every zone stays still so the same source-of-truth card cannot start a second gesture.
		dragBusy: boolean;
		onDragBusyChange: (busy: boolean) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

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

	// The board's cards, mirrored into a drag-mutable copy. This one-way sync from the query is what settles
	// every drag back to truth: a successful move invalidates the board, the query refetches, `cards` gets a
	// new array, and this effect overwrites whatever the drag gesture left behind -- correct order, correct
	// stage, correct everything -- without this column having to reconcile anything itself. Assigning `items`
	// elsewhere (the drag handlers below) never re-triggers this effect, since it only tracks `cards`.
	let items = $state<Card[]>([]);
	$effect(() => {
		items = cards;
	});

	// The one card mid-schedule-dialog, or null the rest of the time. The card stays in its query-confirmed
	// source column while this tracks which record the dialog is deciding the fate of. `pendingCardTarget`
	// is the real stage the dialog will actually commit to -- usually just `stage`, except when the
	// schedule dialog was reached through the collapsed group's own choice dialog below, where `stage` is
	// the logical `assessment` key and the real target is `assessment_scheduled`.
	let pendingCard = $state<Card | null>(null);
	let pendingCardTarget = $state<AnyBoardStage | null>(null);
	// A New request dropped on the collapsed Assessment column: which real sub-state it enters is not
	// implied by the drop alone, so this holds the card while the two-choice dialog decides.
	let pendingChoice = $state<Card | null>(null);
	// A card dropped on Draft, naming the client and the request before the irreversible conversion runs.
	let pendingConvert = $state<Card | null>(null);

	// Whether a card currently being dragged out of a different column may land here at all. The first
	// check recognises "this drag started in this very column" for both a real column (its own single
	// stage) and the collapsed group (any of its three) -- always allowed, same as a plain reorder. The
	// second checks whether the transition table reaches any stage this column actually represents.
	// `true` -- refuse the drop -- for everything else, including any move the table simply never
	// mentions (backward, cross-group, or otherwise not a real domain command).
	const dropRefused = $derived.by(() => {
		if (draggingFromStage === null) return false;
		// Widened from `AnyBoardStage[]` to `OpportunityStage[]` -- a superset, so every real comparison
		// below still only ever matches a genuine board stage.
		const inThisColumn: readonly OpportunityStage[] = stagesInColumn(stage);
		if (inThisColumn.includes(draggingFromStage)) return false;
		return !allowedDragTargets(draggingFromStage).some((target) => inThisColumn.includes(target));
	});

	function handleConsider(event: CustomEvent<DndEvent<Card>>) {
		items = event.detail.items;
		if (event.detail.info.trigger === TRIGGERS.DRAG_STARTED) {
			const dragged = event.detail.items.find((item) => item.id === event.detail.info.id);
			if (dragged) onDragStageChange(dragged.stage);
		}
	}

	async function handleFinalize(event: CustomEvent<DndEvent<Card>>) {
		onDragStageChange(null);

		// The gesture ended without landing in any zone that would accept it -- a refused column, or a
		// release off any drop target. svelte-dnd-action is supposed to hand the card back to its origin
		// zone's own items on this trigger, but a fast real drag can race its polling-based zone-enter/leave
		// detection and drop the card from every zone's local list instead. Resync from the query's own
		// truth rather than trust the library's local list, so a refused move always reappears in place
		// instead of vanishing until the next reload.
		if (event.detail.info.trigger === TRIGGERS.DROPPED_OUTSIDE_OF_ANY) {
			items = cards;
			return;
		}

		// A card just settled here that did not start here -- everything else (a plain reorder, or the drag
		// returning to its own column) needs no action at all. Restore every involved zone from query truth
		// first: the card does not really leave its source stage until the domain action succeeds.
		const dropped = event.detail.items.find(
			(item) => item.id === event.detail.info.id && item.stage !== stage
		);
		items = cards;
		if (!dropped) return;

		const fromStage = dropped.stage;

		// The collapsed Assessment column has no single real stage of its own -- only a New request drop
		// has an approved way in, and even that is ambiguous (unscheduled or scheduled) until the person
		// answers the choice dialog. Every other card that lands here started inside the group already
		// (a same-column reorder `dropRefused` already lets through) and has no drag-based advancement:
		// that is the Brief's next action, not a drop.
		if (stage === ASSESSMENT_GROUP) {
			if (fromStage === 'new_request') {
				pendingChoice = dropped;
				onDragBusyChange(true);
			}
			return;
		}

		const action = dragActionFor(fromStage, stage);
		// `dropRefused` already keeps a disallowed target from accepting the drop in the first place; this
		// is only a second, never-trust-the-client-copy check. If it ever disagrees, undo the visual move
		// rather than ask the server to perform an action this column does not recognise.
		if (!action) {
			return;
		}

		if (DRAG_ACTIONS_NEEDING_INPUT.includes(action)) {
			pendingCard = dropped;
			pendingCardTarget = stage;
			onDragBusyChange(true);
			return;
		}

		if (DRAG_ACTIONS_NEEDING_CONFIRMATION.includes(action)) {
			pendingConvert = dropped;
			onDragBusyChange(true);
			return;
		}

		await performMove(dropped, stage);
	}

	async function performMove(
		card: Card,
		toStage: AnyBoardStage,
		startsAt?: string,
		endsAt?: string,
		rethrow = false,
		idempotencyKey?: string
	) {
		onDragBusyChange(true);
		const loadingToastId = toast.loading('Saving change…');
		try {
			const result = await dragOpportunity(card.id, { toStage, startsAt, endsAt, idempotencyKey });
			// Success means both the server action and the board's confirmed read have finished. Until then,
			// the card remains in its original column and the loading toast stays visible.
			await invalidatePipeline(queryClient);
			toast.dismiss(loadingToastId);
			toast.success(
				result.quote
					? `Change saved. Quote #${result.quote.quote_number} created.`
					: 'Change saved.'
			);
		} catch (error) {
			items = cards;
			// A response can be lost after the server commits. Re-read truth before reporting the failure so
			// the card never lies about where the server ultimately left it.
			await invalidatePipeline(queryClient).catch(() => undefined);
			toast.dismiss(loadingToastId);
			toast.error(
				'That card could not be moved.',
				error instanceof Error ? error.message : undefined
			);
			if (rethrow) throw error;
		} finally {
			onDragBusyChange(false);
		}
	}

	async function confirmScheduledMove(startsAt: string, endsAt: string) {
		if (!pendingCard || !pendingCardTarget) return;
		try {
			await performMove(pendingCard, pendingCardTarget, startsAt, endsAt, true);
			pendingCard = null;
			pendingCardTarget = null;
		} catch (error) {
			// The dialog remains open with its field/server error, so the board remains locked until the user
			// retries successfully or cancels it.
			onDragBusyChange(true);
			throw error;
		}
	}

	function cancelScheduledMove() {
		pendingCard = null;
		pendingCardTarget = null;
		items = cards;
		onDragBusyChange(false);
	}

	// The choice dialog's "Schedule" answer does not collect a time itself -- it hands the same card to
	// the existing schedule dialog, aimed at the real `assessment_scheduled` stage rather than the
	// collapsed column's logical key.
	function chooseSchedule() {
		if (!pendingChoice) return;
		pendingCard = pendingChoice;
		pendingCardTarget = 'assessment_scheduled';
		pendingChoice = null;
	}

	async function chooseAddWithoutScheduling() {
		if (!pendingChoice) return;
		const card = pendingChoice;
		pendingChoice = null;
		await performMove(card, 'assessment_unscheduled');
	}

	function cancelChoice() {
		pendingChoice = null;
		items = cards;
		onDragBusyChange(false);
	}

	async function confirmConvert() {
		if (!pendingConvert) return;
		try {
			// `pendingConvert` is only ever set from the non-group branch of `handleFinalize`, where `stage`
			// has already been narrowed away from the logical `assessment` key -- TypeScript cannot see that
			// narrowing across this separate function, but it holds by construction.
			await performMove(
				pendingConvert,
				stage as AnyBoardStage,
				undefined,
				undefined,
				true,
				crypto.randomUUID()
			);
			pendingConvert = null;
		} catch (error) {
			onDragBusyChange(true);
			throw error;
		}
	}

	function cancelConvert() {
		pendingConvert = null;
		items = cards;
		onDragBusyChange(false);
	}

	const convertClientName = $derived(
		pendingConvert?.client?.company_name?.trim() ||
			pendingConvert?.client?.display_name ||
			'this client'
	);
</script>

<section class="pipeline-column" aria-labelledby={headingId}>
	<header class="pipeline-column__header">
		<div class="pipeline-column__heading">
			<h3 id={headingId}>{BOARD_COLUMN_LABELS[stage]}</h3>
			{#if count !== undefined}
				<span class="pipeline-column__count">{count}</span>
			{/if}
		</div>
		{#if total}
			<p class="pipeline-column__total">{total}</p>
		{/if}
	</header>

	{#if query.isPending}
		<div class="pipeline-column__cards">
			{#each { length: 3 }, index (index)}
				<LoadingSkeleton variant="card" label="Loading opportunities" />
			{/each}
		</div>
	{:else if query.isError}
		<div class="pipeline-column__cards">
			<p class="pipeline-column__message pipeline-column__message--error">
				This column could not be loaded.
			</p>
		</div>
	{:else}
		<!-- The zone wrapper is what actually stretches to fill the column -- .pipeline-column__cards is the
		     real dndzone element inside it, so its droppable area covers the full column height, not just the
		     strip its cards occupy. Only real cards live inside the drop zone itself -- svelte-dnd-action
		     tracks its direct children against `items` one for one, so a decorative message there would throw
		     that count off. The empty-state text is positioned over it from the wrapper instead. -->
		<div class="pipeline-column__zone">
			<div
				class="pipeline-column__cards"
				use:dndzone={{
					items,
					flipDurationMs: 150,
					dragDisabled: !canEdit || pendingCard !== null || dragBusy,
					dropFromOthersDisabled: dropRefused
				}}
				onconsider={handleConsider}
				onfinalize={handleFinalize}
			>
				{#each items as card (card.id)}
					<div class="pipeline-column__card" animate:flip={{ duration: 150 }}>
						<OpportunityCard
							opportunity={card}
							{formatting}
							{canEdit}
							showStageBadge={stage === ASSESSMENT_GROUP}
							onOpen={() => onOpen(card)}
							{onLost}
						/>
					</div>
				{/each}
			</div>
			{#if items.length === 0}
				<p class="pipeline-column__message">Nothing here.</p>
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

	{#if pendingCard}
		<ScheduleAssessmentDialog
			open={true}
			title={`Schedule the assessment - ${pendingCard.title}`}
			onConfirm={confirmScheduledMove}
			onClose={cancelScheduledMove}
		/>
	{/if}

	{#if pendingChoice}
		<AssessmentEntryChoiceDialog
			open={true}
			title={`Add to Assessment - ${pendingChoice.title}`}
			onSchedule={chooseSchedule}
			onAddWithoutScheduling={chooseAddWithoutScheduling}
			onClose={cancelChoice}
		/>
	{/if}

	{#if pendingConvert}
		<ConvertToQuoteDialog
			open={true}
			clientName={convertClientName}
			requestTitle={pendingConvert.title}
			onConfirm={confirmConvert}
			onClose={cancelConvert}
		/>
	{/if}
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
	// Fills whatever height the grid gave this column beyond its header, so the dndzone inside it (below) can
	// in turn fill the same space -- a short or empty column stays droppable across its full visible height,
	// not just the strip its own cards happen to occupy.
	.pipeline-column__zone {
		position: relative;
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
	}
	.pipeline-column__cards {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		gap: var(--space-small);
		// An empty column still needs real droppable area, not a zero-height zone nothing can be dropped onto.
		min-height: 40px;
	}
	// A plain wrapper so svelte-dnd-action has a real box per item to move during a drag, and `animate:flip`
	// has a DOM node to target -- neither can attach directly to a component tag.
	.pipeline-column__card {
		min-width: 0;
	}
	.pipeline-column__message {
		// Overlays the now-tall (possibly empty) drop zone instead of sitting below it, so "Nothing here."
		// reads as a status of the zone rather than trailing content under a lot of empty space.
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		// The zone underneath still owns the drop -- the message is a label over it, not a target itself.
		pointer-events: none;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;

		&--error {
			position: static;
			inset: auto;
			color: var(--color-critical--onSurface);
		}
	}
</style>
