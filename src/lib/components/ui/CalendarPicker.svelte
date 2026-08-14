<script lang="ts">
	import { DatePicker, Popover } from 'bits-ui';
	import type { CalendarDate, DateValue } from '@internationalized/date';
	import type { DateMatcher, DateOnInvalid, DateValidator } from 'bits-ui';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import chevronLeftIcon from '@tabler/icons/outline/chevron-left.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';

	let {
		value = $bindable<CalendarDate | undefined>(),
		id,
		name,
		label = 'Date',
		placeholder,
		locale = 'en-US',
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
		onchange
	}: {
		value?: CalendarDate | undefined;
		id: string;
		name?: string;
		label?: string;
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
		onchange?: (value: CalendarDate | undefined) => void;
	} = $props();

	type WeekStartsOn = 0 | 1 | 2 | 3 | 4 | 5 | 6;
	let open = $state(false);

	function handleValueChange(nextValue: DateValue | undefined) {
		value = nextValue as CalendarDate | undefined;
		onchange?.(value);
	}

	function openCalendar() {
		open = true;
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
>
	<DatePicker.Root
		bind:open
		{value}
		{placeholder}
		{locale}
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
		<DatePicker.Label class="calendar-picker__label">{label}</DatePicker.Label>

		<div class="calendar-picker__control">
			<DatePicker.Input
				{id}
				{name}
				class="calendar-picker__input"
				aria-invalid={invalid}
				aria-describedby={errorMessage ? `${id}-error` : undefined}
				onclick={openCalendar}
			>
				{#snippet children({ segments })}
					{#each segments as segment, segmentIndex (segment.part + '-' + segment.value + '-' + segmentIndex)}
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
					<span>Use arrow keys to navigate</span>
					{#if value}<span class="calendar-picker__selected-date">Selected</span>{/if}
				</footer>
			</Popover.Content>
		</DatePicker.Portal>
	</DatePicker.Root>

	{#if errorMessage}
		<p class="calendar-picker__error" id={`${id}-error`} role="alert">{errorMessage}</p>
	{/if}
</div>

<style lang="scss">
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

			&__control {
				display: flex;
				min-height: var(--space-largest);
				align-items: center;
				border: var(--border-base) solid var(--color-border--interactive);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				box-shadow: var(--shadow-low);
				cursor: text;
				transition:
					border-color var(--timing-quick),
					background-color var(--timing-quick),
					box-shadow var(--timing-quick);

				&:hover {
					border-color: var(--color-interactive--subtle);
					background: var(--color-surface--hover);
				}

				&:focus-within {
					border-color: var(--color-interactive);
					background: var(--color-surface);
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

			&__content {
				z-index: var(--elevation-tooltip);
				width: min(328px, calc(100vw - var(--space-large)));
				padding: var(--space-base);
				border: var(--border-base) solid var(--color-border);
				border-radius: var(--radius-base);
				background: var(--color-surface);
				box-shadow: var(--shadow-high);
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
