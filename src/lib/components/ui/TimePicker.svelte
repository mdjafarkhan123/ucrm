<script lang="ts">
	import type { Time } from '@internationalized/date';
	import TimePickerField from './TimePickerField.svelte';
	import type { TimeRangeValue } from './date-time';
	import { isTimeRangeValid, reconcileTimeRange } from './date-time';

	let {
		value = $bindable<Time | TimeRangeValue | undefined>(),
		id,
		range = false,
		label = 'Time',
		hourCycle = 12,
		minValue,
		maxValue,
		disabled = false,
		readonly = false,
		required = false,
		invalid = false,
		errorMessage = '',
		class: className = '',
		onchange
	}: {
		value?: Time | TimeRangeValue;
		id?: string;
		range?: boolean;
		label?: string;
		locale?: string;
		hourCycle?: 12 | 24;
		minValue?: Time;
		maxValue?: Time;
		disabled?: boolean;
		readonly?: boolean;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		class?: string;
		onchange?: (value: Time | TimeRangeValue | undefined) => void;
	} = $props();

	const generatedId = $props.id();
	let fieldId = $derived(id ?? `time-${generatedId}`);
	let rangeValue = $derived(
		range && value && 'start' in value ? value : { start: undefined, end: undefined }
	);
	let rangeError = $derived(
		range && !isTimeRangeValid(rangeValue) ? 'End time must be after start time.' : ''
	);

	function commitSingle(nextValue: Time | undefined) {
		value = nextValue;
		onchange?.(value);
	}

	function commitStart(start: Time | undefined) {
		const nextValue = reconcileTimeRange(rangeValue, { ...rangeValue, start });
		value = nextValue;
		onchange?.(value);
	}

	function commitEnd(end: Time | undefined) {
		value = { ...rangeValue, end };
		onchange?.(value);
	}
</script>

<div class={['time-picker', range && 'time-picker--range', className]}>
	{#if range}
		<fieldset class="time-picker__fieldset">
			<legend>{label}</legend>
			<div class="time-picker__range-fields">
				<TimePickerField
					id={`${fieldId}-start`}
					label="Start"
					value={rangeValue.start}
					{hourCycle}
					{minValue}
					{maxValue}
					{disabled}
					{readonly}
					{required}
					invalid={invalid || Boolean(rangeError)}
					onchange={commitStart}
				/>
				<span class="time-picker__separator" aria-hidden="true">to</span>
				<TimePickerField
					id={`${fieldId}-end`}
					label="End"
					value={rangeValue.end}
					{hourCycle}
					{minValue}
					{maxValue}
					{disabled}
					{readonly}
					{required}
					invalid={invalid || Boolean(rangeError)}
					onchange={commitEnd}
				/>
			</div>
		</fieldset>
	{:else}
		<TimePickerField
			id={fieldId}
			{label}
			value={value && !('start' in value) ? value : undefined}
			{hourCycle}
			{minValue}
			{maxValue}
			{disabled}
			{readonly}
			{required}
			{invalid}
			{errorMessage}
			onchange={commitSingle}
		/>
	{/if}

	{#if range && (errorMessage || rangeError)}
		<p class="time-picker__error" role="alert">{errorMessage || rangeError}</p>
	{/if}
</div>

<style lang="scss">
	.time-picker {
		width: 100%;

		&__fieldset {
			min-width: 0;
			margin: 0;
			padding: 0;
			border: 0;
		}

		legend {
			margin-bottom: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}

		&__range-fields {
			display: grid;
			grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
			align-items: end;
			gap: var(--space-small);
		}

		&__separator {
			padding-bottom: calc(var(--space-largest) / 2 - var(--space-small));
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			padding-top: var(--space-smaller);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		@media (max-width: 479px) {
			&__range-fields {
				grid-template-columns: 1fr;
			}

			&__separator {
				display: none;
			}
		}
	}
</style>
