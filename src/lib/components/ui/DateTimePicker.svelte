<script lang="ts">
	import CalendarPicker from './CalendarPicker.svelte';
	import TimePicker from './TimePicker.svelte';
	import type { CalendarDate, Time } from '@internationalized/date';
	import type { DateTimePickerValue } from './date-time';

	let {
		value = $bindable<DateTimePickerValue>({
			date: undefined,
			startTime: undefined,
			endTime: undefined
		}),
		range = false,
		timeRole = 'start',
		dateLabel = 'Date',
		timeLabel = 'Time',
		id,
		locale = 'en-US',
		hourCycle = 12,
		disabled = false,
		readonly = false,
		required = false,
		invalid = false,
		errorMessage = '',
		class: className = '',
		onchange
	}: {
		value?: DateTimePickerValue;
		range?: boolean;
		timeRole?: 'start' | 'end';
		dateLabel?: string;
		timeLabel?: string;
		id: string;
		locale?: string;
		hourCycle?: 12 | 24;
		disabled?: boolean;
		readonly?: boolean;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		class?: string;
		onchange?: (value: DateTimePickerValue) => void;
	} = $props();

	function updateValue(nextValue: Partial<DateTimePickerValue>) {
		value = { ...value, ...nextValue };
		onchange?.(value);
	}

	function handleDateChange(date: CalendarDate | undefined) {
		updateValue({ date });
	}

	function handleSingleTimeChange(
		nextValue: Time | { start: Time | undefined; end: Time | undefined } | undefined
	) {
		if (nextValue && 'start' in nextValue) return;
		updateValue(timeRole === 'start' ? { startTime: nextValue } : { endTime: nextValue });
	}

	function handleRangeTimeChange(
		nextValue: Time | { start: Time | undefined; end: Time | undefined } | undefined
	) {
		if (!nextValue || !('start' in nextValue)) return;
		updateValue({ startTime: nextValue.start, endTime: nextValue.end });
	}
</script>

<div class={['date-time-picker', range && 'date-time-picker--range', className]}>
	<div class="date-time-picker__date">
		<CalendarPicker
			value={value.date}
			id={`${id}-date`}
			label={dateLabel}
			{locale}
			{disabled}
			{readonly}
			{required}
			{invalid}
			onchange={handleDateChange}
		/>
	</div>

	{#if range}
		<TimePicker
			value={{ start: value.startTime, end: value.endTime }}
			range
			label={timeLabel}
			{locale}
			{hourCycle}
			{disabled}
			{readonly}
			{required}
			{invalid}
			onchange={handleRangeTimeChange}
		/>
	{:else}
		<TimePicker
			value={timeRole === 'start' ? value.startTime : value.endTime}
			label={timeLabel}
			{locale}
			{hourCycle}
			{disabled}
			{readonly}
			{required}
			{invalid}
			onchange={handleSingleTimeChange}
		/>
	{/if}

	{#if errorMessage}
		<p class="date-time-picker__error" role="alert">{errorMessage}</p>
	{/if}
</div>

<style lang="scss">
	:global {
		.date-time-picker {
			display: grid;
			grid-template-columns: minmax(0, 1.15fr) minmax(160px, 0.85fr);
			align-items: end;
			gap: var(--space-base);
			width: 100%;

			&--range {
				grid-template-columns: minmax(0, 1fr) minmax(260px, 1fr);
			}

			&__error {
				grid-column: 1 / -1;
				margin-top: calc(var(--space-small) * -1);
				color: var(--color-critical);
				font-size: var(--typography--fontSize-small);
			}
		}

		@media (max-width: 639px) {
			.date-time-picker,
			.date-time-picker--range {
				grid-template-columns: 1fr;
				gap: var(--space-slim);
			}
		}
	}
</style>
