<script lang="ts">
	import CalendarWeekGrid, {
		type WeekGridGhost
	} from '$lib/components/calendar/CalendarWeekGrid.svelte';
	import VisitCard from '$lib/components/schedule/VisitCard.svelte';
	import AssessmentCard from '$lib/components/schedule/AssessmentCard.svelte';
	import EventCard from '$lib/components/schedule/EventCard.svelte';
	import TaskCard from '$lib/components/schedule/TaskCard.svelte';
	import { bucketVisitsByDay } from '$lib/schedule/grouping';
	import { type AssessmentItem, type EventItem, type ScheduleItem } from '$lib/schedule/items';
	import { earliestWorkingMinute, weekdayOf, type WorkingWeek } from '$lib/schedule/hours';
	import {
		cardDensity,
		layoutTimedVisits,
		MINUTES_IN_DAY,
		splitDayVisits
	} from '$lib/schedule/layout';
	import { eachDayInWindow, type ScheduleWindow } from '$lib/schedule/filters';
	import { WEEK_HOUR_PX, type ScheduleZoom } from '$lib/schedule/density';
	import {
		canDragVisit,
		draftAnytime,
		draftFromClick,
		draftFromRange,
		proposeMove,
		proposeResize,
		shiftDay,
		snapMinutes,
		SNAP_MINUTES,
		type DropTarget,
		type NewVisitDraft,
		type ScheduleProposal
	} from '$lib/schedule/drag';
	import { startPointerDrag } from '$lib/schedule/pointer-drag';
	import { anchorAtPoint, type PopoverAnchor } from '$lib/components/ui/popover-anchor';
	import { clockLabel } from '$lib/schedule/labels';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';

	// The week, as seven day columns over one shared time axis. The frame is the shared CalendarWeekGrid; this
	// draws the contractor's cards into it and owns dragging.
	//
	// Dragging works on coordinates rather than drop targets, because the grid the pointer lands on is
	// painted and has no elements to drop onto. Each day column and each Anytime cell is measured, and the
	// arithmetic that turns a position into a proposal lives in `$lib/schedule/drag`, where it is tested.

	let {
		window: activeWindow,
		items,
		today,
		nowMinutes,
		workingWeek,
		employeesById,
		selectedItemId,
		canSchedule = false,
		canCreate = false,
		movingVisitId = null,
		zoom = 'compact',
		unscheduleZone = null,
		onselect,
		onselectassessment,
		onselectevent,
		onpropose,
		oncreate,
		onunschedule
	}: {
		window: ScheduleWindow;
		/** Already filtered by the page. Every one of these is drawn -- visits and assessments alike. */
		items: ScheduleItem[];
		today: string;
		/** Minutes past midnight in the contractor's own timezone, or null when today is not in this week. */
		nowMinutes: number | null;
		/** Null when the business has no confirmed weekly pattern, so nothing is shaded. */
		workingWeek: WorkingWeek | null;
		employeesById: Map<string, TeamMember>;
		selectedItemId: string | null;
		/** Whether this reader may change the schedule at all. Nothing drags without it. */
		canSchedule?: boolean;
		/** Whether this reader may start a Job from empty space. The create affordance is absent without it. */
		canCreate?: boolean;
		/** The visit whose proposed move is waiting to be saved, so the grid can show it as pending. */
		movingVisitId?: string | null;
		/** The reader's grid zoom: how tall an hour is drawn. Card density follows from the room it makes. */
		zoom?: ScheduleZoom;
		/** The Unscheduled drawer's drop zone, if it is open. A card dropped over it goes back to the backlog. */
		unscheduleZone?: HTMLElement | null;
		onselect: (visit: ScheduleVisit, element: HTMLElement) => void;
		/** An assessment card was selected. The page opens its Request-owned preview; nothing drags. */
		onselectassessment: (assessment: AssessmentItem, element: HTMLElement) => void;
		/** An event card was selected. The page opens its Schedule-owned preview; nothing drags. */
		onselectevent: (event: EventItem, element: HTMLElement) => void;
		/** A drag finished. Nothing is written until the page's confirmation is saved. */
		onpropose: (visit: ScheduleVisit, proposal: ScheduleProposal, anchor: HTMLElement) => void;
		/** A card was dropped over the Unscheduled drawer. The page confirms before it clears the date. */
		onunschedule?: (visit: ScheduleVisit, anchor: HTMLElement) => void;
		/** An empty-space gesture proposed a brand-new visit. The page opens the create form; nothing
		 *  is written until it is saved. */
		oncreate?: (draft: NewVisitDraft) => void;
	} = $props();

	/** One hour of the grid, in pixels, from the reader's zoom. Everything vertical is worked out from this. */
	const HOUR_HEIGHT = $derived(WEEK_HOUR_PX[zoom]);

	const days = $derived(eachDayInWindow(activeWindow));
	const byDay = $derived(bucketVisitsByDay(items));

	const columns = $derived(
		days.map((day) => {
			const split = splitDayVisits(byDay.get(day) ?? []);
			return {
				day,
				anytime: split.anytime,
				blocks: layoutTimedVisits(split.timed),
				count: (byDay.get(day) ?? []).length,
				working: workingWeek?.get(weekdayOf(day)) ?? []
			};
		})
	);

	// Midnight is almost never where the work is. The grid opens just before the earliest thing it could
	// show -- the business opening, or the first visit of the week when that is earlier.
	const openingMinute = $derived.by(() => {
		const starts = columns.flatMap((column) => column.blocks.map((block) => block.start));
		const earliestVisit = starts.length > 0 ? Math.min(...starts) : null;
		const earliestOpen = earliestWorkingMinute(workingWeek);
		const candidates = [earliestVisit, earliestOpen].filter(
			(value): value is number => value !== null
		);
		const anchor = candidates.length > 0 ? Math.min(...candidates) : 8 * 60;
		return Math.max(0, anchor - 30);
	});

	// --- Dragging ------------------------------------------------------------------------------------

	const PX_PER_MINUTE = $derived(HOUR_HEIGHT / 60);

	/** The day columns and the Anytime cells, measured on the fly so a drag knows where it is. */
	let columnEls = $state<(HTMLElement | undefined)[]>([]);
	let anytimeEls = $state<(HTMLElement | undefined)[]>([]);

	type WeekDrag = {
		visit: ScheduleVisit;
		mode: 'move' | 'resize';
		anchor: HTMLElement;
		/** Where the proposal currently sits, for the ghost the person is watching. */
		day: string;
		start: number | null;
		end: number | null;
	};

	let drag = $state<WeekDrag | null>(null);
	/** How far down the card the pointer grabbed it, so the visit does not jump under the cursor. */
	let grabMinutes = 0;
	/** A drag that just ended must not also register as a click and open the preview. */
	let swallowClick = false;

	function contains(element: HTMLElement | undefined, event: PointerEvent) {
		if (!element) return false;
		const box = element.getBoundingClientRect();
		return (
			event.clientX >= box.left &&
			event.clientX <= box.right &&
			event.clientY >= box.top &&
			event.clientY <= box.bottom
		);
	}

	// Where the pointer is, in calendar terms. A pointer that has wandered off the grid answers null, and
	// the drag then keeps the last place it did understand rather than snapping somewhere arbitrary.
	function targetAt(event: PointerEvent): { day: string; startMinutes: number | null } | null {
		for (const [index, element] of anytimeEls.entries()) {
			if (contains(element, event)) return { day: days[index], startMinutes: null };
		}
		for (const [index, element] of columnEls.entries()) {
			if (!contains(element, event)) continue;
			const box = element!.getBoundingClientRect();
			const raw = (event.clientY - box.top) / PX_PER_MINUTE - grabMinutes;
			return { day: days[index], startMinutes: snapMinutes(raw) };
		}
		return null;
	}

	function endMinutesAt(event: PointerEvent, day: string): number | null {
		const index = days.indexOf(day);
		const element = columnEls[index];
		if (!element) return null;
		const box = element.getBoundingClientRect();
		return snapMinutes((event.clientY - box.top) / PX_PER_MINUTE);
	}

	// --- Placing a visit dragged in from the Unscheduled drawer -------------------------------------

	// The page owns that drag: the card lives in the drawer, so the grid does not start it. The grid only
	// answers where the pointer is over its own columns, paints that target, and hands back the anchor the
	// confirmation will open against. Nothing here writes; the page proposes the move on drop, exactly as an
	// internal drag does. A pointer landing at the pointer, not offset by a grab, because there is no card
	// held under the cursor to keep still.
	let externalDay = $state<string | null>(null);
	let externalStart = $state<number | null>(null);

	export function probeExternal(
		_visit: ScheduleVisit,
		event: PointerEvent
	): { target: DropTarget; anchor: PopoverAnchor } | null {
		for (const [index, element] of anytimeEls.entries()) {
			if (contains(element, event)) {
				externalDay = days[index];
				externalStart = null;
				return element
					? { target: { day: days[index], startMinutes: null }, anchor: element }
					: null;
			}
		}
		for (const [index, element] of columnEls.entries()) {
			if (!contains(element, event)) continue;
			const box = element!.getBoundingClientRect();
			const startMinutes = snapMinutes((event.clientY - box.top) / PX_PER_MINUTE);
			externalDay = days[index];
			externalStart = startMinutes;
			// A day column is a full 24 hours tall and mostly scrolled out of sight, so it is useless to point
			// a popover at. An internal drag anchors to the card it moved; a card arriving from the backlog has
			// no card on the grid yet, so the confirmation points at the spot it was dropped on instead.
			return {
				target: { day: days[index], startMinutes },
				anchor: anchorAtPoint(event.clientX, event.clientY)
			};
		}
		externalDay = null;
		externalStart = null;
		return null;
	}

	export function clearExternal() {
		externalDay = null;
		externalStart = null;
	}

	const externalGhost = $derived.by(() => {
		if (externalDay === null || externalStart === null) return null;
		const end = externalStart + 60;
		return {
			day: externalDay,
			start: externalStart,
			end,
			label: `${clockLabel(clockText(externalStart))} – ${clockLabel(clockText(end))}`
		};
	});

	function beginMove(event: PointerEvent, visit: ScheduleVisit, block: { start: number } | null) {
		if (!canDragVisit(visit, canSchedule)) return;
		// A drag that ended away from the card left no click behind to swallow. Each new press starts clean,
		// so a stale guard can never eat somebody's next real click.
		swallowClick = false;
		const anchor = event.currentTarget as HTMLElement;

		// An Anytime card has no place on the time axis to grab, so it is picked up by its top.
		if (block) {
			const box = anchor.getBoundingClientRect();
			grabMinutes = Math.max(0, (event.clientY - box.top) / PX_PER_MINUTE);
		} else {
			grabMinutes = 0;
		}

		startPointerDrag(event, {
			onStart: () => {
				drag = {
					visit,
					mode: 'move',
					anchor,
					day: visit.visit_date ?? today,
					start: block?.start ?? null,
					end: null
				};
			},
			onMove: (moved) => {
				if (!drag) return;
				const target = targetAt(moved);
				if (!target) return;
				const proposal = proposeMove(visit, target);
				drag = {
					...drag,
					day: target.day,
					start: target.startMinutes,
					end: target.startMinutes === null ? null : minutesOf(proposal.end_time)
				};
			},
			onDrop: (dropped) => {
				const current = drag;
				drag = null;
				swallowClick = true;
				if (!current) return;
				// Dropped over the open Unscheduled drawer: send the visit back to the backlog rather than to a
				// day. The page confirms before anything is written.
				if (contains(unscheduleZone ?? undefined, dropped)) {
					onunschedule?.(visit, current.anchor);
					return;
				}
				const target = targetAt(dropped) ?? { day: current.day, startMinutes: current.start };
				onpropose(visit, proposeMove(visit, target), current.anchor);
			},
			onCancel: () => {
				drag = null;
			}
		});
	}

	function beginResize(event: PointerEvent, visit: ScheduleVisit, block: { start: number }) {
		if (!canDragVisit(visit, canSchedule)) return;
		event.stopPropagation();
		const anchor = (event.currentTarget as HTMLElement).parentElement as HTMLElement;
		const day = visit.visit_date ?? today;

		startPointerDrag(event, {
			onStart: () => {
				drag = { visit, mode: 'resize', anchor, day, start: block.start, end: null };
			},
			onMove: (moved) => {
				if (!drag) return;
				const end = endMinutesAt(moved, day);
				if (end === null) return;
				const proposal = proposeResize(visit, end);
				drag = { ...drag, end: minutesOf(proposal.end_time) };
			},
			onDrop: (dropped) => {
				const current = drag;
				drag = null;
				swallowClick = true;
				if (!current) return;
				const end = endMinutesAt(dropped, day) ?? current.end;
				if (end === null) return;
				onpropose(visit, proposeResize(visit, end), current.anchor);
			},
			onCancel: () => {
				drag = null;
			}
		});
	}

	// The keyboard equivalent of dragging: arrow keys build the same proposal a mouse drag would, shown with
	// the same ghost, and only Enter turns it into the confirmation dialog a pointer drop already opens.
	// Left/right shift the day, up/down nudge the clock a quarter hour, matching the axes this grid draws.
	function handleVisitKey(
		event: KeyboardEvent,
		visit: ScheduleVisit,
		block: { start: number } | null
	) {
		if (!canDragVisit(visit, canSchedule)) return;
		const anchor = event.currentTarget as HTMLElement;
		const active = drag?.visit.id === visit.id ? drag : null;

		if (active && (event.key === 'Escape' || event.key === ' ' || event.key === 'Enter')) {
			event.preventDefault();
			if (event.key !== 'Escape') {
				onpropose(
					visit,
					proposeMove(visit, { day: active.day, startMinutes: active.start }),
					anchor
				);
			}
			drag = null;
			return;
		}

		const isHorizontal = event.key === 'ArrowLeft' || event.key === 'ArrowRight';
		const isVertical = event.key === 'ArrowUp' || event.key === 'ArrowDown';
		if (!isHorizontal && !isVertical) return;

		const base: WeekDrag = active ?? {
			visit,
			mode: 'move',
			anchor,
			day: visit.visit_date ?? today,
			start: block?.start ?? null,
			end: null
		};
		if (isVertical && base.start === null) return; // Anytime has no clock time to nudge.
		event.preventDefault();

		const day = isHorizontal ? shiftDay(base.day, event.key === 'ArrowLeft' ? -1 : 1) : base.day;
		const start = isVertical
			? Math.max(
					0,
					Math.min(
						MINUTES_IN_DAY,
						(base.start ?? 0) + (event.key === 'ArrowUp' ? -1 : 1) * SNAP_MINUTES
					)
				)
			: base.start;

		const proposal = proposeMove(visit, { day, startMinutes: start });
		drag = { ...base, day, start, end: start === null ? null : minutesOf(proposal.end_time) };
	}

	function handleVisitBlur(event: FocusEvent, visit: ScheduleVisit) {
		if (drag?.visit.id === visit.id) drag = null;
	}

	// --- Creating from empty space -----------------------------------------------------------------

	// A press on the empty part of a day column starts a new visit. A plain click opens a one-hour visit at
	// that time; a click-drag draws the block first. A press that landed on a card or its resize handle
	// belongs to that card, so this bows out and lets the card's own handler run.
	let createDrag = $state<{ day: string; start: number; end: number } | null>(null);

	function beginCreate(event: PointerEvent, index: number) {
		if (!canCreate || event.button !== 0) return;
		const target = event.target as HTMLElement;
		// A press on a card belongs to that card, not to empty space. Visit cards carry the pickup handle;
		// an assessment card has no handle but must still bow out, or its click would also start a new job.
		if (
			target.closest('.week__pickup') ||
			target.closest('.week__resize') ||
			target.closest('.assessment-card') ||
			target.closest('.event-card') ||
			target.closest('.task-card')
		)
			return;
		const element = columnEls[index];
		if (!element) return;

		const day = days[index];
		const box = element.getBoundingClientRect();
		const startMinutes = snapMinutes((event.clientY - box.top) / PX_PER_MINUTE);
		let dragged = false;
		swallowClick = false;

		startPointerDrag(event, {
			onStart: () => {
				dragged = true;
				createDrag = { day, start: startMinutes, end: startMinutes };
			},
			onMove: (moved) => {
				const end = endMinutesAt(moved, day);
				if (end === null) return;
				createDrag = { day, start: startMinutes, end };
			},
			onDrop: (dropped) => {
				createDrag = null;
				swallowClick = true;
				const end = endMinutesAt(dropped, day) ?? startMinutes;
				oncreate?.(draftFromRange(day, startMinutes, end));
			},
			onCancel: () => {
				// A release that never became a drag is a plain click: a one-hour visit at that time. Escape
				// during a drag comes through here too, but by then it was a drag, so it just clears.
				const wasClick = !dragged;
				createDrag = null;
				if (wasClick) oncreate?.(draftFromClick(day, startMinutes));
			}
		});
	}

	// A click on empty Anytime space books a date-only visit for that day.
	function createAnytime(event: MouseEvent, day: string) {
		if (!canCreate) return;
		const target = event.target as HTMLElement;
		if (
			target.closest('.week__pickup') ||
			target.closest('.assessment-card') ||
			target.closest('.event-card') ||
			target.closest('.task-card')
		)
			return;
		oncreate?.(draftAnytime(day));
	}

	const createGhost = $derived.by(() => {
		if (!createDrag) return null;
		const end = Math.max(createDrag.start + 15, createDrag.end);
		return {
			day: createDrag.day,
			start: Math.min(createDrag.start, end),
			end: Math.max(createDrag.start, end),
			label: `${clockLabel(clockText(Math.min(createDrag.start, end)))} – ${clockLabel(clockText(Math.max(createDrag.start, end)))}`
		};
	});

	function minutesOf(clock: string | null): number | null {
		if (!clock) return null;
		const [hour, minute] = clock.split(':').map(Number);
		return hour * 60 + minute;
	}

	// The click that follows a real drag is the browser finishing the gesture, not somebody choosing a card.
	function afterDrag(event: MouseEvent) {
		if (!swallowClick) return;
		swallowClick = false;
		event.stopPropagation();
		event.preventDefault();
	}

	const ghost = $derived.by(() => {
		if (!drag || drag.start === null) return null;
		const end = drag.end ?? drag.start + 60;
		return {
			day: drag.day,
			start: drag.start,
			end,
			label: `${clockLabel(clockText(drag.start))} – ${clockLabel(clockText(end))}`
		};
	});

	const ghosts = $derived(
		[
			ghost && { ...ghost, tone: 'move' as const },
			createGhost && { ...createGhost, tone: 'create' as const },
			externalGhost && { ...externalGhost, tone: 'create' as const }
		].filter((value): value is WeekGridGhost => Boolean(value))
	);

	function clockText(minutes: number) {
		const hour = Math.floor(minutes / 60);
		return `${String(hour).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
	}
</script>

<CalendarWeekGrid
	{columns}
	{today}
	{nowMinutes}
	hourHeight={HOUR_HEIGHT}
	{openingMinute}
	{ghosts}
	bookable={canCreate}
	anytimeTarget={(day) =>
		(drag !== null && drag.day === day) || (externalStart === null && externalDay === day)}
	bind:columnEls
	bind:anytimeEls
	oncolumnpointerdown={beginCreate}
	onanytimeclick={createAnytime}
>
	{#snippet anytimeItem(item)}
		{#if item.kind === 'visit'}
			<div
				class="week__pickup"
				class:week__pickup--dragging={drag?.visit.id === item.id}
				class:week__pickup--pending={movingVisitId === item.id}
				onclickcapture={afterDrag}
			>
				<VisitCard
					visit={item}
					density="compact"
					{today}
					{employeesById}
					selected={item.id === selectedItemId}
					keyboardMovable={canDragVisit(item, canSchedule)}
					{onselect}
					onpickup={(event) => beginMove(event, item, null)}
					onkeydown={(event) => handleVisitKey(event, item, null)}
					onblur={(event) => handleVisitBlur(event, item)}
				/>
			</div>
		{:else if item.kind === 'assessment'}
			<AssessmentCard
				assessment={item}
				density="compact"
				{today}
				{employeesById}
				selected={item.id === selectedItemId}
				onselect={onselectassessment}
			/>
		{:else if item.kind === 'task'}
			<TaskCard task={item} density="compact" {today} {employeesById} />
		{:else}
			<EventCard
				event={item}
				density="compact"
				selected={item.id === selectedItemId}
				onselect={onselectevent}
			/>
		{/if}
	{/snippet}

	{#snippet block(block)}
		{@const density = cardDensity(((block.end - block.start) / 60) * HOUR_HEIGHT, block.columns)}
		{#if block.item.kind === 'visit'}
			{@const visit = block.item}
			<div
				class="week__pickup week__pickup--timed"
				class:week__pickup--dragging={drag?.visit.id === visit.id}
				class:week__pickup--pending={movingVisitId === visit.id}
				onclickcapture={afterDrag}
			>
				<VisitCard
					{visit}
					{density}
					{today}
					{employeesById}
					selected={visit.id === selectedItemId}
					keyboardMovable={canDragVisit(visit, canSchedule)}
					{onselect}
					onpickup={(event) => beginMove(event, visit, block)}
					onkeydown={(event) => handleVisitKey(event, visit, block)}
					onblur={(event) => handleVisitBlur(event, visit)}
				/>
				{#if canDragVisit(visit, canSchedule)}
					<!-- The bottom edge, for changing how long the work should take. It is a handle on a card that is
					     already reachable by keyboard through Reschedule, so it is decoration to a screen reader
					     rather than a second control saying the same thing. -->
					<span
						class="week__resize"
						aria-hidden="true"
						onpointerdown={(event) => beginResize(event, visit, block)}
					></span>
				{/if}
			</div>
		{:else if block.item.kind === 'assessment'}
			<!-- An assessment sits on the same time axis but is Request-owned: no pickup, no resize, and its click
			     opens the Request rather than a visit editor. -->
			<AssessmentCard
				assessment={block.item}
				{density}
				{today}
				{employeesById}
				selected={block.item.id === selectedItemId}
				onselect={onselectassessment}
			/>
		{:else if block.item.kind === 'event'}
			<!-- A Schedule-owned event on the time axis: no pickup, no resize; its click opens its own popover. -->
			<EventCard
				event={block.item}
				{density}
				selected={block.item.id === selectedItemId}
				onselect={onselectevent}
			/>
		{/if}
	{/snippet}
</CalendarWeekGrid>

<style lang="scss">
	// A card you can pick up says so before you touch it, and steps out of the way while it is being moved:
	// the ghost is the thing to watch during a drag, not the card's old position.
	.week__pickup {
		touch-action: none;

		&--dragging {
			opacity: 0.35;
		}

		// The proposal is on screen waiting to be saved, so the card is visibly not settled yet.
		&--pending {
			opacity: 0.6;
		}
	}

	// On the time axis the pickup fills the box the grid placed, so the resize handle sits on its bottom edge.
	.week__pickup--timed {
		position: relative;
		height: 100%;
	}

	.week__resize {
		position: absolute;
		right: 0;
		bottom: 0;
		left: 0;
		height: 8px;
		cursor: ns-resize;

		&::after {
			content: '';
			position: absolute;
			bottom: 2px;
			left: 50%;
			width: 24px;
			height: 2px;
			border-radius: var(--radius-small);
			background-color: var(--color-border--interactive);
			transform: translateX(-50%);
			opacity: 0;
			transition: opacity var(--timing-quick) ease;
		}
	}

	.week__pickup--timed:hover .week__resize::after {
		opacity: 1;
	}
</style>
