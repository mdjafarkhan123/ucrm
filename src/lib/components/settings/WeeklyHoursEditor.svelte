<script lang="ts">
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import TimePicker from '$lib/components/ui/TimePicker.svelte';
	import { timeFromString } from '$lib/components/ui/date-time';
	import { WEEKDAY_LABELS } from '$lib/settings/api';
	import { blankDay, type DayState } from '$lib/settings/weekly-hours';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// The seven-day grid: each day open or closed, open 24 hours, or up to three periods. It only edits the
	// week it is handed — the page decides when and where that week is saved.
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
		/** One day per row, for a narrow column. */
		singleColumn?: boolean;
		onchange?: () => void;
	} = $props();

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

<div class="weekly-hours" class:weekly-hours--single={singleColumn}>
	{#each days as day, weekday (weekday)}
		<div class="weekly-hours__day">
			<div class="weekly-hours__day-header">
				<span class="weekly-hours__day-name">{WEEKDAY_LABELS[weekday]}</span>
				<Toggle
					id={`${idPrefix}-open-${weekday}`}
					label={day.isOpen ? 'Open' : 'Closed'}
					checked={day.isOpen}
					{disabled}
					onchange={(checked) => toggleDayOpen(weekday, checked)}
				/>
			</div>
			{#if day.isOpen}
				<div class="weekly-hours__day-body">
					<Toggle
						id={`${idPrefix}-24h-${weekday}`}
						label="Open 24 hours"
						checked={day.is24h}
						{disabled}
						onchange={(checked) => toggleDay24h(weekday, checked)}
					/>
					{#if !day.is24h}
						{#each day.periods, index (index)}
							<div class="weekly-hours__period">
								<TimePicker
									bind:value={days[weekday].periods[index]}
									range
									label={`${WEEKDAY_LABELS[weekday]} period ${index + 1}`}
									{disabled}
									onchange={() => onchange?.()}
								/>
								{#if !disabled}
									<button
										type="button"
										class="weekly-hours__remove-period"
										aria-label="Remove this period"
										onclick={() => removePeriod(weekday, index)}
										><!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html xIcon}</button
									>
								{/if}
							</div>
						{/each}
						{#if !disabled && day.periods.length < 3}
							<button
								type="button"
								class="weekly-hours__add-period"
								onclick={() => addPeriod(weekday)}
								><!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html plusIcon} Add another period</button
							>
						{/if}
					{/if}
				</div>
			{/if}
		</div>
	{/each}
</div>

<style lang="scss">
	.weekly-hours {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-base);

		&--single {
			grid-template-columns: 1fr;
		}

		&__day {
			min-width: 0;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}
		&__day-header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}
		&__day-name {
			color: var(--color-heading);
			font-weight: 700;
		}
		&__day-body {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-base);
		}
		&__period {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);
		}
		&__remove-period {
			display: grid;
			width: 32px;
			height: 32px;
			flex: 0 0 auto;
			place-items: center;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: var(--color-surface);
			margin-bottom: 2px;
		}
		&__remove-period:hover {
			background: var(--color-surface--hover);
		}
		&__remove-period :global(svg) {
			width: 16px;
			height: 16px;
		}
		&__add-period {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			width: fit-content;
			padding: var(--space-smaller) var(--space-small);
			border: var(--border-base) dashed var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: transparent;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__add-period:hover {
			background: var(--color-surface--hover);
		}
		&__add-period :global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	@media (max-width: 900px) {
		.weekly-hours {
			grid-template-columns: 1fr;
		}
	}
</style>
