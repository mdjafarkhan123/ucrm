<script lang="ts" module>
	/**
	 * Wraps a card's select handler. In a date cell it passes through; in a date's "+ N more" list it closes the
	 * list and hands the list's anchor on, so the preview opens where the list was.
	 */
	export type MonthGridRelay = <A>(
		select: (item: A, element: HTMLElement) => void
	) => (item: A, element: HTMLElement) => void;
</script>

<script lang="ts" generics="T extends { id: string }">
	import type { Snippet } from 'svelte';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import Popover from '$lib/components/ui/Popover.svelte';
	import { formatCalendarDay } from '$lib/schedule/labels';

	// The shared month: six weeks of seven dates, used by the contractor Schedule and the Jafar sales calendar.
	//
	// Month answers "how busy is this month", not "when exactly is this", so there is no time axis here: each
	// date lists a few entries in reading order and says how many more it is holding back. The cell is sized so
	// the date, three cards and the + N more line always fit, and the grid scrolls rather than squeezing six
	// weeks into whatever height is left -- a month that silently drops the last row is worse than one you scroll.
	// Each calendar draws its own cards through `card`.

	let {
		days,
		anchorDate,
		itemsByDay,
		today,
		bookable = false,
		closed,
		attention,
		oncellclick,
		card
	}: {
		/** Every date on the grid, a multiple of seven. */
		days: string[];
		/** The date the calendar is anchored to; it decides which month owns the grid, so padding days dim. */
		anchorDate: string;
		/** Each date's entries, already in reading order. */
		itemsByDay: Map<string, T[]>;
		today: string;
		/** Empty cell space can start a new date-only entry, so it shows the cell cursor. */
		bookable?: boolean;
		/** Whether the business is shut that date, so its cell is shaded. Absent when no hours are known. */
		closed?: (day: string) => boolean;
		/** How many of a date's entries are late or have nobody assigned, said beside its count. */
		attention?: (day: string) => { late: number; unassigned: number };
		/** A click on a cell's empty space -- never one that landed on a card or "+ N more". */
		oncellclick?: (day: string) => void;
		card: Snippet<[T, 'micro' | 'compact', MonthGridRelay]>;
	} = $props();

	/** How many cards a date shows before it starts counting. */
	const VISIBLE_PER_DATE = 3;

	const anchorMonth = $derived(anchorDate.slice(0, 7));

	const cells = $derived(
		days.map((day) => {
			const ordered = itemsByDay.get(day) ?? [];
			return {
				day,
				ordered,
				shown: ordered.slice(0, VISIBLE_PER_DATE),
				hidden: Math.max(0, ordered.length - VISIBLE_PER_DATE),
				inMonth: day.slice(0, 7) === anchorMonth,
				closed: closed?.(day) ?? false,
				attention: attention?.(day) ?? { late: 0, unassigned: 0 }
			};
		})
	);

	// The weekday names come off the first row rather than a hard-coded list, so they can never disagree with
	// the days the grid is actually drawing.
	const weekdays = $derived(cells.slice(0, 7).map((cell) => cell.day));

	const dayHeadingFormat: Intl.DateTimeFormatOptions = {
		weekday: 'long',
		month: 'long',
		day: 'numeric'
	};

	/** The 1st carries its month's name, so a padding cell is never mistaken for this month's date. */
	function dateLabel(day: string) {
		return day.endsWith('-01')
			? formatCalendarDay(day, { month: 'short', day: 'numeric' })
			: formatCalendarDay(day, { day: 'numeric' });
	}

	// One date's whole list, opened from + N more. It is anchored to that button rather than to a card, so
	// picking an entry from the list can close the list and hand the same anchor to the preview -- the way a
	// month calendar normally moves from "everything on this date" to "this one".
	let listDay = $state<string | null>(null);
	let listAnchor = $state<HTMLElement | null>(null);
	const listCell = $derived(listDay ? (cells.find((cell) => cell.day === listDay) ?? null) : null);
	const listItems = $derived(listCell?.ordered ?? []);

	function openList(day: string, element: HTMLElement) {
		listDay = day;
		listAnchor = element;
	}

	function closeList() {
		listDay = null;
		listAnchor = null;
	}

	const inCell: MonthGridRelay = (select) => select;

	const fromList: MonthGridRelay = (select) => (item) => {
		const anchor = listAnchor;
		closeList();
		if (anchor) select(item, anchor);
	};

	function clickCell(event: MouseEvent, day: string) {
		if (!oncellclick) return;
		const target = event.target as HTMLElement;
		if (target.closest('.calendar-month__item') || target.closest('.calendar-month__more')) return;
		oncellclick(day);
	}
