<script lang="ts">
	import { untrack } from 'svelte';
	import type { Attachment } from 'svelte/attachments';
	import Avatar from '$lib/components/ui/Avatar.svelte';
	import VisitCard from '$lib/components/schedule/VisitCard.svelte';
	import { earliestWorkingMinute, weekdayOf, type WorkingWeek } from '$lib/schedule/hours';
	import { cardDensityForWidth, MINUTES_IN_DAY } from '$lib/schedule/layout';
	import { buildDayRows, UNASSIGNED_ROW_KEY } from '$lib/schedule/rows';
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
	import type { ScheduleEmployeeFilter } from '$lib/schedule/filters';
	import { DAY_HOUR_PX, type ScheduleZoom } from '$lib/schedule/density';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';
	import userOffIcon from '@tabler/icons/outline/user-off.svg?raw';

	// The day, as rows of people over one shared time axis running left to right.
	//
	// This is the dispatch board: the row answers who, its emptiness answers where the gaps are, and a visit
	// two people share is drawn in both of their rows so neither day looks lighter than it is. The name and
	// Anytime columns stay pinned while the hours scroll, because a row you cannot name is not worth reading.
	//
	// Dragging sideways changes the hour; dragging into another row changes who is going. A visit a crew
	// shares is the exception: dropping it in somebody else's row opens the assignment editor rather than
	// quietly replacing the whole crew with one person, exactly as the behaviour contract requires.

	let {
		day,
		visits,
		team,
		today,
		nowMinutes,
		workingWeek,
		employeeFilter,
		employeesById,
		selectedVisitId,
		canSchedule = false,
		canCreate = false,
		movingVisitId = null,
		zoom = 'compact',
		unscheduleZone = null,
		onselect,
		onpropose,
		oneditassignment,
		oncreate,
		onunschedule
	}: {
		day: string;
		/** Already filtered by the page. Every one of these is drawn, once per person on it. */
		visits: ScheduleVisit[];
		team: TeamMember[];
		today: string;
		/** Minutes past midnight in the contractor's own timezone, or null when this is not today. */
		nowMinutes: number | null;
		/** Null when the business has no confirmed weekly pattern, so nothing is shaded. */
		workingWeek: WorkingWeek | null;
		employeeFilter: ScheduleEmployeeFilter;
		employeesById: Map<string, TeamMember>;
		selectedVisitId: string | null;
		/** Whether this reader may change the schedule at all. Nothing drags without it. */
		canSchedule?: boolean;
		/** Whether this reader may start a Job from empty space. The create affordance is absent without it. */
		canCreate?: boolean;
		/** The visit whose proposed move is waiting to be saved, so the board can show it as pending. */
		movingVisitId?: string | null;
		/** The reader's grid zoom: how wide an hour is drawn. Card density follows from the room it makes. */
		zoom?: ScheduleZoom;
		/** The Unscheduled drawer's drop zone, if it is open. A card dropped over it goes back to the backlog. */
		unscheduleZone?: HTMLElement | null;
		onselect: (visit: ScheduleVisit, element: HTMLElement) => void;
		/** A drag finished. Nothing is written until the page's confirmation is saved. */
		onpropose: (visit: ScheduleVisit, proposal: ScheduleProposal, anchor: HTMLElement) => void;
		/** A shared visit was dropped in somebody else's row; the crew is edited, never swapped. */
		oneditassignment: (visit: ScheduleVisit, anchor: HTMLElement) => void;
		/** A card was dropped over the Unscheduled drawer. The page confirms before it clears the date. */
		onunschedule?: (visit: ScheduleVisit, anchor: HTMLElement) => void;
		/** An empty-space gesture proposed a brand-new visit. The page opens the create form; nothing
		 *  is written until it is saved. */
		oncreate?: (draft: NewVisitDraft) => void;
	} = $props();

	/** One hour of the axis, in pixels, from the reader's zoom, and one lane of a row. Everything else is
	 *  worked out from these. Zoom stretches the time axis only; a lane keeps its height. */
	const HOUR_WIDTH = $derived(DAY_HOUR_PX[zoom]);
	const LANE_HEIGHT = 92;
	const HOURS = Array.from({ length: 24 }, (_, hour) => hour);

	const rows = $derived(buildDayRows(visits, team, employeeFilter));
	const workingBands = $derived(workingWeek?.get(weekdayOf(day)) ?? []);

	function percent(minutes: number) {
		return `${(minutes / MINUTES_IN_DAY) * 100}%`;
	}

	function hourLabel(hour: number) {
		if (hour === 0 || hour === 12) return hour === 0 ? '12am' : '12pm';
		return hour < 12 ? `${hour}am` : `${hour - 12}pm`;
	}

	function visitCountLabel(count: number) {
		return `${count} ${count === 1 ? 'visit' : 'visits'}`;
	}

	// Midnight is almost never where the work is. The board opens just before the earliest thing it could
	// show -- the business opening, or the first visit of the day when that is earlier.
	const openingMinute = $derived.by(() => {
		const starts = rows.flatMap((row) => row.blocks.map((block) => block.start));
		const earliestVisit = starts.length > 0 ? Math.min(...starts) : null;
		const earliestOpen = earliestWorkingMinute(workingWeek);
		const candidates = [earliestVisit, earliestOpen].filter(
			(value): value is number => value !== null
		);
		const anchor = candidates.length > 0 ? Math.min(...candidates) : 8 * 60;
		return Math.max(0, anchor - 30);
	});

	// Read without subscribing, so this runs once when the board mounts. Tracking it would drag the hours
	// back to the start of the working day every time a visit changed, while somebody was reading later on.
	const openAtWorkingHours: Attachment<HTMLElement> = (node) => {
		node.scrollLeft = (untrack(() => openingMinute) / 60) * untrack(() => HOUR_WIDTH);
	};

	// --- Dragging ------------------------------------------------------------------------------------

	const PX_PER_MINUTE = $derived(HOUR_WIDTH / 60);

	/** The time tracks and Anytime cells, one of each per row, measured on the fly during a drag. */
	let trackEls = $state<(HTMLElement | undefined)[]>([]);
	let anytimeEls = $state<(HTMLElement | undefined)[]>([]);

	type DayDrag = {
		visit: ScheduleVisit;
		mode: 'move' | 'resize';
		anchor: HTMLElement;
		rowIndex: number;
		start: number | null;
		end: number | null;
	};

	let drag = $state<DayDrag | null>(null);
	/** How far into the card the pointer grabbed it, so the visit does not jump under the cursor. */
	let grabMinutes = 0;
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

	type RowTarget = { rowIndex: number; startMinutes: number | null };

	function targetAt(event: PointerEvent): RowTarget | null {
		for (const [index, element] of anytimeEls.entries()) {
			if (contains(element, event)) return { rowIndex: index, startMinutes: null };
		}
		for (const [index, element] of trackEls.entries()) {
			if (!contains(element, event)) continue;
			const box = element!.getBoundingClientRect();
			const raw = (event.clientX - box.left) / PX_PER_MINUTE - grabMinutes;
			return { rowIndex: index, startMinutes: snapMinutes(raw) };
		}
		return null;
	}

	// Whose row the drop landed in, as an assignee list -- but only when the row really changed. A visit
	// dropped back in its own row keeps its crew untouched, however many people are on it.
	function crewFor(visit: ScheduleVisit, rowIndex: number): string[] | undefined {
		const row = rows[rowIndex];
		if (!row) return undefined;
		const startedIn = rows.findIndex((candidate) =>
			candidate.kind === 'unassigned'
				? visit.assignee_ids.length === 0
				: visit.assignee_ids.includes(candidate.key)
		);
		if (row.key === rows[startedIn]?.key) return undefined;
		return row.key === UNASSIGNED_ROW_KEY ? [] : [row.key];
	}

	/** A crew of two or more is edited, never swapped by a drag. */
	function isShared(visit: ScheduleVisit) {
		return visit.assignee_ids.length > 1;
	}

	function dropTargetFor(visit: ScheduleVisit, target: RowTarget): DropTarget {
		return {
			day,
			startMinutes: target.startMinutes,
			assigneeIds: isShared(visit) ? undefined : crewFor(visit, target.rowIndex)
		};
	}

	function beginMove(
		event: PointerEvent,
		visit: ScheduleVisit,
		rowIndex: number,
		block: { start: number } | null
	) {
		if (!canDragVisit(visit, canSchedule)) return;
		// A drag that ended away from the card left no click behind to swallow. Each new press starts clean,
		// so a stale guard can never eat somebody's next real click.
		swallowClick = false;
		const anchor = event.currentTarget as HTMLElement;

		if (block) {
			const box = anchor.getBoundingClientRect();
			grabMinutes = Math.max(0, (event.clientX - box.left) / PX_PER_MINUTE);
		} else {
			grabMinutes = 0;
		}

		startPointerDrag(event, {
			onStart: () => {
				drag = {
					visit,
					mode: 'move',
					anchor,
					rowIndex,
					start: block?.start ?? null,
					end: null
				};
			},
			onMove: (moved) => {
				if (!drag) return;
				const target = targetAt(moved);
				if (!target) return;
				const proposal = proposeMove(visit, dropTargetFor(visit, target));
				drag = {
					...drag,
					rowIndex: target.rowIndex,
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
				// row. The page confirms before anything is written.
				if (contains(unscheduleZone ?? undefined, dropped)) {
					onunschedule?.(visit, current.anchor);
					return;
				}
				const target = targetAt(dropped) ?? {
					rowIndex: current.rowIndex,
					startMinutes: current.start
				};
				// A shared visit that changed rows never has its crew rewritten by the gesture. The person
				// gets the assignment editor and decides who is actually going.
				if (isShared(visit) && crewFor(visit, target.rowIndex) !== undefined) {
					oneditassignment(visit, current.anchor);
					return;
				}
				onpropose(visit, proposeMove(visit, dropTargetFor(visit, target)), current.anchor);
			},
			onCancel: () => {
				drag = null;
			}
		});
	}

	function beginResize(
		event: PointerEvent,
		visit: ScheduleVisit,
		rowIndex: number,
		block: { start: number }
	) {
		if (!canDragVisit(visit, canSchedule)) return;
		event.stopPropagation();
		const anchor = (event.currentTarget as HTMLElement).parentElement as HTMLElement;

		startPointerDrag(event, {
			onStart: () => {
				drag = { visit, mode: 'resize', anchor, rowIndex, start: block.start, end: null };
			},
			onMove: (moved) => {
				if (!drag) return;
				const end = endMinutesAt(moved, rowIndex);
				if (end === null) return;
				drag = { ...drag, end: minutesOf(proposeResize(visit, end).end_time) };
			},
			onDrop: (dropped) => {
				const current = drag;
				drag = null;
				swallowClick = true;
				if (!current) return;
				const end = endMinutesAt(dropped, rowIndex) ?? current.end;
				if (end === null) return;
				onpropose(visit, proposeResize(visit, end), current.anchor);
			},
			onCancel: () => {
				drag = null;
			}
		});
	}

	function endMinutesAt(event: PointerEvent, rowIndex: number): number | null {
		const element = trackEls[rowIndex];
		if (!element) return null;
		const box = element.getBoundingClientRect();
		return snapMinutes((event.clientX - box.left) / PX_PER_MINUTE);
	}

	// --- Placing a visit dragged in from the Unscheduled drawer -------------------------------------

	// The page owns that drag: the card lives in the drawer, so the board does not start it. The board only
	// answers which row and time the pointer is over, paints that target, and -- because dropping in a
	// person's row means assigning them -- works the crew out through the same rule an internal move uses.
	// Nothing here writes; the page proposes on drop.
	let externalRow = $state<number | null>(null);
	let externalStart = $state<number | null>(null);

	export function probeExternal(
		visit: ScheduleVisit,
		event: PointerEvent
	): { target: DropTarget; anchor: HTMLElement } | null {
		for (const [index, element] of anytimeEls.entries()) {
			if (contains(element, event)) {
				externalRow = index;
				externalStart = null;
				const anchor = element ?? trackEls[index];
				return anchor
					? { target: dropTargetFor(visit, { rowIndex: index, startMinutes: null }), anchor }
					: null;
			}
		}
		for (const [index, element] of trackEls.entries()) {
			if (!contains(element, event)) continue;
			const box = element!.getBoundingClientRect();
			const startMinutes = snapMinutes((event.clientX - box.left) / PX_PER_MINUTE);
			externalRow = index;
			externalStart = startMinutes;
			return { target: dropTargetFor(visit, { rowIndex: index, startMinutes }), anchor: element! };
		}
		externalRow = null;
		externalStart = null;
		return null;
	}

	export function clearExternal() {
		externalRow = null;
		externalStart = null;
	}

	const externalGhost = $derived.by(() => {
		if (externalRow === null || externalStart === null) return null;
		const end = externalStart + 60;
		return {
			rowIndex: externalRow,
			start: externalStart,
			end,
			label: `${clockLabel(clockText(externalStart))} – ${clockLabel(clockText(end))}`
		};
	});

	function minutesOf(clock: string | null): number | null {
		if (!clock) return null;
		const [hour, minute] = clock.split(':').map(Number);
		return hour * 60 + minute;
	}

	function afterDrag(event: MouseEvent) {
		if (!swallowClick) return;
		swallowClick = false;
		event.stopPropagation();
		event.preventDefault();
	}

	function clockText(minutes: number) {
		const hour = Math.floor(minutes / 60);
		return `${String(hour).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
	}

	const ghost = $derived.by(() => {
		if (!drag || drag.start === null) return null;
		const end = drag.end ?? drag.start + 60;
		return {
			rowIndex: drag.rowIndex,
			start: drag.start,
			end,
			label: `${clockLabel(clockText(drag.start))} – ${clockLabel(clockText(end))}`
		};
	});

	// --- Creating from empty space -----------------------------------------------------------------

	// A press on the empty part of a row's time track starts a new visit. A plain click opens a one-hour
	// visit at that time; a click-drag draws the block first. A press that landed on a card or its resize
	// handle belongs to that card, so this bows out and lets the card's own handler run. The row a gesture
	// starts in does not pre-assign anyone -- a new visit starts unassigned, and the create form collects
	// the crew.
	let createDrag = $state<{ rowIndex: number; start: number; end: number } | null>(null);

	function beginCreate(event: PointerEvent, rowIndex: number) {
		if (!canCreate || event.button !== 0) return;
		const target = event.target as HTMLElement;
		if (target.closest('.day__pickup') || target.closest('.day__resize')) return;

		const startMinutes = endMinutesAt(event, rowIndex);
		if (startMinutes === null) return;
		let dragged = false;
		swallowClick = false;

		startPointerDrag(event, {
			onStart: () => {
				dragged = true;
				createDrag = { rowIndex, start: startMinutes, end: startMinutes };
			},
			onMove: (moved) => {
				const end = endMinutesAt(moved, rowIndex);
				if (end === null) return;
				createDrag = { rowIndex, start: startMinutes, end };
			},
			onDrop: (dropped) => {
				createDrag = null;
				swallowClick = true;
				const end = endMinutesAt(dropped, rowIndex) ?? startMinutes;
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

	// A click on empty Anytime space in any row books a date-only visit for this day.
	function createAnytime(event: MouseEvent) {
		if (!canCreate) return;
		const target = event.target as HTMLElement;
		if (target.closest('.day__pickup')) return;
		oncreate?.(draftAnytime(day));
	}

	const createGhost = $derived.by(() => {
		if (!createDrag) return null;
		const lo = Math.min(createDrag.start, createDrag.end);
		const hi = Math.max(createDrag.start + 15, createDrag.end);
		return {
			rowIndex: createDrag.rowIndex,
			start: lo,
			end: hi,
			label: `${clockLabel(clockText(lo))} – ${clockLabel(clockText(hi))}`
		};
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="day" style:--day-hour="{HOUR_WIDTH}px" style:--day-lane="{LANE_HEIGHT}px">
	<div class="day__scroll" {@attach openAtWorkingHours}>
		<div class="day__grid">
			<div class="day__head day__head--who"></div>
			<div class="day__head day__head--anytime">Anytime</div>
			<div class="day__head day__head--ruler">
				{#each HOURS as hour (hour)}
					<span class="day__hour" style:left="{hour * HOUR_WIDTH}px">{hourLabel(hour)}</span>
				{/each}
				{#if nowMinutes !== null}
					<span class="day__now-marker" style:left={percent(nowMinutes)} aria-hidden="true"></span>
				{/if}
			</div>

			{#each rows as row, rowIndex (row.key)}
				{@const height = row.lanes * LANE_HEIGHT}
				<div class="day__who" class:day__who--unassigned={row.kind === 'unassigned'}>
					{#if row.kind === 'unassigned'}
						<span class="day__avatar day__avatar--unassigned" aria-hidden="true">
							{@html userOffIcon}
						</span>
					{:else if row.employee}
						<Avatar
							id={row.employee.id}
							name={row.employee.full_name}
							src={row.employee.avatar_url}
							size="small"
						/>
					{:else}
						<span class="day__avatar day__avatar--unlisted" aria-hidden="true">?</span>
					{/if}
					<span class="day__who-text">
						<span class="day__name">{row.name}</span>
						<span class="day__count">{visitCountLabel(row.count)}</span>
					</span>
				</div>

				<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
				<!-- A pointer affordance for booking a date-only visit; the keyboard path is the New Visit
				     button in the page header. -->
				<div
					class="day__anytime"
					class:day__anytime--target={(drag !== null && drag.rowIndex === rowIndex) ||
						(externalStart === null && externalRow === rowIndex)}
					class:day__anytime--bookable={canCreate}
					style:max-height="{height}px"
					bind:this={anytimeEls[rowIndex]}
					onclick={createAnytime}
				>
					{#each row.anytime as visit (visit.id)}
						<div
							class="day__pickup"
							class:day__pickup--dragging={drag?.visit.id === visit.id}
							class:day__pickup--pending={movingVisitId === visit.id}
							onclickcapture={afterDrag}
						>
							<VisitCard
								{visit}
								density="compact"
								{today}
								{employeesById}
								showAssignment={false}
								selected={visit.id === selectedVisitId}
								{onselect}
								onpickup={(event) => beginMove(event, visit, rowIndex, null)}
							/>
						</div>
					{/each}
				</div>

				<!-- svelte-ignore a11y_no_static_element_interactions -->
				<!-- A pointer affordance for booking a visit on empty time; the keyboard path is the New Visit
				     button in the page header. -->
				<div
					class="day__track"
					class:day__track--bookable={canCreate}
					style:height="{height}px"
					bind:this={trackEls[rowIndex]}
					onpointerdown={(event) => beginCreate(event, rowIndex)}
				>
					{#each workingBands as band (band.start)}
						<div
							class="day__working"
							style:left={percent(band.start)}
							style:width={percent(band.end - band.start)}
						></div>
					{/each}

					<div class="day__lines" aria-hidden="true"></div>

					{#each row.blocks as block (block.visit.id)}
						<div
							class="day__block day__pickup"
							class:day__pickup--dragging={drag?.visit.id === block.visit.id}
							class:day__pickup--pending={movingVisitId === block.visit.id}
							style:left={percent(block.start)}
							style:width={percent(block.end - block.start)}
							style:top="{block.column * LANE_HEIGHT}px"
							style:height="{LANE_HEIGHT}px"
							onclickcapture={afterDrag}
						>
							<VisitCard
								visit={block.visit}
								density={cardDensityForWidth(((block.end - block.start) / 60) * HOUR_WIDTH)}
								{today}
								{employeesById}
								showAssignment={false}
								selected={block.visit.id === selectedVisitId}
								{onselect}
								onpickup={(event) => beginMove(event, block.visit, rowIndex, block)}
							/>
							{#if canDragVisit(block.visit, canSchedule)}
								<!-- The trailing edge, for changing how long the work should take. Reschedule is
								     the keyboard path to the same change, so this is decoration to a reader. -->
								<span
									class="day__resize"
									aria-hidden="true"
									onpointerdown={(event) => beginResize(event, block.visit, rowIndex, block)}
								></span>
							{/if}
						</div>
					{/each}

					{#if ghost && ghost.rowIndex === rowIndex}
						<div
							class="day__ghost"
							style:left={percent(ghost.start)}
							style:width={percent(Math.max(15, ghost.end - ghost.start))}
							style:height="{LANE_HEIGHT}px"
							aria-hidden="true"
						>
							<span class="day__ghost-label">{ghost.label}</span>
						</div>
					{/if}

					{#if createGhost && createGhost.rowIndex === rowIndex}
						<div
							class="day__ghost day__ghost--create"
							style:left={percent(createGhost.start)}
							style:width={percent(Math.max(15, createGhost.end - createGhost.start))}
							style:height="{LANE_HEIGHT}px"
							aria-hidden="true"
						>
							<span class="day__ghost-label">{createGhost.label}</span>
						</div>
					{/if}

					{#if externalGhost && externalGhost.rowIndex === rowIndex}
						<div
							class="day__ghost day__ghost--create"
							style:left={percent(externalGhost.start)}
							style:width={percent(Math.max(15, externalGhost.end - externalGhost.start))}
							style:height="{LANE_HEIGHT}px"
							aria-hidden="true"
						>
							<span class="day__ghost-label">{externalGhost.label}</span>
						</div>
					{/if}

					{#if nowMinutes !== null}
						<div class="day__now" style:left={percent(nowMinutes)} aria-hidden="true"></div>
					{/if}
				</div>
			{/each}
		</div>
	</div>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.day {
		--day-who: 208px;
		--day-anytime: 132px;

		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	.day__scroll {
		height: clamp(360px, calc(100vh - 340px), 900px);
		overflow: auto;
		scrollbar-gutter: stable;
	}

	.day__grid {
		display: grid;
		// The two pinned columns keep their width; the hours are as wide as a whole day, and scroll.
		grid-template-columns: var(--day-who) var(--day-anytime) calc(24 * var(--day-hour));
	}

	// The head sits above the rows while they scroll under it, and its first two cells sit above the
	// hours while those scroll past. Opaque backgrounds, or the rows would read straight through.
	.day__head {
		position: sticky;
		top: 0;
		z-index: 2;
		box-sizing: border-box;
		height: 40px;
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface);
	}

	.day__head--who {
		left: 0;
		z-index: 4;
	}

	.day__head--anytime {
		left: var(--day-who);
		z-index: 4;
		display: flex;
		align-items: center;
		justify-content: center;
		border-left: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}

	.day__head--ruler {
		border-left: var(--border-base) solid var(--color-border);
	}

	// The current time is marked once, on the ruler, and then runs as a plain line through every row -- a
	// dot on each of ten rows would be ten times the same fact.
	.day__now-marker {
		position: absolute;
		bottom: 0;
		width: 8px;
		height: 8px;
		margin-left: -4px;
		border-radius: var(--radius-circle);
		background-color: var(--color-critical);
	}

	.day__hour {
		position: absolute;
		top: 50%;
		// Sat on its own line rather than inside the hour it opens, so a label reads as the line's time.
		transform: translate(var(--space-smaller), -50%);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	.day__who {
		position: sticky;
		left: 0;
		z-index: 3;
		display: flex;
		align-items: flex-start;
		gap: var(--space-smaller);
		box-sizing: border-box;
		padding: var(--space-small);
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface);
	}

	// The unassigned pile leads the board and wears the warning colour on its icon and count. The row itself
	// is not filled: a solid band at the top of every day stops being a warning and just becomes the header.
	.day__who--unassigned .day__count {
		color: var(--color-warning--onSurface);
		font-weight: 700;
	}

	.day__who-text {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
	}

	.day__name {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.day__count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
	}

	.day__avatar {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		width: 24px;
		height: 24px;
		border-radius: var(--radius-circle);
		background-color: var(--color-surface--active);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.day__avatar--unassigned {
		background-color: var(--color-warning);
		color: var(--color-surface);
	}

	.day__anytime {
		position: sticky;
		left: var(--day-who);
		z-index: 3;
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		box-sizing: border-box;
		padding: var(--space-smaller);
		overflow-y: auto;
		border-left: var(--border-base) solid var(--color-border);
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface);
	}

	.day__track {
		position: relative;
		box-sizing: border-box;
		border-left: var(--border-base) solid var(--color-border);
		border-bottom: var(--border-base) solid var(--color-border);
		// Outside working hours the row recedes; the working band below paints itself back to the ordinary
		// surface. With no confirmed weekly pattern nothing is painted and the whole day recedes equally,
		// which is honest -- the calendar does not know the hours.
		background-color: var(--color-surface--background);
	}

	.day__working {
		position: absolute;
		top: 0;
		height: 100%;
		background-color: var(--color-surface);
	}

	// Hour lines are painted rather than built: a row of 24 cells for every employee would be hundreds of
	// elements of pure decoration, and this board has real cards to spend that budget on.
	.day__lines {
		position: absolute;
		inset: 0;
		background-image: repeating-linear-gradient(
			to right,
			var(--color-border) 0,
			var(--color-border) 1px,
			transparent 1px,
			transparent var(--day-hour)
		);
		pointer-events: none;
	}

	.day__block {
		position: absolute;
		box-sizing: border-box;
		padding: var(--space-smallest) var(--space-smallest) var(--space-smallest) 0;
	}

	// A card that can be picked up gets out of the way while it is being moved: during a drag the ghost is
	// the thing worth watching, not where the visit used to be.
	.day__pickup {
		touch-action: none;

		&--dragging {
			opacity: 0.35;
		}

		// The proposal is on screen waiting to be saved, so the card is visibly not settled yet.
		&--pending {
			opacity: 0.6;
		}
	}

	.day__resize {
		position: absolute;
		top: var(--space-smallest);
		right: var(--space-smallest);
		bottom: var(--space-smallest);
		width: 8px;
		cursor: ew-resize;

		&::after {
			content: '';
			position: absolute;
			top: 50%;
			right: 2px;
			width: 2px;
			height: 24px;
			border-radius: var(--radius-small);
			background-color: var(--color-border--interactive);
			transform: translateY(-50%);
			opacity: 0;
			transition: opacity var(--timing-quick) ease;
		}
	}

	.day__block:hover .day__resize::after {
		opacity: 1;
	}

	.day__ghost {
		position: absolute;
		top: 0;
		box-sizing: border-box;
		display: flex;
		align-items: center;
		padding: var(--space-smallest) var(--space-smaller);
		border: var(--border-thick) dashed var(--color-interactive);
		border-radius: var(--radius-small);
		background-color: var(--color-informative--surface);
		pointer-events: none;
	}

	// The new-visit ghost reads as a fresh, additive block rather than a moved one.
	.day__ghost--create {
		border-color: var(--color-success);
		background-color: var(--color-success--surface);
	}

	.day__ghost-label {
		color: var(--color-informative--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	.day__ghost--create .day__ghost-label {
		color: var(--color-success--onSurface);
	}

	.day__track--bookable {
		cursor: cell;
	}

	.day__anytime--bookable {
		cursor: cell;
	}

	.day__anytime--target {
		background-color: var(--color-informative--surface);
	}

	.day__now {
		position: absolute;
		top: 0;
		height: 100%;
		border-left: var(--border-thick) solid var(--color-critical);
		pointer-events: none;
	}
</style>
