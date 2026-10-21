<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import TimePicker from '$lib/components/ui/TimePicker.svelte';
	import { timeFromString } from '$lib/components/ui/date-time';
	import { WEEKDAY_LABELS } from '$lib/settings/api';
	import { blankDay, dayBlocks, type DayState } from '$lib/settings/weekly-hours';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// The week planner (`inputs.md` → Weekly hours): one row per day, each open or closed, open 24 hours, or up
	// to three periods, with a 24-hour bar that draws what the boxes below it say. It only edits the week it is
	// handed — the page decides when and where that week is saved.
	let {
		days = $bindable(),
		disabled = false,
		idPrefix = 'hours',
		singleColumn = false,
		onchange
	}: {
		days: DayState[];
		disabled?: boolean;
		/** Keeps control ids unique when two editors could share a page. */
		idPrefix?: string;
		/** The narrow column (setup wizard): switches beside the day name, bar and boxes under it. */
		singleColumn?: boolean;
		onchange?: () => void;
	} = $props();

	const SCALE = ['12 AM', '6 AM', '12 PM', '6 PM', '12 AM'];

	function toggleDayOpen(weekday: number, isOpen: boolean) {
		days[weekday] = blankDay(isOpen);
		onchange?.();
	}
	function toggleDay24h(weekday: number, is24h: boolean) {
		days[weekday].is24h = is24h;
		if (is24h) days[weekday].periods = [];
		else if (days[weekday].periods.length === 0)
			days[weekday].periods = [{ start: timeFromString('09:00'), end: timeFromString('17:00') }];
		onchange?.();
	}
	function addPeriod(weekday: number) {
		if (days[weekday].periods.length >= 3) return;
		days[weekday].periods.push({ start: undefined, end: undefined });
		onchange?.();
	}
	function removePeriod(weekday: number, index: number) {
		days[weekday].periods.splice(index, 1);
		onchange?.();
	}
</script>