</script>

<div class="calendar-month">
	<div class="calendar-month__head">
		{#each weekdays as day (day)}
			<span
				class="calendar-month__weekday"
				class:calendar-month__weekday--today={new Date(day + 'T12:00:00').getDay() ===
					new Date(today + 'T12:00:00').getDay()}
				>{formatCalendarDay(day, { weekday: 'short' })}</span
			>
		{/each}
	</div>

	<div class="calendar-month__body">
		<div class="calendar-month__grid">
			{#each cells as cell (cell.day)}
				<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
				<!-- A pointer affordance for a date-only entry; each calendar's header has the keyboard path. -->
				<div
					class="calendar-month__cell"
					class:calendar-month__cell--outside={!cell.inMonth}
					class:calendar-month__cell--closed={cell.closed}
					class:calendar-month__cell--today={cell.day === today}
					class:calendar-month__cell--bookable={bookable}
					onclick={(event) => clickCell(event, cell.day)}
				>
					<div class="calendar-month__date">
						<span
							class="calendar-month__number"
							title={formatCalendarDay(cell.day, dayHeadingFormat)}
						>
							{dateLabel(cell.day)}
						</span>
						{#if cell.ordered.length > 0 || cell.closed}
							<span class="calendar-month__count">
								{cell.closed ? 'Closed' : cell.ordered.length}
								<span class="calendar-month__count-word">
									{cell.closed ? '' : cell.ordered.length === 1 ? 'item' : 'items'}
								</span>
								{@render attentionMarks(cell.attention)}
							</span>
						{/if}
					</div>

					{#if cell.shown.length > 0}
						<ul class="calendar-month__items">
							{#each cell.shown as item (item.id)}
								<li class="calendar-month__item">{@render card(item, 'micro', inCell)}</li>
							{/each}
						</ul>
					{/if}

					{#if cell.hidden > 0}
						<button
							type="button"
							class="calendar-month__more"
							aria-label={`${cell.hidden} more on ${formatCalendarDay(cell.day, dayHeadingFormat)}`}
							onclick={(event) => openList(cell.day, event.currentTarget)}
						>
							+ {cell.hidden} more
						</button>
					{/if}
				</div>
			{/each}
		</div>
	</div>
</div>

{#snippet attentionMarks(marks: { late: number; unassigned: number })}
	{#if marks.late > 0}
		<span class="calendar-month__attention calendar-month__attention--late">
			<span class="calendar-month__attention-dot" aria-hidden="true"></span>
			{marks.late}
			<span class="calendar-month__count-word">late</span>
		</span>
	{/if}
	{#if marks.unassigned > 0}
		<span class="calendar-month__attention calendar-month__attention--unassigned">
			<span class="calendar-month__attention-dot" aria-hidden="true"></span>
			{marks.unassigned}
			<span class="calendar-month__count-word">unassigned</span>
		</span>
	{/if}
{/snippet}

{#snippet listSubtitle()}
	{#if listCell}
		{listCell.ordered.length}
		{listCell.ordered.length === 1 ? 'item' : 'items'}
		{@render attentionMarks(listCell.attention)}
	{/if}
{/snippet}

{#if listDay}
	<Popover
		concept
		icon={calendarIcon}
		iconTone="time"
		open
		anchor={listAnchor}
		title={formatCalendarDay(listDay, dayHeadingFormat)}
		subtitle={listSubtitle}
		onClose={closeList}
	>
		<ul class="calendar-month-list">
			{#each listItems as item (item.id)}
				<li>{@render card(item, 'compact', fromList)}</li>
			{/each}
		</ul>
	</Popover>
{/if}

<style lang="scss">
	.calendar-month {
		// The cell fits the date row, three cards and the + N more line without measuring anything at runtime.
		// Change the card height and this follows. The grid has no frame of its own: the calendar card around
		// it draws the edge.
		--calendar-month-card: 22px;
		--calendar-month-cell: 154px;

		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		min-height: 320px;
		background-color: var(--color-surface);
	}

	.calendar-month__head,
	.calendar-month__grid {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
		// The body scrolls under a scrollbar; the head keeps the same gutter so its columns line up with it.
		scrollbar-gutter: stable;
	}

	.calendar-month__head {
		flex: 0 0 auto;
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.calendar-month__weekday {
		padding: 11px 14px;
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 600;
		letter-spacing: 0.8px;
		text-transform: uppercase;
	}

	.calendar-month__body {
		// Six weeks keep their full height. The month takes the room the card gives it and scrolls inside it
		// rather than clipping its last row.
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
		scrollbar-gutter: stable;
	}

	.calendar-month__grid {
		grid-auto-rows: minmax(var(--calendar-month-cell), auto);
	}

	.calendar-month__cell {
		display: flex;
		flex-direction: column;
		gap: 5px;
		min-width: 0;
		padding: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
		border-left: var(--border-base) solid var(--color-border);

		&:nth-child(-n + 7) {
			border-top: none;
		}
		&:nth-child(7n + 1) {
			border-left: none;
		}
	}

	.calendar-month__cell--bookable {
		cursor: cell;
	}

	// A padding date still shows its real work; it simply recedes, so the month it belongs to reads as the
	// month on screen.
	.calendar-month__cell--outside {
		.calendar-month__number {
			color: var(--color-text--secondary);
		}
		.calendar-month__items {
			opacity: 0.6;
		}
	}

	// A day the business is shut recedes too; the key at the bottom of the card says what the shading means.
	.calendar-month__cell--closed {
		background: repeating-linear-gradient(
			135deg,
			var(--color-surface) 0 11px,
			var(--color-border) 11px 12px
		);
	}

	.calendar-month__date {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-smaller);
		min-height: 24px;
	}

	.calendar-month__number {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 24px;
		height: 24px;
		padding: 0 var(--space-smaller);
		border-radius: 999px;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-label);
		font-weight: 700;
	}

	.calendar-month__weekday--today {
		color: var(--color-interactive);
		box-shadow: inset 0 -3px var(--color-interactive);
	}
	.calendar-month__cell--today {
		position: relative;
		&::before {
			content: '';
			position: absolute;
			inset: 4px;
			pointer-events: none;
			border: var(--border-base) solid var(--color-interactive);
			border-radius: 10px;
			background: var(--color-surface);
			box-shadow:
				0 6px 16px color-mix(in srgb, var(--color-interactive) 14%, transparent),
				0 1px 2px color-mix(in srgb, var(--color-heading) 8%, transparent);
		}
		> * {
			position: relative;
		}
	}

	.calendar-month__cell--today .calendar-month__number {
		background-color: var(--color-interactive);
		color: var(--color-text--reverse);
	}

	.calendar-month__count {
		display: inline-flex;
		align-items: center;
		gap: 3px var(--space-small);
		flex-wrap: wrap;
		justify-content: flex-end;
		color: var(--color-text--secondary);
		font-size: 11px;
		font-weight: 500;
		white-space: nowrap;
	}

	.calendar-month__attention {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		padding: 3px 7px;
		border-radius: var(--radius-circle);
		font-size: var(--typography--fontSize-overline);
		font-weight: 600;

		&--late {
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}
		&--unassigned {
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
		}
	}

	.calendar-month__attention-dot {
		width: 5px;
		height: 5px;
		border-radius: var(--radius-circle);
		background-color: currentColor;
	}

	.calendar-month__attention--unassigned .calendar-month__attention-dot {
		background-color: var(--color-warning);
	}

	@media (max-width: 767px) {
		.calendar-month {
			min-height: 0;
		}

		.calendar-month__body {
			flex: 0 0 auto;
			max-height: 560px;
		}
	}

	// The word goes first when the cell gets narrow; the number itself never does.
	@media (max-width: 1199px) {
		.calendar-month__count-word {
			display: none;
		}
	}

	.calendar-month__items {
		display: flex;
		flex-direction: column;
		gap: 3px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.calendar-month__item {
		height: var(--calendar-month-card);
	}

	.calendar-month__more {
		align-self: flex-start;
		padding: 0 var(--space-smallest);
		border: none;
		border-radius: var(--radius-small);
		background: none;
		color: var(--color-interactive);
		font-family: inherit;
		font-size: 11px;
		font-weight: 600;
		cursor: pointer;

		&:hover {
			background-color: var(--color-surface--hover);
			color: var(--color-text);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.calendar-month-list {
		display: flex;
		flex-direction: column;
		gap: 6px;
		width: 100%;
		margin: 0;
		padding: 0;
		max-height: 360px;
		overflow-y: auto;
		list-style: none;

		> li {
			flex: 0 0 auto;
			min-height: 40px;
		}
	}
</style>
