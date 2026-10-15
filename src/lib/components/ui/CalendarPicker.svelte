<script lang="ts">
	import { onMount } from 'svelte';
	import { DatePicker, Popover } from 'bits-ui';
	import type { CalendarDate, DateValue } from '@internationalized/date';
	import { today, getLocalTimeZone } from '@internationalized/date';
	import type { DateMatcher, DateOnInvalid, DateValidator } from 'bits-ui';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	let {
		value = $bindable<CalendarDate | undefined>(),
		id,
		name,
		label = 'Date',
		hideLabel = false,
		placeholder,
		locale,
		weekStartsOn = 0,
		minValue,
		maxValue,
		isDateDisabled,
		isDateUnavailable,
		validate,
		onInvalid,
		disabled = false,
		readonly = false,
		required = false,
		invalid = false,
		errorMessage = '',
		class: className = '',
		size = 'base',
		onchange
	}: {
		value?: CalendarDate | undefined;
		id: string;
		name?: string;
		label?: string;
		/** Keeps the label for screen readers only, for places like a filter row that already show it. */
		hideLabel?: boolean;
		placeholder?: CalendarDate;
		locale?: string;
		weekStartsOn?: WeekStartsOn;
		minValue?: CalendarDate;
		maxValue?: CalendarDate;
		isDateDisabled?: DateMatcher;
		isDateUnavailable?: DateMatcher;
		validate?: DateValidator;
		onInvalid?: DateOnInvalid;
		disabled?: boolean;
		readonly?: boolean;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		class?: string;
		/** `small` matches the 34px controls of a toolbar such as the calendar bar. */
		size?: 'base' | 'small';
		onchange?: (value: CalendarDate | undefined) => void;
	} = $props();

	type WeekStartsOn = 0 | 1 | 2 | 3 | 4 | 5 | 6;
	let open = $state(false);
	const currentDate = today(getLocalTimeZone());
	const todayValidation = $derived(validate?.(currentDate));
	const todayDisabled = $derived(
		disabled ||
			readonly ||
			(minValue !== undefined && currentDate.compare(minValue) < 0) ||
			(maxValue !== undefined && currentDate.compare(maxValue) > 0) ||
			Boolean(isDateDisabled?.(currentDate)) ||
			Boolean(isDateUnavailable?.(currentDate)) ||
			((typeof todayValidation === 'string' || Array.isArray(todayValidation)) &&
				todayValidation.length > 0)
	);
	// Day, month and year are typed in the order of the viewer's browser language, as the browser's own date boxes
	// do: a US browser shows 10/09/2026 for 9 October, a UK one 09/10/2026. The server cannot know it, so a page
	// drawn there starts in US order until it reaches the browser.
	let browserLocale = $state('en-US');
	onMount(() => {
		browserLocale = navigator.language || 'en-US';
	});
	const fieldLocale = $derived(locale ?? browserLocale);
	const labelClass = $derived(
		hideLabel ? 'calendar-picker__label calendar-picker__label--hidden' : 'calendar-picker__label'
	);

	function handleValueChange(nextValue: DateValue | undefined) {
		value = nextValue as CalendarDate | undefined;
		onchange?.(value);
	}

	function focusCalendarWithoutScrolling(event: Event) {
		event.preventDefault();
		document.querySelector<HTMLElement>('[data-bits-day][data-focused]')?.focus({
			preventScroll: true
		});
	}
</script>

<div
	class={['calendar-picker', className]}
	class:calendar-picker--invalid={invalid}
	class:calendar-picker--disabled={disabled}
	class:calendar-picker--small={size === 'small'}
