<script module lang="ts">
	import { setKeyboardDragTrigger } from 'svelte-dnd-action';
	// Global to the document, per the library's own contract -- narrowed once, here, so Enter stays free
	// for `OpportunityCard`'s "open the Brief" handler instead of also starting a keyboard drag.
	setKeyboardDragTrigger('space');
</script>

<script lang="ts">
	import { createInfiniteQuery, useQueryClient } from '@tanstack/svelte-query';
	import { dndzone, TRIGGERS, type DndEvent } from 'svelte-dnd-action';
	import { flip } from 'svelte/animate';
	import { tick } from 'svelte';
	import OpportunityCard from './OpportunityCard.svelte';
	import ScheduleAssessmentDialog from './ScheduleAssessmentDialog.svelte';
	import AssessmentEntryChoiceDialog from './AssessmentEntryChoiceDialog.svelte';
	import ConvertToQuoteDialog from './ConvertToQuoteDialog.svelte';
	import TaskDialog from './TaskDialog.svelte';
	import SendQuoteDialog from '$lib/components/quotes/SendQuoteDialog.svelte';
	import clockPauseIcon from '@tabler/icons/outline/clock-pause.svg?raw';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		boardColumnKey,
		dragOpportunity,
		invalidatePipeline,
		fetchBoardColumn,
		placeOpportunity,
		undoOpportunityMove,
		undoOpportunityPlacement,
		DragWriteError,
		NEEDS_FUTURE_TASK,
		type BoardColumnPage,
		type OpportunityCard as Card
	} from '$lib/pipeline/api';
	import type { MoveTarget } from '$lib/pipeline/moves';
	import {
		ALL_STAGE_LABELS,
		ASSESSMENT_GROUP,
		BOARD_COLUMN_LABELS,
		boardColumnId,
		boardColumnRequestKey,
		isAnyBoardStage,
		stageSection,
		stagesInColumn,
		type AnyBoardStage,
		type BoardColumn,
		type CustomStage,
		type OpportunityStage
	} from '$lib/pipeline/stages';
	import {
		dragActionFor,
		allowedDragTargets,
		DRAG_ACTIONS_NEEDING_INPUT,
		DRAG_ACTIONS_NEEDING_CONFIRMATION
	} from '$lib/pipeline/transitions';
	import { formatMoney, type BoardFormatting } from '$lib/pipeline/money';
	import { activityKey } from '$lib/collaboration/api';
	import type { QuoteSendChoice } from '$lib/quotes/send';
	import type { BoardFilters } from '$lib/pipeline/filters';
	import type { InactivityRules } from '$lib/pipeline/freshness';

	// One column owns one query. A busy stage can keep loading its next page without making the other
	// three fetch again, and the header count comes from the board summary rather than from this query,
	// so paging never re-counts the board.
	let {
		column,
		count,
		valueTotal,
		filters,
		formatting,
		canEdit,
		customStages = [],
		inactivityRules = null,
		onOpen,
		onLost,
		dragging,
		onDraggingChange,
		dragBusy,
		onDragBusyChange
	}: {
		// A protected column, or a custom follow-up stage an owner or administrator added in Settings.
		column: BoardColumn;
		count: number | undefined;
		// Undefined while the summary is still answering or this member may not see money; null when nobody
		// has estimated anything in this column, which is not zero and never prints as $0.00.
		valueTotal: number | null | undefined;
		filters: BoardFilters;
		formatting: BoardFormatting | null;
		canEdit: boolean;
		// Every custom follow-up stage on the board, so a card's Move menu can list them.
		customStages?: readonly CustomStage[];
		// What a card's inactivity warning is measured against. Null until the board summary answers.
		inactivityRules?: InactivityRules | null;
		onOpen: (card: Card) => void;
		onLost?: (opportunityId: string) => void;
		// The card currently being dragged, board-wide, or null between gestures: its real stage, and the
		// custom stage it was sitting in if any. Every column reads this to decide whether it may accept a
		// drop from somewhere else -- there is no other way for a sibling column to know a drag is even
		// happening.
		dragging: { stage: OpportunityStage; customStageId: string | null } | null;
		onDraggingChange: (
			dragging: { stage: OpportunityStage; customStageId: string | null } | null
		) => void;
		// A protected move is confirmed one at a time. While its dialog is open or its server action is
		// saving, every zone stays still so the same source-of-truth card cannot start a second gesture.
		dragBusy: boolean;
		onDragBusyChange: (busy: boolean) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// The protected column this is, or null for a custom follow-up stage. A custom stage holds the cards
	// somebody placed in it; each one keeps its real stage underneath, which is what a real action moves.
	const stage = $derived(column.kind === 'protected' ? column.key : null);
	const customStage = $derived(column.kind === 'custom' ? column.stage : null);
	const columnId = $derived(boardColumnId(column));
	const label = $derived(
		column.kind === 'protected' ? BOARD_COLUMN_LABELS[column.key] : column.stage.name
	);

	const query = createInfiniteQuery(() => ({
		// The filters are in the key, so changing a control asks a new question rather than reusing the
		// answer to the old one, and paging restarts from the top of the new order on its own.
		queryKey: boardColumnKey(columnId, filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchBoardColumn(boardColumnRequestKey(column), filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (page: BoardColumnPage) => page.next_cursor ?? undefined,
		// Cards only move when a Request or Assessment moves, and both of those invalidate this key
		// themselves. Half a minute stops a walk back and forth between pages from re-fetching four
		// columns every time, without letting the board go quietly out of date.
		staleTime: 30_000
	}));

	const cards = $derived(query.data?.pages.flatMap((page) => page.opportunities) ?? []);
	const headingId = $derived(`pipeline-column-${columnId}`);
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

	// How long a toast offering Undo stays up. Long enough to notice a slip and reach the button; the
	// countdown also stops while the toast is hovered or focused.
	const UNDO_TOAST_MS = 8000;

	// The one card mid-schedule-dialog, or null the rest of the time. The card stays in its query-confirmed
	// source column while this tracks which record the dialog is deciding the fate of. `pendingCardTarget`
	// is the real stage the dialog will actually commit to: the column a card was dropped on, the stage
	// picked in a card's Move menu, or `assessment_scheduled` when the schedule dialog was reached through
	// the collapsed group's own choice dialog below.
	let pendingCard = $state<Card | null>(null);
	let pendingCardTarget = $state<AnyBoardStage | null>(null);
	// A New request dropped on the collapsed Assessment column: which real sub-state it enters is not
	// implied by the drop alone, so this holds the card while the two-choice dialog decides.
	let pendingChoice = $state<Card | null>(null);
	// A card headed for Draft, naming the client and the request before the irreversible conversion runs.
	let pendingConvert = $state<Card | null>(null);
	// A Draft quote headed for Awaiting response. The send window is open for it; the card moves only once
	// the quote has really been emailed or deliberately marked as sent some other way. The key is minted
	// once per drop, so a retried email after a dropped response is recognised as the same send.
	let pendingSend = $state<{ card: Card; quoteId: string; idempotencyKey: string } | null>(null);
	// A card an on-hold stage refused for having no follow-up Task with a future date. The Task dialog is
	// open for it; saving the Task finishes the move into that stage.
	let pendingHold = $state<{ card: Card; stage: CustomStage } | null>(null);

	// Whether a card is one of this column's own: placed in this custom stage, or sitting in one of this
	// protected column's real stages with no custom placement.
	function belongsHere(card: Card) {
		if (customStage) return card.custom_stage_id === customStage.id;
		// Widened from `AnyBoardStage[]` to `OpportunityStage[]` -- a superset, so the comparison still only
		// ever matches a genuine board stage.
		const realStages: readonly OpportunityStage[] = stage ? stagesInColumn(stage) : [];
		return card.custom_stage_id === null && realStages.includes(card.stage);
	}

	// Whether a card currently being dragged out of a different column may land here at all.
	//
	// A custom stage takes every drop and answers in `handleFinalize`: a card from the wrong side of the
	// Request/Quote line is handed straight back with the reason, which a zone that silently refused the
	// drop could never say.
	//
	// A protected column allows two things. A card whose real stage is already here -- the drag started
	// in this very column, or the card is coming home from a custom stage. And a card whose real stage the
	// transition table can advance to a stage this column represents. `true` -- refuse the drop -- for
	// everything else, including any move the table simply never mentions (backward, cross-group, or
	// otherwise not a real domain command).
	const dropRefused = $derived.by(() => {
		if (dragging === null || stage === null) return false;
		const realStages: readonly OpportunityStage[] = stagesInColumn(stage);
		if (realStages.includes(dragging.stage)) return false;
		return !allowedDragTargets(dragging.stage).some((target) => realStages.includes(target));
	});

	function handleConsider(event: CustomEvent<DndEvent<Card>>) {
		items = event.detail.items;
		if (event.detail.info.trigger === TRIGGERS.DRAG_STARTED) {
			const dragged = event.detail.items.find((item) => item.id === event.detail.info.id);
			if (dragged) {
				onDraggingChange({ stage: dragged.stage, customStageId: dragged.custom_stage_id });
			}
		}
	}

	async function handleFinalize(event: CustomEvent<DndEvent<Card>>) {
		onDraggingChange(null);

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
			(item) => item.id === event.detail.info.id && !belongsHere(item)
		);
		items = cards;
		if (!dropped) return;

		// A custom stage is follow-up organization only, so the drop is the whole move -- no dialog and no
		// domain action. The one thing it refuses is a card from the other side of the Request/Quote line.
		if (customStage) {
			const cardSection = stageSection(dropped.stage);
			if (cardSection !== customStage.section) {
				toast.error(
					`That card cannot go into ${customStage.name}.`,
					cardSection === 'request'
						? 'This is a request, so it can only go into a Requests stage. Convert it to a quote first.'
						: 'This is a quote, so it can only go into a Quotes stage.'
				);
				return;
			}
			await performPlace(dropped, customStage.id);
			return;
		}
		if (stage === null) return;

		// Coming home: the card was in a custom stage and this column is the real stage it never left.
		// Nothing about the Request or Quote changes, so there is no action to perform -- only the
		// placement to clear.
		if (dropped.custom_stage_id !== null && belongsHereOnceUnplaced(dropped)) {
			await performPlace(dropped, null);
			return;
		}

		// From here on the drop asks for a real action, measured from the card's real stage -- the same
		// action whether the card was dragged out of that stage's own column or out of a custom stage. Once
		// it succeeds the real stage changes, and the database lets go of the custom placement by itself.
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

		// `dropRefused` already keeps a disallowed target from accepting the drop in the first place, and
		// `beginStageMove` checks again before anything is asked of the server.
		await beginStageMove(dropped, stage);
	}

	// A card asked to enter a real stage, by a drop or from its Move menu. Each stage's own action decides
	// what happens first: the send window, the schedule dialog, the conversion confirmation, or nothing.
	// Measured from the card's real stage -- the same action whether the card sat in that stage's own
	// column or in a custom stage. Once it succeeds the real stage changes, and the database lets go of
	// the custom placement by itself.
	async function beginStageMove(card: Card, toStage: AnyBoardStage) {
		const action = dragActionFor(card.stage, toStage);
		// Never trust the client copy: a move the table does not know is not asked of the server.
		if (!action) return;

		if (action === 'quote_publish') {
			if (!card.quote) return;
			pendingSend = { card, quoteId: card.quote.id, idempotencyKey: crypto.randomUUID() };
			onDragBusyChange(true);
			return;
		}

		if (DRAG_ACTIONS_NEEDING_INPUT.includes(action)) {
			pendingCard = card;
			pendingCardTarget = toStage;
			onDragBusyChange(true);
			return;
		}

		if (DRAG_ACTIONS_NEEDING_CONFIRMATION.includes(action)) {
			pendingConvert = card;
			onDragBusyChange(true);
			return;
		}

		await performMove(card, toStage);
	}

	// The card's Move menu. It names a real stage outright, so even on the collapsed board there is no
	// "which Assessment state" question to ask.
	function moveFromMenu(card: Card, target: MoveTarget) {
		if (dragBusy) return;
		if (target.kind === 'stage') return beginStageMove(card, target.stage);
		return performPlace(card, target.kind === 'custom' ? target.customStageId : null);
	}

	// After a move the card is redrawn in another column, which would leave a keyboard user's focus
	// nowhere. Put it back on the card wherever it now is; a card that left the board has nothing to find.
	// A move confirmed in a dialog calls this again once that dialog has closed: while it is open it keeps
	// focus inside itself, and on closing it hands focus back to the Move button of a card that has gone.
	// The frame's wait lets that hand-back happen first.
	async function focusCard(cardId: string) {
		await tick();
		await new Promise((resolve) => requestAnimationFrame(resolve));
		document
			.querySelector<HTMLElement>(`[data-opportunity-id="${cardId}"] .opportunity-card__open`)
			?.focus();
	}

	function belongsHereOnceUnplaced(card: Card) {
		const realStages: readonly OpportunityStage[] = stage ? stagesInColumn(stage) : [];
		return realStages.includes(card.stage);
	}

	// Places a card in a custom stage, or back in its real stage with null. Shared by a drop and by the
	// card's own menu, so both lock the board, save, and report in exactly the same way. The card stays
	// where it is until the server has answered and the board has re-read.
	async function performPlace(card: Card, customStageId: string | null) {
		const destination = customStageId
			? customStages.find((candidate) => candidate.id === customStageId)?.name
			: isAnyBoardStage(card.stage)
				? ALL_STAGE_LABELS[card.stage]
				: undefined;
		onDragBusyChange(true);
		const loadingToastId = toast.loading('Saving change…');
		try {
			const result = await placeOpportunity(card.id, customStageId);
			await invalidatePipeline(queryClient);
			toast.dismiss(loadingToastId);
			const title = destination ? `Moved to ${destination}.` : 'Change saved.';
			if (result.applied) {
				toast.show({
					variant: 'success',
					title,
					duration: UNDO_TOAST_MS,
					action: {
						label: 'Undo',
						onSelect: () =>
							void performUndo(card, () => undoOpportunityPlacement(card.id, customStageId))
					}
				});
			} else {
				toast.success(title);
			}
			void focusCard(card.id);
		} catch (error) {
			items = cards;
			// An on-hold stage wants a follow-up Task first. That is something the person can fix right here,
			// so the board asks for the Task instead of only refusing; the board stays locked behind the
			// dialog, exactly as it does for the schedule and convert dialogs.
			const holdStage =
				error instanceof DragWriteError && error.code === NEEDS_FUTURE_TASK
					? customStages.find((candidate) => candidate.id === customStageId)
					: undefined;
			if (holdStage) {
				toast.dismiss(loadingToastId);
				pendingHold = { card, stage: holdStage };
				return;
			}
			// A response can be lost after the server commits. Re-read truth before reporting the failure so
			// the card never lies about where the server ultimately left it.
			await invalidatePipeline(queryClient).catch(() => undefined);
			toast.dismiss(loadingToastId);
			toast.error(
				'That card could not be moved.',
				error instanceof Error ? error.message : undefined
			);
		} finally {
			if (pendingHold === null) onDragBusyChange(false);
		}
	}

	// The follow-up Task now exists, so the move the stage refused is simply asked for again.
	async function finishHold() {
		if (!pendingHold) return;
		const { card, stage: holdStage } = pendingHold;
		pendingHold = null;
		await performPlace(card, holdStage.id);
	}

	function cancelHold() {
		if (pendingHold) void focusCard(pendingHold.card.id);
		pendingHold = null;
		items = cards;
		onDragBusyChange(false);
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
			const title = `Moved to ${ALL_STAGE_LABELS[toStage]}.`;
			const undo = result.undo;
			if (undo) {
				// A reversible move: the server said so, and will check again when Undo is pressed.
				toast.show({
					variant: 'success',
					title,
					duration: UNDO_TOAST_MS,
					action: {
						label: 'Undo',
						onSelect: () =>
							void performUndo(card, () => undoOpportunityMove(card.id, { ...result, undo }))
					}
				});
			} else {
				toast.success(
					title,
					result.quote ? `Quote #${result.quote.quote_number} created.` : undefined
				);
			}
			void focusCard(card.id);
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

	// Takes back the move the toast was about: a real move or a custom-stage placement, each through its own
	// request. The server undoes it only while it is still the last thing that happened to the card, and
	// puts the card's clocks back with it — and, for a real move, the assessment and the Request.
	async function performUndo(
		card: Card,
		undo: () => Promise<{ stage: OpportunityStage; custom_stage_id: string | null }>
	) {
		onDragBusyChange(true);
		const loadingToastId = toast.loading('Undoing…');
		try {
			const result = await undo();
			await invalidatePipeline(queryClient);
			toast.dismiss(loadingToastId);
			const home =
				customStages.find((candidate) => candidate.id === result.custom_stage_id)?.name ??
				(isAnyBoardStage(result.stage) ? ALL_STAGE_LABELS[result.stage] : null);
			toast.success(home ? `Moved back to ${home}.` : 'Move undone.');
			void focusCard(card.id);
		} catch (error) {
			await invalidatePipeline(queryClient).catch(() => undefined);
			toast.dismiss(loadingToastId);
			toast.error(
				'That move could not be undone.',
				error instanceof Error ? error.message : undefined
			);
		} finally {
			onDragBusyChange(false);
		}
	}

	async function confirmScheduledMove(startsAt: string, endsAt: string) {
		if (!pendingCard || !pendingCardTarget) return;
		try {
			const card = pendingCard;
			await performMove(card, pendingCardTarget, startsAt, endsAt, true);
			pendingCard = null;
			pendingCardTarget = null;
			void focusCard(card.id);
		} catch (error) {
			// The dialog remains open with its field/server error, so the board remains locked until the user
			// retries successfully or cancels it.
			onDragBusyChange(true);
			throw error;
		}
	}

	function cancelScheduledMove() {
		if (pendingCard) void focusCard(pendingCard.id);
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
		if (pendingChoice) void focusCard(pendingChoice.id);
		pendingChoice = null;
		items = cards;
		onDragBusyChange(false);
	}

	async function confirmConvert() {
		if (!pendingConvert) return;
		try {
			// Converting only ever leads to Draft, whichever column or menu asked for it.
			const card = pendingConvert;
			await performMove(card, 'quote_draft', undefined, undefined, true, crypto.randomUUID());
			pendingConvert = null;
			void focusCard(card.id);
		} catch (error) {
			onDragBusyChange(true);
			throw error;
		}
	}

	function cancelConvert() {
		if (pendingConvert) void focusCard(pendingConvert.id);
		pendingConvert = null;
		items = cards;
		onDragBusyChange(false);
	}

	// The send window's own write. The window stays open, and the board locked behind it, until this
	// succeeds; a refusal is thrown back for the window to show, with the quote still a Draft.
	async function confirmSend(choice: QuoteSendChoice, expectedRevision: number) {
		if (!pendingSend) return;
		const { card, quoteId, idempotencyKey } = pendingSend;
		try {
			await dragOpportunity(card.id, {
				toStage: 'quote_awaiting_response',
				idempotencyKey,
				send: { ...choice, expectedRevision }
			});
		} catch (error) {
			// A response can be lost after the server commits. Re-read truth so the card never lies about
			// where the server ultimately left it.
			await invalidatePipeline(queryClient).catch(() => undefined);
			throw error;
		}
		// The quote itself changed, not only the card: its page, the Quotes list and counts, and its history.
		await Promise.all([
			invalidatePipeline(queryClient),
			queryClient.invalidateQueries({ queryKey: ['quotes'] }),
			queryClient.invalidateQueries({ queryKey: activityKey('quote', quoteId) })
		]);
		pendingSend = null;
		onDragBusyChange(false);
		toast.success(
			choice.method === 'email' ? 'Quote emailed to the customer.' : 'Quote marked as sent.',
			'Moved to Awaiting response.'
		);
		void focusCard(card.id);
	}

	function cancelSend() {
		if (pendingSend) void focusCard(pendingSend.card.id);
		pendingSend = null;
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
			<h3 id={headingId}>
				{label}
				{#if customStage?.requires_future_task}
					<span
						class="pipeline-column__hold"
						role="img"
						aria-label="On hold stage: cards need a task with a future due date"
						title="On hold stage: cards need a task with a future due date"
					>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html clockPauseIcon}
					</span>
				{/if}
			</h3>
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
							showStageBadge={stage === ASSESSMENT_GROUP || customStage !== null}
							{customStages}
							{inactivityRules}
							onMove={(target) => void moveFromMenu(card, target)}
							moveBusy={dragBusy}
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
			timezone={formatting?.timezone}
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

	{#if pendingHold}
		<TaskDialog
			open={true}
			opportunityId={pendingHold.card.id}
			futureDueFor={pendingHold.stage.name}
			timezone={formatting?.timezone}
			onSaved={finishHold}
			onClose={cancelHold}
		/>
	{/if}

	{#if pendingSend}
		<SendQuoteDialog
			open={true}
			quoteId={pendingSend.quoteId}
			onSend={confirmSend}
			onClose={cancelSend}
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
	.pipeline-column__hold {
		display: inline-grid;
		place-items: center;
		margin-left: var(--space-smaller);
		color: var(--color-icon--secondary);
		vertical-align: text-bottom;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
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
