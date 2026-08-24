<script lang="ts">
	import { Popover, TimeField, TimeRangeField } from 'bits-ui';
	import { parseTime, type Time } from '@internationalized/date';
	import type { TimeOnInvalid, TimeRangeValidator } from 'bits-ui';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import type { TimeRangeValue } from './date-time';
	import {
		addMinutesToTime,
		DEFAULT_RANGE_MINUTES,
		isTimeRangeValid,
		reconcileTimeRange,
		timeToString
	} from './date-time';

	type TimeGranularity = 'hour' | 'minute' | 'second';
	type TimeMenuKey = 'start' | 'end';
	type TimeMenuOption = { value: string; label: string; disabled?: boolean };

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

	// The menu lists times every half hour -- anything odder is typed straight into the field beside it.
	const STEP_MINUTES = 30;

	const rangeValidator: TimeRangeValidator<Time> = (nextValue) => {
		if (!isTimeRangeValid(nextValue)) return 'End time must be after start time.';
		return nextValue.start ? (validate?.(nextValue.start) ?? undefined) : undefined;
	};

	let rangeError = $derived(
		range && value && !isTimeRangeValid(value as TimeRangeValue)
			? 'End time must be after start time.'
			: ''
	);

	// Which field's menu is open; a single field simply uses 'start'.
	let openMenu = $state<TimeMenuKey | null>(null);

	function commitSingle(nextValue: Time | undefined) {
		value = nextValue;
		onchange?.(nextValue);
	}

	// Typed segments land here too, so a hand-entered range goes through the same reconciliation as a
	// picked one: whichever boundary moved keeps its value and the other one carries the visit length.
	function commitRange(nextValue: TimeRangeValue | undefined) {
		value = reconcileTimeRange(
			value as TimeRangeValue,
			nextValue ?? { start: undefined, end: undefined }
		);
		onchange?.(value);
	}

	// Picking a start with no end yet suggests an hour-long visit rather than leaving the range empty.
	function pickStart(nextTime: Time | undefined) {
		const current = value as TimeRangeValue;
		const end =
			current.end ?? (nextTime ? addMinutesToTime(nextTime, DEFAULT_RANGE_MINUTES) : undefined);
		commitRange({ start: nextTime, end });
		openMenu = null;
	}

	function pickEnd(nextTime: Time | undefined) {
		commitRange({ ...(value as TimeRangeValue), end: nextTime });
		openMenu = null;
	}

	const timeOptions = $derived.by(() => {
		const format = new Intl.DateTimeFormat(locale, {
			hour: 'numeric',
			minute: '2-digit',
			hour12: hourCycle === 12
		});
		const options: TimeMenuOption[] = [];
		for (let total = 0; total < 24 * 60; total += STEP_MINUTES) {
			const hour = Math.floor(total / 60);
			options.push({
				value: `${String(hour).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`,
				label: format.format(new Date(2000, 0, 1, hour, total % 60))
			});
		}
		return options;
	});

	// The end list greys out everything at or before the start, so an impossible range cannot be picked.
	const endMenuOptions = $derived.by(() => {
		const start = range ? (value as TimeRangeValue).start : undefined;
		if (!start) return timeOptions;
		const floor = start.hour * 60 + start.minute;
		return timeOptions.map((option) => ({
			...option,
			disabled: Number(option.value.slice(0, 2)) * 60 + Number(option.value.slice(3)) <= floor
		}));
	});

	function toggleMenu(key: TimeMenuKey, nextOpen: boolean) {
		openMenu = nextOpen ? key : null;
	}

	// Opening lands focus on the chosen time so the arrow keys continue from there.
	function focusOnMount(node: HTMLElement) {
		const frame = requestAnimationFrame(() => {
			const options = Array.from(
				node.querySelectorAll<HTMLButtonElement>('button:not([disabled])')
			);
			const selected = options.find((option) => option.getAttribute('aria-selected') === 'true');
			(selected ?? options[0])?.focus({ preventScroll: true });
		});
		return () => cancelAnimationFrame(frame);
	}

	// Arrow keys walk the list the way the calendar's arrow keys walk its grid.
	function handleMenuKeydown(event: KeyboardEvent) {
		if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
		event.preventDefault();
		const container = event.currentTarget as HTMLElement;
		const options = Array.from(
			container.querySelectorAll<HTMLButtonElement>('button:not([disabled])')
		);
		if (!options.length) return;
		const currentIndex = options.indexOf(document.activeElement as HTMLButtonElement);
		let nextIndex = currentIndex;
		if (event.key === 'ArrowDown') {
			nextIndex = currentIndex < 0 ? 0 : Math.min(currentIndex + 1, options.length - 1);
		} else if (event.key === 'ArrowUp') {
			nextIndex = currentIndex < 0 ? options.length - 1 : Math.max(currentIndex - 1, 0);
		} else if (event.key === 'Home') {
			nextIndex = 0;
		} else {
			nextIndex = options.length - 1;
		}
		options[nextIndex]?.focus({ preventScroll: true });
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet timeMenu(
	key: TimeMenuKey,
	current: Time | undefined,
	ariaLabel: string,
	onPick: (next: Time | undefined) => void,
	options: TimeMenuOption[]
)}
	{@const selectedValue = timeToString(current)}
	<Popover.Root
		open={openMenu === key}
		onOpenChange={(nextOpen: boolean) => toggleMenu(key, nextOpen)}
	>
		<Popover.Trigger
			class="time-picker__trigger"
			aria-label={ariaLabel}
			disabled={disabled || readonly}
		>
			{@html clockIcon}
		</Popover.Trigger>

		<Popover.Portal>
			<Popover.Content
				class="time-picker__menu"
				data-elevation="elevated"
				sideOffset={6}
				collisionPadding={8}
			>
				<div
					class="time-picker__options"
					role="listbox"
					aria-label={ariaLabel}
					tabindex={-1}
					{@attach focusOnMount}
					onkeydown={handleMenuKeydown}
				>
					{#each options as option (option.value)}
						<button
							type="button"
							class="time-picker__option"
							role="option"
							aria-selected={selectedValue === option.value}
							disabled={option.disabled}
							tabindex={-1}
							onclick={() => onPick(parseTime(option.value))}
						>
							<span class="time-picker__option-label">{option.label}</span>
							{#if selectedValue === option.value}
								<span class="time-picker__option-check" aria-hidden="true">{@html checkIcon}</span>
							{/if}
						</button>
					{/each}
				</div>
			</Popover.Content>
		</Popover.Portal>
	</Popover.Root>
{/snippet}

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
			onValueChange={commitRange}
		>
			<TimeRangeField.Label class="time-picker__label">{label}</TimeRangeField.Label>
			<div class="time-picker__range-fields">
				<div class="time-picker__range-field">
					<span class="time-picker__range-label">Start</span>
					<div class="time-picker__control">
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

						{@render timeMenu(
							'start',
							(value as TimeRangeValue).start,
							`Open ${label.toLowerCase()} start time picker`,
							pickStart,
							timeOptions
						)}
					</div>
				</div>

				<div class="time-picker__range-field">
					<span class="time-picker__range-label">End</span>
					<div class="time-picker__control">
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

						{@render timeMenu(
							'end',
							(value as TimeRangeValue).end,
							`Open ${label.toLowerCase()} end time picker`,
							pickEnd,
							endMenuOptions
						)}
					</div>
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
			onValueChange={commitSingle}
		>
			<TimeField.Label class="time-picker__label">{label}</TimeField.Label>
			<div class="time-picker__control">
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

				{@render timeMenu(
					'start',
					value as Time | undefined,
					`Open ${label.toLowerCase()} time picker`,
					commitSingle,
					timeOptions
				)}
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

			&__control {
				display: flex;
				min-height: var(--space-largest);
				align-items: center;
				border: var(--border-base) solid var(--color-border--interactive);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				cursor: text;
				transition:
					border-color var(--timing-quick),
					background-color var(--timing-quick),
					box-shadow var(--timing-quick);

				&:focus-within {
					box-shadow: var(--shadow-focus);
				}
			}

			&__input {
				display: flex;
				min-width: 0;
				flex: 1;
				align-items: center;
				gap: 0;
				padding: 0 var(--space-base);
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				line-height: var(--typography--lineHeight-base);
				outline: none;
			}

			&__segment,
			&__literal {
				white-space: pre;
			}

			&__segment {
				padding: var(--space-smaller) var(--space-smallest);
				border-radius: var(--radius-small);
				outline: none;
				cursor: text;

				&:hover {
					background: var(--color-surface--active);
				}

				&:focus {
					color: var(--color-heading);
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
			}

			&__range-label {
				display: block;
				margin-bottom: var(--space-smaller);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			&__trigger {
				display: grid;
				width: var(--space-largest);
				height: var(--space-largest);
				flex: 0 0 auto;
				place-items: center;
				margin-right: var(--space-smaller);
				border: 0;
				border-left: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-small);
				color: var(--color-icon--secondary);
				background: transparent;
				outline: none;
				cursor: pointer;
				transition:
					color var(--timing-quick),
					background-color var(--timing-quick);

				&:hover {
					color: var(--color-heading);
					background: var(--color-surface--hover);
				}

				&:focus-visible {
					box-shadow: var(--shadow-focus);
				}

				&[data-state='open'] {
					color: var(--color-heading);
					background: var(--color-surface--active);
				}

				:global(svg) {
					display: block;
					width: 20px;
					height: 20px;
				}
			}

			&__menu {
				z-index: var(--elevation-tooltip);
				width: min(224px, calc(100vw - var(--space-large)));
				max-height: min(calc(var(--space-extravagant) * 6), var(--bits-floating-available-height));
				padding: var(--space-smaller);
				overflow: hidden;
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				box-shadow: var(--shadow-base);
			}

			&__options {
				max-height: inherit;
				overflow-y: auto;
				outline: none;
			}

			&__option {
				display: flex;
				width: 100%;
				align-items: center;
				justify-content: space-between;
				gap: var(--space-small);
				padding: var(--space-smaller) var(--space-small);
				border: 0;
				border-radius: var(--radius-small);
				outline: none;
				color: var(--color-text);
				background: transparent;
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
				line-height: var(--typography--lineHeight-base);
				text-align: left;
				cursor: pointer;
				transition:
					color var(--timing-quick),
					background-color var(--timing-quick);

				&:hover,
				&:focus-visible {
					color: var(--color-heading);
					background: var(--color-surface--hover);
				}

				&[aria-selected='true'] {
					color: var(--color-heading);
					background: var(--color-surface--active);
				}

				&:disabled {
					color: var(--color-disabled);
					background: transparent;
					cursor: not-allowed;
				}
			}

			&__option-label {
				min-width: 0;
				overflow: hidden;
				text-overflow: ellipsis;
				white-space: nowrap;
			}

			&__option-check {
				display: grid;
				width: 16px;
				height: 16px;
				flex: 0 0 auto;
				place-items: center;
				color: var(--color-interactive);

				svg {
					display: block;
					width: 16px;
					height: 16px;
				}
			}

			&__error {
				padding-top: var(--space-smaller);
				color: var(--color-critical);
				font-size: var(--typography--fontSize-small);
			}

			&--invalid &__control {
				border-color: var(--color-critical);
			}

			&.time-picker--disabled {
				.time-picker__control {
					border-color: var(--color-border);
					background: var(--color-disabled--secondary);
				}

				.time-picker__trigger {
					color: var(--color-disabled);
					background: transparent;
					cursor: not-allowed;
				}

				:global(.time-picker__label),
				:global(.time-picker__input),
				.time-picker__range-label {
					color: var(--color-disabled);
				}
			}
		}
	}
</style>
