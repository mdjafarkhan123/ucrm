<script lang="ts">
	import { Time } from '@internationalized/date';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import TimePickerField from '$lib/components/ui/TimePickerField.svelte';
	import { MAX_RANGES_PER_DAY, WEEKDAYS, type BookingHours } from '$lib/jafar/booking';

	// Jafar business management E1: a host's weekly hours, Calendly's way -- each day on or off, with one or more
	// ranges. A day switched on starts 9 to 5; a new range starts an hour after the last one ends.

	let {
		value = $bindable([]),
		errors = {}
	}: {
		value?: BookingHours[];
		/** Messages by the range's index in `value`, from the server. */
		errors?: Record<number, string>;
	} = $props();

	const toTime = (clock: string) => {
		const [hour, minute] = clock.split(':').map(Number);
		return new Time(hour, minute);
	};
	const toClock = (time: Time) =>
		`${String(time.hour).padStart(2, '0')}:${String(time.minute).padStart(2, '0')}`;

	function rangesOf(weekday: number) {
		return value
			.map((range, index) => ({ range, index }))
			.filter(({ range }) => range.weekday === weekday);
	}

	function toggleDay(weekday: number, on: boolean) {
		value = on
			? [...value, { weekday, start: '09:00', end: '17:00' }]
			: value.filter((range) => range.weekday !== weekday);
	}

	function addRange(weekday: number) {
		const last = rangesOf(weekday).at(-1)?.range;
		const startHour = last ? Math.min(Number(last.end.slice(0, 2)) + 1, 22) : 9;
		value = [
			...value,
			{
				weekday,
				start: `${String(startHour).padStart(2, '0')}:00`,
				end: `${String(startHour + 1).padStart(2, '0')}:00`
			}
		];
	}

	function removeRange(index: number) {
		value = value.filter((_, at) => at !== index);
	}

	function setTime(index: number, edge: 'start' | 'end', time: Time | undefined) {
		if (!time) return;
		value = value.map((range, at) => (at === index ? { ...range, [edge]: toClock(time) } : range));
	}
</script>

<ul class="weekly-hours">
	{#each WEEKDAYS as day (day.value)}
		{@const ranges = rangesOf(day.value)}
		<li class="weekly-hours__day">
			<div class="weekly-hours__name">
				<Checkbox
					id={`hours-day-${day.value}`}
					label={day.name}
					checked={ranges.length > 0}
					onchange={(on: boolean) => toggleDay(day.value, on)}
				/>
			</div>
			{#if ranges.length === 0}
				<p class="weekly-hours__off">Not taking bookings</p>
			{:else}
				<div class="weekly-hours__ranges">
					{#each ranges as { range, index } (index)}
						<div class="weekly-hours__range">
							<TimePickerField
								id={`hours-${index}-start`}
								label={`${day.name} start`}
								hideLabel
								value={toTime(range.start)}
								invalid={Boolean(errors[index])}
								onchange={(time) => setTime(index, 'start', time)}
							/>
							<span class="weekly-hours__dash" aria-hidden="true">–</span>
							<TimePickerField
								id={`hours-${index}-end`}
								label={`${day.name} end`}
								hideLabel
								value={toTime(range.end)}
								invalid={Boolean(errors[index])}
								onchange={(time) => setTime(index, 'end', time)}
							/>
							<button
								type="button"
								class="weekly-hours__icon"
								aria-label={`Remove ${day.name} ${range.start} to ${range.end}`}
								onclick={() => removeRange(index)}
							>
								{@html trashIcon}
							</button>
							{#if errors[index]}
								<p class="weekly-hours__error" role="alert">{errors[index]}</p>
							{/if}
						</div>
					{/each}
				</div>
				{#if ranges.length < MAX_RANGES_PER_DAY}
					<button
						type="button"
						class="weekly-hours__icon weekly-hours__add"
						aria-label={`Add another range on ${day.name}`}
						onclick={() => addRange(day.value)}
					>
						{@html plusIcon}
					</button>
				{/if}
			{/if}
		</li>
	{/each}
</ul>

<style lang="scss">
	.weekly-hours {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.weekly-hours__day {
		display: grid;
		grid-template-columns: 9rem 1fr auto;
		gap: var(--space-base);
		align-items: start;
		padding: var(--space-base) 0;
		border-bottom: var(--border-base) solid var(--color-border);

		&:last-child {
			border-bottom: 0;
		}

		@media (max-width: 640px) {
			grid-template-columns: 1fr auto;

			.weekly-hours__ranges,
			.weekly-hours__off {
				grid-column: 1 / -1;
				grid-row: 2;
			}
		}
	}

	.weekly-hours__name {
		min-height: 2.5rem;
		display: flex;
		align-items: center;
	}

	.weekly-hours__off {
		margin: 0;
		min-height: 2.5rem;
		display: flex;
		align-items: center;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.weekly-hours__ranges {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	.weekly-hours__range {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}

	.weekly-hours__dash {
		color: var(--color-text--secondary);
	}

	.weekly-hours__icon {
		display: inline-grid;
		place-items: center;
		width: 2.5rem;
		height: 2.5rem;
		padding: 0;
		border: 0;
		border-radius: var(--radius-base);
		background: transparent;
		color: var(--color-interactive--subtle);
		cursor: pointer;

		:global(svg) {
			width: 1.25rem;
			height: 1.25rem;
		}

		&:hover {
			background: var(--color-interactive--background);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.weekly-hours__error {
		flex-basis: 100%;
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
