<script lang="ts" module>
	import type { WorkingBand } from '$lib/schedule/hours';
	import type { TimedBlock } from '$lib/schedule/layout';

	/** One day of the grid: the dated entries with no clock time, and the timed ones already laid out. */
	export type WeekGridColumn<T extends { id: string }> = {
		day: string;
		anytime: T[];
		blocks: TimedBlock<T>[];
		/** Everything on the day, for the count under its date. */
		count: number;
		/** Working hours painted as the ordinary surface; the rest of the day recedes. */
		working: WorkingBand[];
	};

	/** A dashed outline of where something would go: a move in progress, or a new entry being drawn. */
	export type WeekGridGhost = {
		day: string;
		start: number;
		end: number;
		label: string;
		tone: 'move' | 'create';
	};
</script>

<script lang="ts" generics="T extends { id: string }">
	import { untrack, type Snippet } from 'svelte';
	import type { Attachment } from 'svelte/attachments';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import { itemCountLabel } from '$lib/schedule/items';
	import { MINUTES_IN_DAY } from '$lib/schedule/layout';

	// The shared time grid: day columns over one time axis, used by the contractor Schedule's Week view and the
	// Jafar sales calendar's Day and Week views (one column for a day). It draws the frame -- dates, the Anytime
	// lane, hour labels, working hours, the now line, ghosts -- and places blocks; each calendar draws its own
	// cards through the snippets and owns any dragging, using the measured columns it binds.
	//
	// Hour lines and the working-hours band are painted rather than built: a grid of 7 x 24 cells would be
	// 168 elements of pure decoration, and the view has real cards to spend that budget on.

	let {
		columns,
		today,
		nowMinutes,
		hourHeight,
		openingMinute,
		ghosts = [],
		anytimeLabel = 'Anytime',
		bookable = false,
		anytimeTarget = () => false,
		columnEls = $bindable([]),
		anytimeEls = $bindable([]),
		oncolumnpointerdown,
		onanytimeclick,
		anytimeItem,
		block
	}: {
		columns: WeekGridColumn<T>[];
		today: string;
		/** Minutes past midnight in the calendar's own time zone, or null when today is not on screen. */
		nowMinutes: number | null;
		/** One hour, in pixels. Everything vertical is worked out from it. */
		hourHeight: number;
		/** Where the grid opens scrolled to when it first mounts. */
		openingMinute: number;
		ghosts?: WeekGridGhost[];
		anytimeLabel?: string;
		/** Empty space can start a new entry, so it shows the cell cursor. */
		bookable?: boolean;
		/** Whether a day's Anytime cell is where a drag would land. */
		anytimeTarget?: (day: string) => boolean;
		/** The measured day columns and Anytime cells, for a calendar that turns pointer positions into times. */
		columnEls?: (HTMLElement | undefined)[];
		anytimeEls?: (HTMLElement | undefined)[];
		oncolumnpointerdown?: (event: PointerEvent, index: number) => void;
		onanytimeclick?: (event: MouseEvent, day: string) => void;
		anytimeItem: Snippet<[T, string]>;
		/** Drawn inside a box already placed at the block's time and lane. */
		block: Snippet<[TimedBlock<T>]>;
	} = $props();

	const HOURS = Array.from({ length: 24 }, (_, hour) => hour);

	const anyAnytime = $derived(columns.some((column) => column.anytime.length > 0));

	function percent(minutes: number) {
		return `${(minutes / MINUTES_IN_DAY) * 100}%`;
	}

	function hourLabel(hour: number) {
		if (hour === 0 || hour === 12) return hour === 0 ? '12am' : '12pm';
		return hour < 12 ? `${hour}am` : `${hour - 12}pm`;
	}

	// Read without subscribing, so this runs once when the grid mounts. Tracking it would scroll the view back
	// every time an entry changed, while somebody was reading further down.
	const openAtWorkingHours: Attachment<HTMLElement> = (node) => {
		node.scrollTop = (untrack(() => openingMinute) / 60) * untrack(() => hourHeight);
	};
</script>

<div
	class="calendar-week"
	style:--calendar-week-hour="{hourHeight}px"
	style:--calendar-week-days={columns.length}
