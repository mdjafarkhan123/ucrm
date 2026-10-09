<script lang="ts">
	import { Calendar } from 'bits-ui';
	import type { CalendarDate, DateValue } from '@internationalized/date';
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	// Jafar business management E1: the public booking page's month, Calendly's way -- days with an open time stand
	// out and can be chosen; every other day is quiet and cannot. Keyboard and screen-reader behavior is Bits UI's.

	let {
		value = $bindable(),
		month = $bindable(),
		openDays,
		minValue,
		maxValue,
		loading = false
	}: {
		value?: CalendarDate;
		/** Any day in the month shown. */
		month: CalendarDate;
		/** "2026-10-14" for each day with an open time, in the visitor's zone. */
		openDays: Set<string>;
		minValue: CalendarDate;
		maxValue: CalendarDate;
		loading?: boolean;
	} = $props();

	const isUnavailable = (date: DateValue) => loading || !openDays.has(date.toString());
</script>

<Calendar.Root
	type="single"
	class="booking-month"
	weekdayFormat="short"
	fixedWeeks
	preventDeselect
	disableDaysOutsideMonth
	{minValue}
	{maxValue}
	isDateUnavailable={isUnavailable}
	bind:value={
		() => value,
		(next) => {
			value = next as CalendarDate | undefined;
		}
	}
	bind:placeholder={
		() => month,
		(next) => {
			// Bits UI moves its placeholder to the chosen day; only a different month is news to the page.
			if (next && (next.year !== month.year || next.month !== month.month))
				month = next as CalendarDate;
		}
	}
>
	{#snippet children({ months, weekdays })}
		<Calendar.Header class="booking-month__header">
			<Calendar.Heading class="booking-month__heading" />
			<div class="booking-month__nav-group">
				<Calendar.PrevButton class="booking-month__nav" aria-label="Previous month">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html chevronLeftIcon}
				</Calendar.PrevButton>
				<Calendar.NextButton class="booking-month__nav" aria-label="Next month">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html chevronRightIcon}
				</Calendar.NextButton>
			</div>
		</Calendar.Header>

		{#each months as shown (shown.value.toString())}
			<Calendar.Grid class="booking-month__grid" aria-busy={loading}>
				<Calendar.GridHead>
					<Calendar.GridRow class="booking-month__row">
						{#each weekdays as weekday, index (weekday + index)}
							<Calendar.HeadCell class="booking-month__weekday">{weekday}</Calendar.HeadCell>
						{/each}
					</Calendar.GridRow>
				</Calendar.GridHead>
				<Calendar.GridBody>
					{#each shown.weeks as week (week[0]?.toString() ?? 'week')}
						<Calendar.GridRow class="booking-month__row">
							{#each week as date (date.toString())}
								<Calendar.Cell {date} month={shown.value} class="booking-month__cell">
									<Calendar.Day class="booking-month__day" />
								</Calendar.Cell>
							{/each}
						</Calendar.GridRow>
					{/each}
				</Calendar.GridBody>
			</Calendar.Grid>
		{/each}
	{/snippet}
</Calendar.Root>

<style lang="scss">
	// Bits UI renders these parts, so the styles are global, scoped by the booking-month block name.
	:global {
		.booking-month {
			width: 100%;
		}

		.booking-month__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			margin-bottom: var(--space-base);
		}

		.booking-month__heading {
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
			color: var(--color-text);
		}

		.booking-month__nav-group {
			display: flex;
			gap: var(--space-smaller);
		}

		.booking-month__nav {
			display: inline-grid;
			place-items: center;
			width: 2.5rem;
			height: 2.5rem;
			padding: 0;
			border: 0;
			border-radius: var(--radius-circle);
			background: transparent;
			color: var(--color-interactive);
			cursor: pointer;

			svg {
				width: 1.25rem;
				height: 1.25rem;
			}

			&:hover:not([data-disabled]) {
				background: var(--color-interactive--background--subtle--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&[data-disabled] {
				color: var(--color-disabled);
				cursor: default;
			}
		}

		.booking-month__grid {
			width: 100%;
			border-collapse: separate;
			border-spacing: 0 var(--space-smaller);
			table-layout: fixed;
		}

		.booking-month__weekday {
			padding-bottom: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}

		.booking-month__cell {
			padding: 0;
			text-align: center;
		}

		.booking-month__day {
			display: inline-grid;
			place-items: center;
			width: min(2.75rem, 100%);
			aspect-ratio: 1;
			border-radius: var(--radius-circle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			font-variant-numeric: tabular-nums;
			cursor: default;
			user-select: none;

			&[data-outside-month] {
				visibility: hidden;
			}

			&:not([data-unavailable]):not([data-disabled]) {
				background: var(--color-interactive--background--subtle--hover);
				color: var(--color-interactive);
				font-weight: 700;
				cursor: pointer;

				&:hover {
					background: var(--color-success--surface);
				}
			}

			&[data-selected] {
				background: var(--color-interactive) !important;
				color: var(--color-surface) !important;
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&[data-unavailable],
			&[data-disabled] {
				color: var(--color-disabled);
			}
		}
	}
</style>
