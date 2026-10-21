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
	// Look: design skill `layout.md` → Booking page → Month.
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
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}

		.booking-month__nav-group {
			display: flex;
			gap: var(--space-small);
		}

		.booking-month__nav {
			display: inline-grid;
			place-items: center;
			width: 36px;
			height: 36px;
			padding: 0;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-icon);
			box-shadow: var(--shadow-button);
			cursor: pointer;
			transition:
				background-color 120ms ease,
				border-color 120ms ease;

			svg {
				width: 16px;
				height: 16px;
			}

			&:hover:not([data-disabled]) {
				background: var(--color-surface--hover);
			}

			&:active:not([data-disabled]) {
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&[data-disabled] {
				border-color: var(--color-disabled--secondary);
				background: var(--color-disabled--secondary);
				color: var(--color-disabled);
				box-shadow: none;
				cursor: default;
			}
		}

		.booking-month__grid {
			width: 100%;
			border-collapse: separate;
			border-spacing: 0 6px;
			table-layout: fixed;
		}

		.booking-month__weekday {
			height: 28px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		.booking-month__cell {
			padding: 0;
			text-align: center;
		}

		.booking-month__day {
			position: relative;
			display: inline-grid;
			place-items: center;
			width: min(44px, 100%);
			aspect-ratio: 1;
			border: 1.5px solid transparent;
			border-radius: var(--radius-circle);
			color: var(--color-disabled);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			font-variant-numeric: tabular-nums;
			cursor: default;
			user-select: none;
			transition:
				background-color 120ms ease,
				border-color 120ms ease;

			// The small dot under the number: an open day's in the brand colour, today's quiet.
			&::after {
				position: absolute;
				bottom: 7px;
				left: 50%;
				width: 4px;
				height: 4px;
				border-radius: var(--radius-circle);
				transform: translateX(-50%);
				content: none;
			}

			&[data-today]::after {
				background: var(--color-text--secondary);
				content: '';
			}

			&[data-outside-month] {
				visibility: hidden;
			}

			&:not([data-unavailable]):not([data-disabled]) {
				border-color: var(--color-border--interactive);
				background: var(--color-surface);
				color: var(--color-heading);
				font-weight: 700;
				cursor: pointer;

				&::after {
					background: var(--color-interactive);
					content: '';
				}

				&:hover {
					border-color: var(--color-interactive);
					background: var(--color-surface--hover);
				}
			}

			&[data-selected] {
				border-color: var(--color-interactive) !important;
				background: var(--color-interactive) !important;
				color: var(--color-text--reverse) !important;

				&::after {
					content: none;
				}
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}
</style>