>
	<div class="calendar-week__row calendar-week__head">
		<div class="calendar-week__corner"></div>
		{#each columns as column (column.day)}
			<div class="calendar-week__day" class:calendar-week__day--today={column.day === today}>
				<span class="calendar-week__weekday">
					{formatCalendarDay(column.day, { weekday: 'short' })}
				</span>
				<span class="calendar-week__date">{formatCalendarDay(column.day, { day: 'numeric' })}</span>
				{#if column.count > 0}
					<span class="calendar-week__count">{itemCountLabel(column.count)}</span>
				{/if}
			</div>
		{/each}
	</div>

	{#if anyAnytime}
		<div class="calendar-week__row calendar-week__anytime">
			<div class="calendar-week__anytime-label">{anytimeLabel}</div>
			{#each columns as column, index (column.day)}
				<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
				<!-- A pointer affordance for a date-only entry; each calendar's header has the keyboard path. -->
				<div
					class="calendar-week__anytime-column"
					class:calendar-week__anytime-column--target={anytimeTarget(column.day)}
					class:calendar-week__anytime-column--bookable={bookable}
					bind:this={anytimeEls[index]}
					onclick={(event) => onanytimeclick?.(event, column.day)}
				>
					{#each column.anytime as item (item.id)}
						{@render anytimeItem(item, column.day)}
					{/each}
				</div>
			{/each}
		</div>
	{/if}

	<div class="calendar-week__row calendar-week__body" {@attach openAtWorkingHours}>
		<div class="calendar-week__times" style:height="{24 * hourHeight}px">
			{#each HOURS as hour (hour)}
				<span class="calendar-week__hour" style:top="{hour * hourHeight}px">{hourLabel(hour)}</span>
			{/each}
		</div>

		{#each columns as column, index (column.day)}
			<!-- svelte-ignore a11y_no_static_element_interactions -->
			<!-- A pointer affordance for a new entry on empty time; each calendar's header has the keyboard path. -->
			<div
				class="calendar-week__column"
				class:calendar-week__column--bookable={bookable}
				style:height="{24 * hourHeight}px"
				bind:this={columnEls[index]}
				onpointerdown={(event) => oncolumnpointerdown?.(event, index)}
			>
				{#each column.working as band (band.start)}
					<div
						class="calendar-week__working"
						style:top={percent(band.start)}
						style:height={percent(band.end - band.start)}
					></div>
				{/each}

				<div class="calendar-week__lines" aria-hidden="true"></div>

				{#each column.blocks as placed (placed.item.id)}
					<div
						class="calendar-week__block"
						style:top={percent(placed.start)}
						style:height={percent(placed.end - placed.start)}
						style:left="{(placed.column / placed.columns) * 100}%"
						style:width="{(1 / placed.columns) * 100}%"
					>
						{@render block(placed)}
					</div>
				{/each}

				{#each ghosts.filter((ghost) => ghost.day === column.day) as ghost, ghostIndex (ghostIndex)}
					<div
						class="calendar-week__ghost"
						class:calendar-week__ghost--create={ghost.tone === 'create'}
						style:top={percent(ghost.start)}
						style:height={percent(Math.max(15, ghost.end - ghost.start))}
						aria-hidden="true"
					>
						<span class="calendar-week__ghost-label">{ghost.label}</span>
					</div>
				{/each}

				{#if nowMinutes !== null && column.day === today}
					<div class="calendar-week__now" style:top={percent(nowMinutes)} aria-hidden="true"></div>
				{/if}
			</div>
		{/each}
	</div>
</div>

<style lang="scss">
	.calendar-week {
		--calendar-week-gutter: 56px;

		display: flex;
		flex-direction: column;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		overflow: hidden;
	}

	.calendar-week__row {
		display: grid;
		grid-template-columns: var(--calendar-week-gutter) repeat(
				var(--calendar-week-days),
				minmax(0, 1fr)
			);
	}

	.calendar-week__head {
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface);
	}

	.calendar-week__corner {
		border-right: var(--border-base) solid var(--color-border);
	}

	.calendar-week__day {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-smallest);
		padding: var(--space-small) var(--space-smaller);
		border-left: var(--border-base) solid var(--color-border);
	}

	.calendar-week__weekday {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
	}

	.calendar-week__date {
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

	.calendar-week__day--today .calendar-week__date {
		background-color: var(--color-interactive);
		color: var(--color-surface);
	}

	.calendar-week__count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
	}

	.calendar-week__anytime {
		border-bottom: var(--border-base) solid var(--color-border);
		background-color: var(--color-surface--background--subtle);
	}

	.calendar-week__anytime-label {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		padding: var(--space-small) var(--space-smaller);
		border-right: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-align: right;
	}

	.calendar-week__anytime-column {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		padding: var(--space-smaller);
		max-height: 112px;
		overflow-y: auto;
		border-left: var(--border-base) solid var(--color-border);
	}

	.calendar-week__body {
		// The gutter scrolls with the columns, so the hour labels can never drift away from their lines.
		height: clamp(360px, calc(100vh - 340px), 900px);
		overflow-y: auto;
		scrollbar-gutter: stable;
	}

	.calendar-week__times {
		position: relative;
		border-right: var(--border-base) solid var(--color-border);
	}

	.calendar-week__hour {
		position: absolute;
		right: var(--space-small);
		// Sat on its own line rather than inside the hour it opens, so a label reads as the line's time.
		transform: translateY(-50%);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	.calendar-week__column {
		position: relative;
		border-left: var(--border-base) solid var(--color-border);
		// Outside working hours the column recedes; the working band paints itself back to the ordinary
		// surface. With no known hours nothing is painted and the whole day recedes equally.
		background-color: var(--color-surface--background);
	}

	.calendar-week__working {
		position: absolute;
		left: 0;
		width: 100%;
		background-color: var(--color-surface);
	}

	.calendar-week__lines {
		position: absolute;
		inset: 0;
		background-image: repeating-linear-gradient(
			to bottom,
			var(--color-border) 0,
			var(--color-border) 1px,
			transparent 1px,
			transparent var(--calendar-week-hour)
		);
		pointer-events: none;
	}

	.calendar-week__block {
		position: absolute;
		box-sizing: border-box;
		padding-right: var(--space-smallest);
	}

	.calendar-week__ghost {
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

	// A new entry reads as a fresh, additive block rather than a moved one.
	.calendar-week__ghost--create {
		border-color: var(--color-success);
		background-color: var(--color-success--surface);
	}

	.calendar-week__ghost-label {
		color: var(--color-informative--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
		white-space: nowrap;
	}

	.calendar-week__ghost--create .calendar-week__ghost-label {
		color: var(--color-success--onSurface);
	}

	.calendar-week__column--bookable,
	.calendar-week__anytime-column--bookable {
		cursor: cell;
	}

	.calendar-week__anytime-column--target {
		background-color: var(--color-informative--surface);
	}

	.calendar-week__now {
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