>
	<!-- Bits UI reads the language once, so the field is drawn again when the browser's arrives. -->
	{#key fieldLocale}
		<DatePicker.Root
			bind:open
			{value}
			{placeholder}
			locale={fieldLocale}
			{weekStartsOn}
			{minValue}
			{maxValue}
			{isDateDisabled}
			{isDateUnavailable}
			{validate}
			{onInvalid}
			{disabled}
			{readonly}
			{required}
			calendarLabel={label}
			onValueChange={handleValueChange}
		>
			<DatePicker.Label class={labelClass}>{label}</DatePicker.Label>

			<div class="calendar-picker__control">
				<DatePicker.Input
					{id}
					{name}
					class="calendar-picker__input"
					aria-invalid={invalid}
					aria-describedby={errorMessage ? `${id}-error` : undefined}
				>
					{#snippet children({ segments })}
						{#each segments as segment, segmentIndex (segment.part + '-' + segmentIndex)}
							{#if segment.part === 'literal'}
								<span class="calendar-picker__literal" aria-hidden="true">{segment.value}</span>
							{:else}
								<DatePicker.Segment class="calendar-picker__segment" part={segment.part}>
									{segment.value}
								</DatePicker.Segment>
							{/if}
						{/each}
					{/snippet}
				</DatePicker.Input>

				<DatePicker.Trigger
					class="calendar-picker__trigger"
					aria-label={`Open ${label.toLowerCase()} calendar`}
				>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html calendarIcon}
				</DatePicker.Trigger>
			</div>

			<DatePicker.Portal>
				<Popover.Content
					class="calendar-picker__content"
					data-elevation="elevated"
					sideOffset={6}
					collisionPadding={8}
					onOpenAutoFocus={focusCalendarWithoutScrolling}
				>
					<DatePicker.Calendar>
						{#snippet children({ months, weekdays })}
							<DatePicker.Header class="calendar-picker__header">
								<DatePicker.PrevButton class="calendar-picker__nav" aria-label="Previous month">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html chevronLeftIcon}
								</DatePicker.PrevButton>
								<DatePicker.Heading class="calendar-picker__heading" />
								<DatePicker.NextButton class="calendar-picker__nav" aria-label="Next month">
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html chevronRightIcon}
								</DatePicker.NextButton>
							</DatePicker.Header>

							{#each months as month (month.value.toString())}
								<DatePicker.Grid class="calendar-picker__grid">
									<DatePicker.GridHead>
										<DatePicker.GridRow>
											{#each weekdays as weekday, weekdayIndex (weekday + '-' + weekdayIndex)}
												<DatePicker.HeadCell class="calendar-picker__weekday"
													>{weekday}</DatePicker.HeadCell
												>
											{/each}
										</DatePicker.GridRow>
									</DatePicker.GridHead>

									<DatePicker.GridBody>
										{#each month.weeks as week (week[0]?.toString() ?? 'week')}
											<DatePicker.GridRow>
												{#each week as date (date.toString())}
													<DatePicker.Cell {date} month={month.value}>
														{#snippet children({ selected, disabled: dayDisabled, unavailable })}
															<DatePicker.Day>
																{#snippet children({ day })}
																	<span
																		class={[
																			'calendar-picker__day',
																			selected && 'is-selected',
																			dayDisabled && 'is-disabled',
																			unavailable && 'is-unavailable'
																		]}>{day}</span
																	>
																{/snippet}
															</DatePicker.Day>
														{/snippet}
													</DatePicker.Cell>
												{/each}
											</DatePicker.GridRow>
										{/each}
									</DatePicker.GridBody>
								</DatePicker.Grid>
							{/each}
						{/snippet}
					</DatePicker.Calendar>

					<footer class="calendar-picker__footer">
						<span class="calendar-picker__keyboard-hint">Use arrow keys to navigate</span>
						{#if value}<span class="calendar-picker__selected-date">Selected</span>{/if}
						<span class="calendar-picker__legend"><span>Today</span><span>Chosen</span></span>
						<button
							class="calendar-picker__today"
							type="button"
							disabled={todayDisabled}
							onclick={() => {
								if (todayDisabled) return;
								handleValueChange(currentDate);
								open = false;
							}}>Today</button
						>
					</footer>
				</Popover.Content>
			</DatePicker.Portal>
		</DatePicker.Root>
	{/key}

	{#if errorMessage}
		<p class="calendar-picker__error" id={`${id}-error`} role="alert">{errorMessage}</p>
	{/if}
</div>

<style lang="scss">
	.calendar-picker__legend,
	.calendar-picker__today {
		display: none;
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) {
		:global(.calendar-picker__control) {
			border-color: var(--classic2-border-input);
			border-radius: 12px;
			background: var(--classic2-surface);
		}
		:global(.calendar-picker__control:focus-within) {
			outline: 2px solid var(--classic2-green);
			outline-offset: 2px;
			box-shadow: none;
		}
		:global(.calendar-picker__input),
		:global(.calendar-picker__label) {
			color: var(--classic2-ink);
			font-family: var(--classic2-font);
			font-size: 13px;
		}
		:global(.calendar-picker__literal),
		:global(.calendar-picker__trigger) {
			color: var(--classic2-muted);
		}
		:global(.calendar-picker__content) {
			width: min(330px, calc(100vw - 24px));
			padding: 16px;
			border-color: var(--classic2-border);
			border-radius: 16px;
			background: var(--classic2-surface-raised);
			box-shadow: 0 12px 32px var(--classic2-shadow-lift);
			font-family: var(--classic2-font);
		}
		:global(.calendar-picker__header) {
			grid-template-columns: 1fr 30px 30px;
			gap: 4px;
			padding: 0;
			background: transparent;
		}
		:global(.calendar-picker__heading) {
			grid-column: 1;
			grid-row: 1;
			text-align: left;
			color: var(--classic2-ink);
			font-size: 14px;
		}
		:global(.calendar-picker__nav) {
			width: 30px;
			height: 30px;
			border: 1px solid var(--classic2-border-control);
			border-radius: 9px;
			color: var(--classic2-ink);
		}
		:global(.calendar-picker__nav:first-child) {
			grid-column: 2;
			grid-row: 1;
		}
		:global(.calendar-picker__nav:last-child) {
			grid-column: 3;
			grid-row: 1;
		}
		:global(.calendar-picker__nav:hover),
		:global(.calendar-picker__trigger:hover),
		:global(.calendar-picker__segment:hover),
		:global(.calendar-picker__segment:focus) {
			background: var(--classic2-surface-soft);
			color: var(--classic2-ink);
		}
		:global(.calendar-picker__nav:focus-visible),
		:global(.calendar-picker__trigger:focus-visible) {
			outline: 2px solid var(--classic2-green);
			outline-offset: 2px;
			box-shadow: none;
		}
		:global(.calendar-picker__weekday) {
			color: var(--classic2-muted);
			font-size: 11px;
		}
		:global(.calendar-picker__day) {
			width: 38px;
			max-width: 100%;
			height: 38px;
			border-radius: 10px;
			color: var(--classic2-ink);
			font-size: 13px;
		}
		:global([data-highlighted] .calendar-picker__day),
		:global([data-focused] .calendar-picker__day) {
			background: var(--classic2-surface-soft);
		}
		:global([data-today]:not([data-selected]) .calendar-picker__day) {
			border-color: var(--classic2-solid-green);
			color: var(--classic2-green);
		}
		:global([data-selected] .calendar-picker__day) {
			border-color: var(--classic2-solid-green);
			background: var(--classic2-solid-green);
			color: var(--classic2-white);
		}
		:global([data-disabled] .calendar-picker__day),
		:global([data-outside-month] .calendar-picker__day) {
			color: var(--classic2-muted);
		}
		:global(.calendar-picker--invalid .calendar-picker__control),
		:global(.calendar-picker--invalid .calendar-picker__control:focus-within) {
			border-color: var(--classic2-rose);
			outline-color: var(--classic2-rose);
		}
		:global(.calendar-picker--disabled .calendar-picker__control) {
			background: var(--classic2-surface-soft);
			border-color: var(--classic2-border);
		}
		:global(.calendar-picker__error) {
			color: var(--classic2-rose);
		}
		:global(.calendar-picker__footer) {
			border-color: var(--classic2-divider);
			color: var(--classic2-muted);
			font-size: 11px;
		}
		.calendar-picker__keyboard-hint,
		.calendar-picker__selected-date {
			display: none;
		}
		.calendar-picker__legend {
			display: flex;
			gap: 12px;
			span {
				display: inline-flex;
				align-items: center;
				gap: 5px;
			}
			span::before {
				content: '';
				width: 10px;
				height: 10px;
				border: 1px solid var(--classic2-solid-green);
				border-radius: 3px;
			}
			span:last-child::before {
				background: var(--classic2-solid-green);
			}
		}
		.calendar-picker__today {
			display: block;
			height: 30px;
			padding: 0 10px;
			border: 1px solid var(--classic2-border-control);
			border-radius: 9px;
			color: var(--classic2-ink);
			background: var(--classic2-surface);
			font-size: 12px;
			font-weight: 600;
			cursor: pointer;
		}
		.calendar-picker__today:hover:not(:disabled) {
			background: var(--classic2-surface-soft);
		}
		.calendar-picker__today:focus-visible {
			outline: 2px solid var(--classic2-green);
			outline-offset: 2px;
		}
		.calendar-picker__today:disabled {
			opacity: 0.5;
			cursor: not-allowed;
		}
	}

	:global {
		.calendar-picker {
			width: 100%;
			color: var(--color-heading);

			&__label {
				display: block;
				margin-bottom: var(--space-smaller);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
			}

			&__label--hidden {
				position: absolute;
				width: 1px;
				height: 1px;
				margin: 0;
				overflow: hidden;
				clip: rect(0 0 0 0);
				white-space: nowrap;
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

			&__trigger,
			&__nav {
				display: grid;
				place-items: center;
				border: 0;
				color: var(--color-icon--secondary);
				background: transparent;
				outline: none;
				transition:
					color var(--timing-quick),
					background-color var(--timing-quick),
					box-shadow var(--timing-quick);

				&:hover {
					color: var(--color-heading);
					background: var(--color-surface--hover);
				}

				&:focus-visible {
					box-shadow: var(--shadow-focus);
				}
			}

			&__trigger {
				width: var(--space-largest);
				height: var(--space-largest);
				margin-right: var(--space-smaller);
				border-radius: var(--radius-small);
				border-left: var(--border-base) solid var(--color-border);
				cursor: pointer;
			}

			&__trigger :global(svg),
			&__nav :global(svg) {
				width: 20px;
				height: 20px;
			}

			&--small &__control {
				min-height: 34px;
			}

			&--small &__input {
				padding: 0 var(--space-small);
				font-size: var(--typography--fontSize-small);
			}

			&--small &__segment {
				padding-block: var(--space-minuscule);
			}

			&--small &__trigger {
				width: 32px;
				height: 32px;
				margin-right: 0;
			}

			&--small &__trigger :global(svg) {
				width: 16px;
				height: 16px;
			}

			&__content {
				z-index: var(--elevation-tooltip);
				width: min(328px, calc(100vw - var(--space-large)));
				padding: var(--space-base);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				box-shadow: var(--shadow-base);
			}

			&__header {
				display: grid;
				grid-template-columns: 36px 1fr 36px;
				align-items: center;
				gap: var(--space-small);
				margin-bottom: var(--space-base);
				padding: var(--space-smaller);
				border-radius: var(--radius-small);
				background: var(--color-surface--background--subtle);
			}

			&__nav {
				width: 36px;
				height: 36px;
				border-radius: var(--radius-base);
				color: var(--color-interactive--subtle);
			}

			&__heading {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 700;
				text-align: center;
			}

			&__grid {
				width: 100%;
				border-collapse: separate;
				border-spacing: 0 var(--space-smaller);
			}

			&__weekday {
				padding-bottom: var(--space-small);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
				line-height: var(--typography--lineHeight-tighter);
				text-align: center;
			}

			&__day {
				display: grid;
				width: 36px;
				height: 36px;
				place-items: center;
				border: var(--border-base) solid transparent;
				border-radius: var(--radius-circle);
				color: var(--color-text);
				font-size: var(--typography--fontSize-base);
				line-height: 1;
				transition:
					color var(--timing-quick),
					background-color var(--timing-quick),
					border-color var(--timing-quick);
			}

			:global([data-selected] .calendar-picker__day) {
				border-color: var(--color-interactive);
				color: var(--color-surface);
				background: var(--color-interactive);
				font-weight: 700;
			}

			:global([data-today]:not([data-selected]) .calendar-picker__day) {
				border-color: var(--color-interactive);
				color: var(--color-interactive--subtle);
				font-weight: 700;
			}

			:global([data-highlighted] .calendar-picker__day),
			:global([data-focused] .calendar-picker__day) {
				background: var(--color-surface--hover);
			}

			:global([data-disabled] .calendar-picker__day),
			:global([data-outside-month] .calendar-picker__day) {
				color: var(--color-disabled);
				opacity: 0.55;
			}

			&__footer {
				display: flex;
				align-items: center;
				justify-content: space-between;
				margin-top: var(--space-base);
				padding-top: var(--space-slim);
				border-top: var(--border-base) solid var(--color-border);
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			&__selected-date {
				padding: var(--space-smallest) var(--space-small);
				border-radius: var(--radius-circle);
				color: var(--color-success);
				background: var(--color-success--surface);
				font-weight: 600;
			}

			&__error {
				padding-top: var(--space-smaller);
				color: var(--color-critical);
				font-size: var(--typography--fontSize-small);
			}

			&--invalid &__control {
				border-color: var(--color-critical);
			}

			&.calendar-picker--disabled {
				.calendar-picker__control {
					border-color: var(--color-border);
					background: var(--color-disabled--secondary);
				}

				:global(.calendar-picker__label),
				:global(.calendar-picker__input) {
					color: var(--color-disabled);
				}
			}
		}
	}
</style>
