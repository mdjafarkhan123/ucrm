<script lang="ts">
	import { TimeField, TimeRangeField } from 'bits-ui';
	import type { Time } from '@internationalized/date';
	import type { TimeOnInvalid, TimeRangeValidator } from 'bits-ui';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import type { TimeRangeValue } from './date-time';
	import { isTimeRangeValid } from './date-time';

	let {
		value = $bindable<Time | TimeRangeValue | undefined>(),
		range = false,
		label = 'Time',
		locale = 'en-US',
		hourCycle = 12,
		granularity = 'minute',
		minValue,
		maxValue,
		validate,
		onInvalid,
		disabled = false,
		readonly = false,
		required = false,
		invalid = false,
		errorMessage = '',
		class: className = '',
		onchange
	}: {
		value?: Time | TimeRangeValue;
		range?: boolean;
		label?: string;
		locale?: string;
		hourCycle?: 12 | 24;
		granularity?: TimeGranularity;
		minValue?: Time;
		maxValue?: Time;
		validate?: (value: Time) => string | string[] | void;
		onInvalid?: TimeOnInvalid;
		disabled?: boolean;
		readonly?: boolean;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		class?: string;
		onchange?: (value: Time | TimeRangeValue | undefined) => void;
	} = $props();

	type TimeGranularity = 'hour' | 'minute' | 'second';

	const rangeValidator: TimeRangeValidator<Time> = (nextValue) => {
		if (!isTimeRangeValid(nextValue)) return 'End time must be after start time.';
		return nextValue.start ? (validate?.(nextValue.start) ?? undefined) : undefined;
	};

	let rangeError = $derived(
		range && value && !isTimeRangeValid(value as TimeRangeValue)
			? 'End time must be after start time.'
			: ''
	);

	function handleSingleValueChange(nextValue: Time | undefined) {
		value = nextValue;
		onchange?.(nextValue);
	}

	function handleRangeValueChange(nextValue: TimeRangeValue | undefined) {
		value = nextValue ?? { start: undefined, end: undefined };
		onchange?.(value);
	}
</script>

<div
	class={['time-picker', range && 'time-picker--range', className]}
	class:time-picker--invalid={invalid || Boolean(rangeError)}
	class:time-picker--disabled={disabled}
