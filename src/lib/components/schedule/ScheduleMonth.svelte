<script lang="ts">
	import Popover from '$lib/components/ui/Popover.svelte';
	import VisitCard from '$lib/components/schedule/VisitCard.svelte';
	import AssessmentCard from '$lib/components/schedule/AssessmentCard.svelte';
	import EventCard from '$lib/components/schedule/EventCard.svelte';
	import { bucketVisitsByDay, orderDayVisits } from '$lib/schedule/grouping';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { eachDayInWindow, type ScheduleWindow } from '$lib/schedule/filters';
	import { draftAnytime, type NewVisitDraft } from '$lib/schedule/drag';
	import type { AssessmentItem, EventItem, ScheduleItem } from '$lib/schedule/items';
	import type { ScheduleVisit } from '$lib/schedule/api';
	import type { TeamMember } from '$lib/team/api';

	// The month, as six weeks of seven dates.
	//
	// Month answers "how busy is this month", not "when exactly is this visit", so there is no time axis
	// here: each date lists a few visits in reading order and says how many more it is holding back. The
	// cell is sized so the date, three cards and the + N more line always fit, and the grid scrolls rather
	// than squeezing six weeks into whatever height is left -- a month that silently drops the last row is
	// worse than one you scroll.

	let {
		window: activeWindow,
		anchorDate,
		items,
		today,
		employeesById,
		selectedItemId,
		canCreate = false,
		onselect,
		onselectassessment,
		onselectevent,
		oncreate
	}: {
		window: ScheduleWindow;
		/** The date the calendar is anchored to. It decides which month owns the grid, so the padding days
		 * either side can be dimmed without being hidden. */
		anchorDate: string;
		/** Already filtered by the page. Every one of these is drawn or counted -- visits and assessments. */
		items: ScheduleItem[];
		today: string;
		employeesById: Map<string, TeamMember>;
		selectedItemId: string | null;
		/** Whether this reader may start a Job from empty space. A month cell only becomes clickable with it. */
		canCreate?: boolean;
		onselect: (visit: ScheduleVisit, element: HTMLElement) => void;
		/** An assessment card was selected. The page opens its Request-owned preview. */
		onselectassessment: (assessment: AssessmentItem, element: HTMLElement) => void;
		/** An event card was selected. The page opens its Schedule-owned preview. */
		onselectevent: (event: EventItem, element: HTMLElement) => void;
		/** A click on empty cell space books a date-only visit for that date -- the same date-only visit the
		 *  Anytime lane creates. The page opens the create form; nothing is written until it is saved. */
		oncreate?: (draft: NewVisitDraft) => void;
	} = $props();

	/** How many cards a date shows before it starts counting. */
	const VISIBLE_PER_DATE = 3;

	const byDay = $derived(bucketVisitsByDay(items));
	const anchorMonth = $derived(anchorDate.slice(0, 7));

	const cells = $derived(
		eachDayInWindow(activeWindow).map((day) => {
			const ordered = orderDayVisits(byDay.get(day) ?? []);
			return {
				day,
				ordered,
				shown: ordered.slice(0, VISIBLE_PER_DATE),
				hidden: Math.max(0, ordered.length - VISIBLE_PER_DATE),
				inMonth: day.slice(0, 7) === anchorMonth
			};
		})
	);

	// The weekday names come off the first row rather than a hard-coded list, so they can never disagree
	// with the days the grid is actually drawing.
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
	// picking a visit from the list can close the list and hand the same anchor to the shared preview --
	// the way a month calendar normally moves from "everything on this date" to "this one visit".
	let listDay = $state<string | null>(null);
	let listAnchor = $state<HTMLElement | null>(null);
	const listItems = $derived(
		listDay ? (cells.find((cell) => cell.day === listDay)?.ordered ?? []) : []
	);

	function openList(day: string, element: HTMLElement) {
		listDay = day;
		listAnchor = element;
	}

	function closeList() {
		listDay = null;
		listAnchor = null;
	}

	// Picking from the day's list closes it and hands the same anchor to whichever preview the item owns.
	function selectVisitFromList(visit: ScheduleVisit) {
		const anchor = listAnchor;
		closeList();
		if (anchor) onselect(visit, anchor);
	}

	function selectAssessmentFromList(assessment: AssessmentItem) {
		const anchor = listAnchor;
		closeList();
		if (anchor) onselectassessment(assessment, anchor);
	}

	function selectEventFromList(event: EventItem) {
		const anchor = listAnchor;
		closeList();
		if (anchor) onselectevent(event, anchor);
	}

	// A click on a cell's empty space books a date-only visit for that date. A click that landed on a card
	// or the "+ N more" button belongs to that control, so this bows out.
	function createOnDate(event: MouseEvent, day: string) {
		if (!canCreate) return;
		const target = event.target as HTMLElement;
		if (target.closest('.month__item') || target.closest('.month__more')) return;
		oncreate?.(draftAnytime(day));
	}
</script>

