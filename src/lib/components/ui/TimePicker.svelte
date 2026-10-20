<script lang="ts">
	import type { Time } from '@internationalized/date';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import TimePickerField from './TimePickerField.svelte';
	import type { TimeRangeValue } from './date-time';
	import { isTimeRangeValid, reconcileTimeRange, timeToMinutes } from './date-time';

	/* eslint-disable svelte/no-unused-props -- locale is accepted for existing callers; hourCycle controls time text. */
	let {
		value = $bindable<Time | TimeRangeValue | undefined>(),
		id,
		range = false,
		label = 'Time',
		hourCycle = 12,
		minValue,
		maxValue,
		startTime,
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
		// Accepted for compatibility; time text follows hourCycle.
		locale?: string;
		hourCycle?: 12 | 24;
		minValue?: Time;
		maxValue?: Time;
		startTime?: Time;
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

	let duration = $derived(
		rangeValue.start && rangeValue.end
			? (timeToMinutes(rangeValue.end) ?? 0) - (timeToMinutes(rangeValue.start) ?? 0)
			: undefined
	);
	let durationLabel = $derived(
		duration === undefined
			? ''
			: duration <= 0
				? 'Check end'
				: `${Math.floor(duration / 60) ? `${Math.floor(duration / 60)} hr` : ''}${duration % 60 ? ` ${duration % 60} min` : ''}`.trim()
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
					{invalid}
					onchange={commitStart}
				/>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="time-picker__separator" aria-hidden="true">{@html arrowRightIcon}</span>
				<TimePickerField
					id={`${fieldId}-end`}
					label="End"
					startTime={rangeValue.start}
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
				{#if durationLabel}<span
						class="time-picker__duration"
						class:time-picker__duration--invalid={Boolean(rangeError)}
						><!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html rangeError ? alertCircleIcon : hourglassIcon}{durationLabel}</span
					>{/if}
			</div>
		</fieldset>
	{:else}
		<TimePickerField
			id={fieldId}
			{startTime}
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
	// Start → End on one line with the length chip after them (concept board "Pickers v2", Time box). The chip
	// drops under the pair when the row is too narrow. The group's name stays for screen readers only, so the
	// Start and End labels line up with the fields beside them.
	.time-picker {
		width: 100%;

		&__fieldset {
			min-width: 0;
			margin: 0;
			padding: 0;
			border: 0;
		}

		legend {
			position: absolute;
			width: 1px;
			height: 1px;
			padding: 0;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		&__range-fields {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			column-gap: var(--space-small);
			row-gap: var(--space-small);

			> :global(.time-picker-field) {
				flex: 1 1 128px;
				width: auto;
			}
		}

		&__separator {
			display: grid;
			height: 40px;
			place-items: center;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__duration {
			display: inline-flex;
			height: 40px;
			flex: 0 0 auto;
			align-items: center;
			gap: 6px;
			padding: 0 14px;
			border-radius: var(--radius-circle);
			background: var(--color-time--surface);
			color: var(--color-time--onSurface);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			white-space: nowrap;

			:global(svg) {
				width: 16px;
				height: 16px;
				color: var(--color-time);
			}

			&--invalid {
				background: var(--color-critical--surface);
				color: var(--color-critical--onSurface);

				:global(svg) {
					color: var(--color-critical);
				}
			}
		}

		&__error {
			padding-top: var(--space-smaller);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
