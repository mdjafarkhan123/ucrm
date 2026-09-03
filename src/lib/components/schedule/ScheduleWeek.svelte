<script lang="ts">
	import { untrack } from 'svelte';
	import type { Attachment } from 'svelte/attachments';
	import VisitCard from '$lib/components/schedule/VisitCard.svelte';
	import AssessmentCard from '$lib/components/schedule/AssessmentCard.svelte';
	import { bucketVisitsByDay } from '$lib/schedule/grouping';
	import type { AssessmentItem, ScheduleItem } from '$lib/schedule/items';
	import { earliestWorkingMinute, weekdayOf, type WorkingWeek } from '$lib/schedule/hours';
	import { formatCalendarDay } from '$lib/schedule/labels';
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
		snapMinutes,
		type DropTarget,
		type NewVisitDraft,
		type ScheduleProposal
	} from '$lib/schedule/drag';
	import { startPointerDrag } from '$lib/schedule/pointer-drag';
	import { clockLabel } from '$lib/schedule/labels';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';

	// The week, as seven day columns over one shared time axis.
	//
	// Hour lines and the working-hours band are painted rather than built: a grid of 7 x 24 cells would be
	// 168 elements of pure decoration, and this view has real cards to spend that budget on.
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
	const HOURS = Array.from({ length: 24 }, (_, hour) => hour);

	const days = $derived(eachDayInWindow(activeWindow));
	const byDay = $derived(bucketVisitsByDay(items));

	const columns = $derived(
		days.map((day) => {
			const split = splitDayVisits(byDay.get(day) ?? []);
			return {
				day,
				weekday: weekdayOf(day),
				anytime: split.anytime,
				blocks: layoutTimedVisits(split.timed),
				count: (byDay.get(day) ?? []).length
			};
		})
	);

	const anyAnytime = $derived(columns.some((column) => column.anytime.length > 0));

	function percent(minutes: number) {
		return `${(minutes / MINUTES_IN_DAY) * 100}%`;
	}

	function hourLabel(hour: number) {
		if (hour === 0 || hour === 12) return hour === 0 ? '12am' : '12pm';
		return hour < 12 ? `${hour}am` : `${hour - 12}pm`;
	}

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

	// The opening minute is read without subscribing to it, so this runs once when the grid mounts. Tracking
	// it would scroll the view back to the top of the working day every time a visit changed, while
	// somebody was reading further down.
	const openAtWorkingHours: Attachment<HTMLElement> = (node) => {
		node.scrollTop = (untrack(() => openingMinute) / 60) * untrack(() => HOUR_HEIGHT);
	};

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
	): { target: DropTarget; anchor: HTMLElement } | null {
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
			return { target: { day: days[index], startMinutes }, anchor: element! };
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
			target.closest('.assessment-card')
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
		if (target.closest('.week__pickup') || target.closest('.assessment-card')) return;
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

	function clockText(minutes: number) {
		const hour = Math.floor(minutes / 60);
		return `${String(hour).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
	}
</script>

<div class="week" style:--week-hour="{HOUR_HEIGHT}px">
	<div class="week__row week__head">
		<div class="week__corner"></div>
		{#each columns as column (column.day)}
			<div class="week__day" class:week__day--today={column.day === today}>
				<span class="week__weekday">{formatCalendarDay(column.day, { weekday: 'short' })}</span>
				<span class="week__date">{formatCalendarDay(column.day, { day: 'numeric' })}</span>
				{#if column.count > 0}
					<span class="week__count">{column.count} {column.count === 1 ? 'visit' : 'visits'}</span>
				{/if}
			</div>
		{/each}
	</div>

	{#if anyAnytime}
		<div class="week__row week__anytime">
			<div class="week__anytime-label">Anytime</div>
			{#each columns as column, index (column.day)}
				<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
				<!-- A pointer affordance for booking a date-only visit; the keyboard path is the New Visit
				     button in the page header. -->
				<div
					class="week__anytime-column"
					class:week__anytime-column--target={(drag !== null && drag.day === column.day) ||
						(externalStart === null && externalDay === column.day)}
					class:week__anytime-column--bookable={canCreate}
					bind:this={anytimeEls[index]}
					onclick={(event) => createAnytime(event, column.day)}
				>
					{#each column.anytime as item (item.id)}
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
									{onselect}
									onpickup={(event) => beginMove(event, item, null)}
								/>
							</div>
						{:else}
							<AssessmentCard
								assessment={item}
								density="compact"
								{today}
								{employeesById}
								selected={item.id === selectedItemId}
								onselect={onselectassessment}
							/>
						{/if}
					{/each}
				</div>
			{/each}
		</div>
	{/if}

	<div class="week__row week__body" {@attach openAtWorkingHours}>
		<div class="week__times" style:height="{24 * HOUR_HEIGHT}px">
			{#each HOURS as hour (hour)}
				<span class="week__hour" style:top="{hour * HOUR_HEIGHT}px">{hourLabel(hour)}</span>
			{/each}
		</div>

		{#each columns as column, index (column.day)}
			<!-- svelte-ignore a11y_no_static_element_interactions -->
			<!-- A pointer affordance for booking a visit on empty time; the keyboard path is the New Visit
			     button in the page header. -->
			<div
				class="week__column"
				class:week__column--bookable={canCreate}
				style:height="{24 * HOUR_HEIGHT}px"
				bind:this={columnEls[index]}
				onpointerdown={(event) => beginCreate(event, index)}
			>
				{#each workingWeek?.get(column.weekday) ?? [] as band (band.start)}
					<div
						class="week__working"
						style:top={percent(band.start)}
						style:height={percent(band.end - band.start)}
					></div>
				{/each}

				<div class="week__lines" aria-hidden="true"></div>

				{#each column.blocks as block (block.item.id)}
					{#if block.item.kind === 'visit'}
						{@const visit = block.item}
						<div
							class="week__block week__pickup"
							class:week__pickup--dragging={drag?.visit.id === visit.id}
							class:week__pickup--pending={movingVisitId === visit.id}
							style:top={percent(block.start)}
							style:height={percent(block.end - block.start)}
							style:left="{(block.column / block.columns) * 100}%"
							style:width="{(1 / block.columns) * 100}%"
							onclickcapture={afterDrag}
						>
							<VisitCard
								{visit}
								density={cardDensity(((block.end - block.start) / 60) * HOUR_HEIGHT, block.columns)}
								{today}
								{employeesById}
								selected={visit.id === selectedItemId}
								{onselect}
								onpickup={(event) => beginMove(event, visit, block)}
							/>
							{#if canDragVisit(visit, canSchedule)}
								<!-- The bottom edge, for changing how long the work should take. It is a handle on a
								     card that is already reachable by keyboard through Reschedule, so it is decoration
								     to a screen reader rather than a second control saying the same thing. -->
								<span
									class="week__resize"
									aria-hidden="true"
									onpointerdown={(event) => beginResize(event, visit, block)}
								></span>
							{/if}
						</div>
					{:else}
						<!-- An assessment sits on the same time axis but is Request-owned: no pickup, no resize,
						     and its click opens the Request rather than a visit editor. -->
						<div
							class="week__block"
							style:top={percent(block.start)}
							style:height={percent(block.end - block.start)}
							style:left="{(block.column / block.columns) * 100}%"
							style:width="{(1 / block.columns) * 100}%"
						>
							<AssessmentCard
								assessment={block.item}
								density={cardDensity(((block.end - block.start) / 60) * HOUR_HEIGHT, block.columns)}
								{today}
								{employeesById}
								selected={block.item.id === selectedItemId}
								onselect={onselectassessment}
							/>
						</div>
					{/if}
				{/each}

				{#if ghost && ghost.day === column.day}
					<div
						class="week__ghost"
						style:top={percent(ghost.start)}
						style:height={percent(Math.max(15, ghost.end - ghost.start))}
						aria-hidden="true"
					>
						<span class="week__ghost-label">{ghost.label}</span>
					</div>
				{/if}

				{#if createGhost && createGhost.day === column.day}
					<div
						class="week__ghost week__ghost--create"
						style:top={percent(createGhost.start)}
						style:height={percent(Math.max(15, createGhost.end - createGhost.start))}
						aria-hidden="true"
					>
						<span class="week__ghost-label">{createGhost.label}</span>
					</div>
				{/if}

				{#if externalGhost && externalGhost.day === column.day}
					<div
						class="week__ghost week__ghost--create"
						style:top={percent(externalGhost.start)}
						style:height={percent(Math.max(15, externalGhost.end - externalGhost.start))}
						aria-hidden="true"
					>
						<span class="week__ghost-label">{externalGhost.label}</span>
					</div>
				{/if}

				{#if nowMinutes !== null && column.day === today}
					<div class="week__now" style:top={percent(nowMinutes)} aria-hidden="true"></div>
				{/if}
			</div>
		{/each}
	</div>
</div>

<style lang="scss">
	.week {
		--week-gutter: 56px;

		display: flex;
		flex-direction: column;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	.week__row {
		display: grid;
		grid-template-columns: var(--week-gutter) repeat(7, minmax(0, 1fr));
	}

	.week__head {
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface);
	}

	.week__corner {
		border-right: var(--border-base) solid var(--color-border);
	}

	.week__day {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-smallest);
		padding: var(--space-small) var(--space-smaller);
		border-left: var(--border-base) solid var(--color-border);
	}

	.week__weekday {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
	}

	.week__date {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 28px;
		height: 28px;
		border-radius: var(--radius-circle);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
	}

	.week__day--today .week__date {
		background-color: var(--color-interactive);
		color: var(--color-surface);
	}

	.week__count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
	}

	.week__anytime {
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface--background--subtle);
	}

	.week__anytime-label {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		padding: var(--space-small) var(--space-smaller);
		border-right: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}

	.week__anytime-column {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		padding: var(--space-smaller);
		max-height: 112px;
		overflow-y: auto;
		border-left: var(--border-base) solid var(--color-border);
	}

	.week__body {
		// The gutter scrolls with the columns, so the hour labels can never drift away from their lines.
		height: clamp(360px, calc(100vh - 340px), 900px);
		overflow-y: auto;
		scrollbar-gutter: stable;
	}

	.week__times {
		position: relative;
		border-right: var(--border-base) solid var(--color-border);
	}

	.week__hour {
		position: absolute;
		right: var(--space-small);
		// Sat on its own line rather than inside the hour it opens, so a label reads as the line's time.
		transform: translateY(-50%);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	.week__column {
		position: relative;
		border-left: var(--border-base) solid var(--color-border);
		// Outside working hours the column recedes; the working band below paints itself back to the
		// ordinary surface. With no confirmed weekly pattern nothing is painted and the whole day recedes
		// equally, which is honest -- the calendar does not know the hours.
		background-color: var(--color-surface--background);
	}

	.week__working {
		position: absolute;
		left: 0;
		width: 100%;
		background-color: var(--color-surface);
	}

	.week__lines {
		position: absolute;
		inset: 0;
		background-image: repeating-linear-gradient(
			to bottom,
			var(--color-border) 0,
			var(--color-border) 1px,
			transparent 1px,
			transparent var(--week-hour)
		);
		pointer-events: none;
	}

	.week__block {
		position: absolute;
		box-sizing: border-box;
		padding-right: var(--space-smallest);
	}

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

	.week__resize {
		position: absolute;
		right: var(--space-smallest);
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

	.week__block:hover .week__resize::after {
		opacity: 1;
	}

	.week__ghost {
		position: absolute;
		right: var(--space-smallest);
		left: 0;
		box-sizing: border-box;
		display: flex;
		align-items: flex-start;
		padding: var(--space-smallest) var(--space-smaller);
		border: var(--border-thick) dashed var(--color-interactive);
		border-radius: var(--radius-small);
		background-color: var(--color-informative--surface);
		pointer-events: none;
	}

	// The new-visit ghost reads as a fresh, additive block rather than a moved one.
	.week__ghost--create {
		border-style: dashed;
		border-color: var(--color-success);
		background-color: var(--color-success--surface);
	}

	.week__ghost-label {
		color: var(--color-informative--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	.week__ghost--create .week__ghost-label {
		color: var(--color-success--onSurface);
	}

	.week__column--bookable {
		cursor: cell;
	}

	.week__anytime-column--bookable {
		cursor: cell;
	}

	.week__anytime-column--target {
		background-color: var(--color-informative--surface);
	}

	.week__now {
		position: absolute;
		left: 0;
		width: 100%;
		border-top: var(--border-thick) solid var(--color-critical);
		pointer-events: none;

		&::before {
			content: '';
			position: absolute;
			top: -4px;
			left: 0;
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background-color: var(--color-critical);
		}
	}
</style>