<div class="month">
	<div class="month__head">
		{#each weekdays as day (day)}
			<span class="month__weekday">{formatCalendarDay(day, { weekday: 'short' })}</span>
		{/each}
	</div>

	<div class="month__body">
		<div class="month__grid">
			{#each cells as cell (cell.day)}
				<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
				<!-- A pointer affordance for booking a date-only visit; the keyboard path is the New Visit
				     button in the page header. -->
				<div
					class="month__cell"
					class:month__cell--outside={!cell.inMonth}
					class:month__cell--today={cell.day === today}
					class:month__cell--bookable={canCreate}
					onclick={(event) => createOnDate(event, cell.day)}
				>
					<div class="month__date">
						<span class="month__number" title={formatCalendarDay(cell.day, dayHeadingFormat)}>
							{dateLabel(cell.day)}
						</span>
						{#if cell.ordered.length > 0}
							<span class="month__count">
								{cell.ordered.length}
								<span class="month__count-word">{cell.ordered.length === 1 ? 'item' : 'items'}</span
								>
							</span>
						{/if}
					</div>

					{#if cell.shown.length > 0}
						<ul class="month__items">
							{#each cell.shown as item (item.id)}
								<li class="month__item">
									{#if item.kind === 'visit'}
										<VisitCard
											visit={item}
											density="micro"
											{today}
											{employeesById}
											selected={item.id === selectedItemId}
											{onselect}
										/>
									{:else if item.kind === 'assessment'}
										<AssessmentCard
											assessment={item}
											density="micro"
											{today}
											{employeesById}
											selected={item.id === selectedItemId}
											onselect={onselectassessment}
										/>
									{:else}
										<EventCard
											event={item}
											density="micro"
											selected={item.id === selectedItemId}
											onselect={onselectevent}
										/>
									{/if}
								</li>
							{/each}
						</ul>
					{/if}

					{#if cell.hidden > 0}
						<button
							type="button"
							class="month__more"
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

{#if listDay}
	<Popover
		open
		anchor={listAnchor}
		title={formatCalendarDay(listDay, dayHeadingFormat)}
		onClose={closeList}
	>
		<ul class="month-list">
			{#each listItems as item (item.id)}
				<li class="month-list__item">
					{#if item.kind === 'visit'}
						<VisitCard
							visit={item}
							density="compact"
							{today}
							{employeesById}
							selected={item.id === selectedItemId}
							onselect={selectVisitFromList}
						/>
					{:else if item.kind === 'assessment'}
						<AssessmentCard
							assessment={item}
							density="compact"
							{today}
							{employeesById}
							selected={item.id === selectedItemId}
							onselect={selectAssessmentFromList}
						/>
					{:else}
						<EventCard
							event={item}
							density="compact"
							selected={item.id === selectedItemId}
							onselect={selectEventFromList}
						/>
					{/if}
				</li>
			{/each}
		</ul>
	</Popover>
{/if}

<style lang="scss">
	.month {
		// The cell fits the date row, three micro cards and the + N more line without measuring anything at
		// runtime. Change the card height and this follows.
		--month-card: 22px;
		--month-cell: 132px;

		display: flex;
		flex-direction: column;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	.month__head,
	.month__grid {
		display: grid;
		grid-template-columns: repeat(7, minmax(0, 1fr));
	}

	.month__head {
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.month__weekday {
		padding: var(--space-small) var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: center;
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
	}

	.month__body {
		// Six weeks keep their full height. On a short screen the month scrolls instead of quietly clipping
		// its last row.
		max-height: clamp(360px, calc(100vh - 300px), 900px);
		overflow-y: auto;
		scrollbar-gutter: stable;
	}

	.month__grid {
		grid-auto-rows: minmax(var(--month-cell), auto);
	}

	.month__cell {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		min-width: 0;
		padding: var(--space-smaller);
		border-top: var(--border-base) solid var(--color-border);
		border-left: var(--border-base) solid var(--color-border);

		&:nth-child(-n + 7) {
			border-top: none;
		}
		&:nth-child(7n + 1) {
			border-left: none;
		}
	}

	.month__cell--bookable {
		cursor: cell;
	}

	// A padding date still shows its real work; it simply recedes, so the month it belongs to reads as the
	// month on screen.
	.month__cell--outside {
		background-color: var(--color-surface--background);

		.month__number {
			color: var(--color-text--secondary);
		}
	}

	.month__date {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-smaller);
		min-height: 24px;
	}

	.month__number {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 24px;
		height: 24px;
		padding: 0 var(--space-smallest);
		border-radius: var(--radius-circle);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}

	.month__cell--today .month__number {
		background-color: var(--color-interactive);
		color: var(--color-surface);
	}

	.month__count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		white-space: nowrap;
	}

	// The word goes first when the cell gets narrow; the number itself never does.
	@media (max-width: 1199px) {
		.month__count-word {
			display: none;
		}
	}

	.month__items {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.month__item {
		height: var(--month-card);
	}

	.month__more {
		align-self: flex-start;
		padding: 0 var(--space-smallest);
		border: none;
		border-radius: var(--radius-small);
		background: none;
		color: var(--color-text--secondary);
		font-family: inherit;
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
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

	.month-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0;
		max-height: 320px;
		overflow-y: auto;
		list-style: none;
	}
</style>