{#snippet openSwitch(day: DayState, weekday: number)}
	<span class={['weekly-hours__switch', day.isOpen && 'weekly-hours__switch--on']}>
		<Toggle
			id={`${idPrefix}-open-${weekday}`}
			label={day.isOpen ? 'Open' : 'Closed'}
			checked={day.isOpen}
			{disabled}
			onchange={(checked) => toggleDayOpen(weekday, checked)}
		/>
	</span>
{/snippet}

{#snippet allDaySwitch(day: DayState, weekday: number)}
	{#if day.isOpen}
		<Toggle
			id={`${idPrefix}-24h-${weekday}`}
			label="Open 24 hours"
			checked={day.is24h}
			{disabled}
			onchange={(checked) => toggleDay24h(weekday, checked)}
		/>
	{/if}
{/snippet}

<div
	class={[
		'weekly-hours',
		singleColumn && 'weekly-hours--single',
		disabled && 'weekly-hours--disabled'
	]}
>
	<div class="weekly-hours__scale" aria-hidden="true">
		{#if !singleColumn}<span class="weekly-hours__scale-day">Day</span>{/if}
		<span class="weekly-hours__scale-marks">
			{#each SCALE as mark, index (index)}<span>{mark}</span>{/each}
		</span>
	</div>

	{#each days as day, weekday (weekday)}
		<div class={['weekly-hours__day', !day.isOpen && 'weekly-hours__day--closed']}>
			<div class="weekly-hours__day-col">
				<div class="weekly-hours__heading">
					<span class="weekly-hours__tile" aria-hidden="true">
						{WEEKDAY_LABELS[weekday].slice(0, 3)}
					</span>
					<span class="weekly-hours__name">{WEEKDAY_LABELS[weekday]}</span>
					{#if singleColumn}
						<span class="weekly-hours__switches weekly-hours__switches--inline">
							{@render allDaySwitch(day, weekday)}
							{@render openSwitch(day, weekday)}
						</span>
					{/if}
				</div>
				{#if !singleColumn}
					<div class="weekly-hours__switches">
						{@render openSwitch(day, weekday)}
						{@render allDaySwitch(day, weekday)}
					</div>
				{/if}
			</div>

			<div class="weekly-hours__hours">
				<div class="weekly-hours__bar" aria-hidden="true">
					{#each dayBlocks(day) as block, index (index)}
						<span
							class="weekly-hours__block"
							style:left={`calc(${block.left}% + 2px)`}
							style:width={`calc(${block.width}% - 4px)`}>{block.label}</span
						>
					{/each}
				</div>

				{#if day.isOpen && !day.is24h}
					{#each day.periods, index (index)}
						<div class="weekly-hours__period">
							<TimePicker
								bind:value={days[weekday].periods[index]}
								range
								hideRangeLabels
								label={`${WEEKDAY_LABELS[weekday]} period ${index + 1}`}
								{disabled}
								onchange={() => onchange?.()}
							/>
							{#if !disabled}
								<span class="weekly-hours__remove">
									<Button
										variant="secondary"
										size="small"
										iconOnly
										label="Remove this period"
										onclick={() => removePeriod(weekday, index)}
									>
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html xIcon}
									</Button>
								</span>
							{/if}
						</div>
					{/each}
					{#if !disabled && day.periods.length < 3}
						<div class="weekly-hours__add">
							<Button variant="secondary" size="small" onclick={() => addPeriod(weekday)}>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html plusIcon} Add another period
							</Button>
						</div>
					{/if}
				{/if}
			</div>
		</div>
	{/each}
</div>

<style lang="scss">
	.weekly-hours {
		--weekly-hours--day: 240px;
		--weekly-hours--box: 150px;

		display: flex;
		flex-direction: column;
		min-width: 0;

		&__scale {
			display: flex;
			align-items: center;
			gap: 24px;
			padding: 10px 20px;
			background: var(--color-surface--background--subtle);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__scale-day {
			flex: 0 0 var(--weekly-hours--day);
			letter-spacing: 0.7px;
			text-transform: uppercase;
		}

		&__scale-marks {
			display: flex;
			flex: 1 1 auto;
			justify-content: space-between;
			min-width: 0;
		}

		&__day {
			display: flex;
			gap: 24px;
			padding: 16px 20px;
			border-top: var(--border-base) solid var(--color-border);
		}

		&__day-col {
			display: flex;
			flex: 0 0 var(--weekly-hours--day);
			flex-direction: column;
			gap: 12px;
			min-width: 0;
		}

		&__heading {
			display: flex;
			align-items: center;
			gap: 12px;
		}

		&__tile {
			display: grid;
			flex: 0 0 auto;
			width: 40px;
			height: 40px;
			place-items: center;
			border: var(--border-base) solid var(--color-time--surface-edge);
			border-radius: var(--radius-tile-large);
			background: var(--color-time--surface);
			color: var(--color-time--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__switches {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: 10px;
			padding-left: 52px;

			&--inline {
				flex-direction: row;
				align-items: center;
				gap: 16px;
				margin-left: auto;
				padding-left: 0;
			}
		}

		/* "Open" reads in the brand colour; "Closed" stays quiet. */
		&__switch :global(.toggle__label) {
			color: var(--color-text--secondary);
		}

		&__switch--on :global(.toggle__label) {
			color: var(--color-interactive);
		}

		&__hours {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			align-items: flex-start;
			gap: 12px;
			min-width: 0;
			padding-top: 4px;
		}

		&__bar {
			position: relative;
			box-sizing: border-box;
			width: 100%;
			height: 32px;
			flex: 0 0 auto;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			/* A hairline at 6, 12 and 18 hours. */
			background:
				linear-gradient(var(--color-border), var(--color-border)) 25% 0 / 1px 100% no-repeat,
				linear-gradient(var(--color-border), var(--color-border)) 50% 0 / 1px 100% no-repeat,
				linear-gradient(var(--color-border), var(--color-border)) 75% 0 / 1px 100% no-repeat,
				var(--color-surface--background--subtle);
		}

		&__block {
			position: absolute;
			top: 3px;
			bottom: 3px;
			box-sizing: border-box;
			display: grid;
			min-width: 4px;
			padding: 0 6px;
			place-items: center;
			overflow: hidden;
			border-radius: 6px;
			background: var(--color-time);
			color: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__period {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);

			:global(.time-picker__range-fields > .time-picker-field) {
				flex: 0 0 var(--weekly-hours--box);
			}

			:global(.time-picker__range-fields) {
				flex-wrap: nowrap;
			}
		}

		&__remove {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			height: 40px;

			:global(svg) {
				color: var(--color-critical);
			}
		}

		&__add {
			display: flex;
		}

		&__day--closed &__tile,
		&--disabled &__tile {
			border-color: var(--color-inactive--surface-edge);
			background: var(--color-inactive--surface);
			color: var(--color-inactive--onSurface);
		}

		&__day--closed &__name {
			color: var(--color-text--secondary);
		}

		&--disabled &__block {
			background: var(--color-disabled);
		}

		/* One column (setup wizard, 640): the bar and boxes sit under the day's heading row. */
		&--single {
			--weekly-hours--box: 130px;

			overflow: hidden;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&--single &__day {
			flex-direction: column;
			gap: 12px;
		}

		&--single &__day-col {
			flex-basis: auto;
		}

		&--single &__hours {
			padding-top: 0;
		}
	}
</style>