>
	{#if range}
		<TimeRangeField.Root
			value={value as TimeRangeValue}
			{locale}
			{hourCycle}
			{granularity}
			{minValue}
			{maxValue}
			validate={rangeValidator}
			{onInvalid}
			{disabled}
			{readonly}
			{required}
			onValueChange={handleRangeValueChange}
		>
			<TimeRangeField.Label class="time-picker__label">{label}</TimeRangeField.Label>
			<div class="time-picker__range-fields">
				<div class="time-picker__range-field">
					<span class="time-picker__range-label">Start</span>
					<TimeRangeField.Input
						type="start"
						class="time-picker__input"
						aria-label={`${label}, start time`}
						aria-invalid={invalid || Boolean(rangeError)}
					>
						{#snippet children({ segments })}
							{#each segments as segment, segmentIndex (segment.part + '-' + segment.value + '-' + segmentIndex)}
								{#if segment.part === 'literal'}
									<span class="time-picker__literal" aria-hidden="true">{segment.value}</span>
								{:else}
									<TimeRangeField.Segment class="time-picker__segment" part={segment.part}>
										{segment.value}
									</TimeRangeField.Segment>
								{/if}
							{/each}
						{/snippet}
					</TimeRangeField.Input>
				</div>

				<div class="time-picker__range-field">
					<span class="time-picker__range-label">End</span>
					<TimeRangeField.Input
						type="end"
						class="time-picker__input"
						aria-label={`${label}, end time`}
						aria-invalid={invalid || Boolean(rangeError)}
					>
						{#snippet children({ segments })}
							{#each segments as segment, segmentIndex (segment.part + '-' + segment.value + '-' + segmentIndex)}
								{#if segment.part === 'literal'}
									<span class="time-picker__literal" aria-hidden="true">{segment.value}</span>
								{:else}
									<TimeRangeField.Segment class="time-picker__segment" part={segment.part}>
										{segment.value}
									</TimeRangeField.Segment>
								{/if}
							{/each}
						{/snippet}
					</TimeRangeField.Input>
				</div>
			</div>
		</TimeRangeField.Root>
	{:else}
		<TimeField.Root
			value={value as Time | undefined}
			{locale}
			{hourCycle}
			{granularity}
			{minValue}
			{maxValue}
			{validate}
			{onInvalid}
			{disabled}
			{readonly}
			{required}
			onValueChange={handleSingleValueChange}
		>
			<TimeField.Label class="time-picker__label">{label}</TimeField.Label>
			<div class="time-picker__control">
				<span class="time-picker__icon" aria-hidden="true">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html clockIcon}
				</span>
				<TimeField.Input class="time-picker__input" aria-label={label}>
					{#snippet children({ segments })}
						{#each segments as segment, segmentIndex (segment.part + '-' + segment.value + '-' + segmentIndex)}
							{#if segment.part === 'literal'}
								<span class="time-picker__literal" aria-hidden="true">{segment.value}</span>
							{:else}
								<TimeField.Segment class="time-picker__segment" part={segment.part}>
									{segment.value}
								</TimeField.Segment>
							{/if}
						{/each}
					{/snippet}
				</TimeField.Input>
			</div>
		</TimeField.Root>
	{/if}

	{#if errorMessage || rangeError}
		<p class="time-picker__error" role="alert">{errorMessage || rangeError}</p>
	{/if}
</div>

<style lang="scss">
	:global {
		.time-picker {
			width: 100%;
			color: var(--color-heading);

			&__label {
				display: block;
				margin-bottom: var(--space-smaller);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}

			&__control,
			&__input {
				display: flex;
				align-items: center;
			}

			&__control {
				min-height: var(--space-largest);
				gap: var(--space-small);
				padding: 0 var(--space-base);
				border: var(--border-base) solid var(--color-border--interactive);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				transition: box-shadow var(--timing-quick);
			}

			&__input {
				min-width: 0;
				flex: 1;
				gap: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				line-height: var(--typography--lineHeight-base);
				outline: none;
			}

			&__icon {
				display: grid;
				width: 20px;
				height: 20px;
				flex: 0 0 auto;
				place-items: center;
				color: var(--color-icon--secondary);
			}

			&__icon :global(svg) {
				width: 20px;
				height: 20px;
			}

			&__segment,
			&__literal {
				white-space: pre;
			}

			&__segment {
				padding: var(--space-smaller) var(--space-smallest);
				border-radius: var(--radius-small);
				outline: none;

				&:focus {
					background: var(--color-surface--active);
				}
			}

			&__literal {
				color: var(--color-text--secondary);
			}

			&__range-fields {
				display: grid;
				grid-template-columns: repeat(2, minmax(0, 1fr));
				gap: var(--space-small);
			}

			&__range-field {
				min-width: 0;
				padding: var(--space-small) var(--space-slim);
				border: var(--border-base) solid var(--color-border--interactive);
				border-radius: var(--radius-base);
				background: var(--color-surface);
			}

			&__range-label {
				display: block;
				margin-bottom: var(--space-smaller);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			&__error {
				padding-top: var(--space-smaller);
				color: var(--color-critical);
				font-size: var(--typography--fontSize-small);
			}

			&--invalid &__control,
			&--invalid &__range-field {
				border-color: var(--color-critical);
			}

			&.time-picker--disabled {
				.time-picker__control,
				.time-picker__range-field {
					border-color: var(--color-border);
					background: var(--color-disabled--secondary);
				}

				:global(.time-picker__label),
				:global(.time-picker__input) {
					color: var(--color-disabled);
				}
			}
		}
	}
</style>
