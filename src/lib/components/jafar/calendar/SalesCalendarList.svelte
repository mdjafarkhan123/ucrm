<script lang="ts">
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import SalesCalendarCard from './SalesCalendarCard.svelte';
	import { formatCalendarDay } from '$lib/schedule/labels';
	import type { CalendarItem } from '$lib/jafar/calendar';

	// Jafar business management C2: the calendar on a phone. Seven columns of a week cannot be read or tapped at
	// that width, so -- as Google Calendar's Schedule view does -- the window becomes one list, a heading per day
	// with its items in order. A day with nothing on it says so once and offers to book a call there.
	let {
		days,
		today,
		itemTime,
		passed,
		onselect,
		onbook
	}: {
		days: { day: string; items: CalendarItem[] }[];
		today: string;
		itemTime: (item: CalendarItem) => string;
		passed: (item: CalendarItem) => boolean;
		onselect: (item: CalendarItem) => void;
		onbook: (day: string) => void;
	} = $props();
</script>

<!-- The icon is a Tabler SVG file imported at build time, not user content. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<ol class="sales-list">
	{#each days as { day, items } (day)}
		<li class="sales-list__day" class:sales-list__day--today={day === today}>
			<div class="sales-list__heading">
				<h2 class="sales-list__date">
					<span class="sales-list__weekday">{formatCalendarDay(day, { weekday: 'short' })}</span>
					<span class="sales-list__number">{formatCalendarDay(day, { day: 'numeric' })}</span>
					<span class="sales-list__month">{formatCalendarDay(day, { month: 'short' })}</span>
				</h2>
				<button
					type="button"
					class="sales-list__book"
					aria-label="Book a call on {formatCalendarDay(day, {
						weekday: 'long',
						month: 'long',
						day: 'numeric'
					})}"
					onclick={() => onbook(day)}
				>
					{@html plusIcon}
				</button>
			</div>
			{#if items.length}
				<ul class="sales-list__items">
					{#each items as item (item.id)}
						<li>
							<SalesCalendarCard
								{item}
								density="standard"
								time={itemTime(item) || 'Any time'}
								passed={passed(item)}
								onselect={(chosen) => onselect(chosen)}
							/>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="sales-list__empty">Nothing booked</p>
			{/if}
		</li>
	{/each}
</ol>

<style lang="scss">
	.sales-list {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.sales-list__day {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
	}

	.sales-list__day--today {
		border-color: var(--color-interactive);
		box-shadow: inset 3px 0 0 var(--color-interactive);
	}

	.sales-list__heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}

	.sales-list__date {
		display: flex;
		align-items: baseline;
		gap: var(--space-smaller);
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}

	.sales-list__weekday,
	.sales-list__month {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
	}

	.sales-list__number {
		font-size: var(--typography--fontSize-larger);
	}

	.sales-list__day--today .sales-list__number {
		color: var(--color-interactive);
	}

	// 44px: a thumb-sized target.
	.sales-list__book {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 44px;
		height: 44px;
		border: 0;
		border-radius: var(--radius-circle);
		background: transparent;
		color: var(--color-interactive);
		cursor: pointer;

		&:hover,
		&:focus-visible {
			background-color: var(--color-interactive--background--subtle--hover);
		}

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.sales-list__items {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;

		// A list row has no grid box to fill, so the card takes its natural height.
		:global(.sales-card) {
			position: relative;
			height: auto;
			min-height: 64px;
		}
	}

	.sales-list__empty {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
