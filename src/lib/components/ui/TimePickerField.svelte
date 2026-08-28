<script lang="ts">
	import { Popover } from 'bits-ui';
	import { Time } from '@internationalized/date';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import { formatTimeText, parseTimeText, timeToMinutes } from './date-time';

	let {
		value = $bindable<Time | undefined>(),
		id,
		label,
		hideLabel = false,
		hourCycle = 12,
		minValue,
		maxValue,
		disabled = false,
		readonly = false,
		required = false,
		invalid = false,
		errorMessage = '',
		onchange
	}: {
		value?: Time;
		id: string;
		label: string;
		hideLabel?: boolean;
		hourCycle?: 12 | 24;
		minValue?: Time;
		maxValue?: Time;
		disabled?: boolean;
		readonly?: boolean;
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		onchange?: (value: Time | undefined) => void;
	} = $props();

	let open = $state(false);
	let touched = $state(false);
	let localError = $state('');
	let draft = $derived(formatTimeText(value, hourCycle));
	let selected = $derived(value ?? parseTimeText(draft) ?? new Time(9, 0));
	let shownError = $derived(errorMessage || localError);
	let minuteOptions = $derived.by(() => {
		const values = Array.from({ length: 12 }, (_, index) => index * 5);
		if (!values.includes(selected.minute)) values.push(selected.minute);
		return values.sort((a, b) => a - b);
	});
	let hourOptions = $derived(
		hourCycle === 12
			? Array.from({ length: 12 }, (_, index) => index + 1)
			: Array.from({ length: 24 }, (_, index) => index)
	);
	let selectedDisplayHour = $derived(hourCycle === 12 ? selected.hour % 12 || 12 : selected.hour);
	let selectedPeriod = $derived(selected.hour >= 12 ? 'PM' : 'AM');

	function withinLimits(nextValue: Time) {
		const minutes = timeToMinutes(nextValue) ?? 0;
		return (
			(minValue === undefined || minutes >= (timeToMinutes(minValue) ?? 0)) &&
			(maxValue === undefined || minutes <= (timeToMinutes(maxValue) ?? 0))
		);
	}

	function commit(nextValue: Time | undefined) {
		touched = true;
		if (!nextValue) {
			if (required) {
				localError = 'Enter a time.';
				return false;
			}
			value = undefined;
			draft = '';
			localError = '';
			onchange?.(value);
			return true;
		}

		if (!withinLimits(nextValue)) {
			localError = 'Choose a time within the allowed range.';
			return false;
		}

		value = nextValue;
		draft = formatTimeText(nextValue, hourCycle);
		localError = '';
		onchange?.(value);
		return true;
	}

	function commitDraft() {
		const trimmed = draft.trim();
		if (!trimmed) return commit(undefined);
		const parsed = parseTimeText(trimmed);
		if (!parsed) {
			touched = true;
			localError = 'Enter a valid time, such as 9:30 AM.';
			return false;
		}
		return commit(parsed);
	}

	function handleInput(event: Event) {
		draft = (event.currentTarget as HTMLInputElement).value;
		if (touched) localError = '';
	}

	function handleInputKeydown(event: KeyboardEvent) {
		if (event.key === 'Enter') {
			event.preventDefault();
			if (commitDraft()) open = false;
		}
		if (event.key === 'Escape') {
			draft = formatTimeText(value, hourCycle);
			localError = '';
		}
	}

	function updateHour(hour: number) {
		const nextHour = hourCycle === 24 ? hour : (hour % 12) + (selectedPeriod === 'PM' ? 12 : 0);
		commit(new Time(nextHour, selected.minute));
	}

	function updateMinute(minute: number) {
		commit(new Time(selected.hour, minute));
	}

	function updatePeriod(period: 'AM' | 'PM') {
		const hour = (selected.hour % 12) + (period === 'PM' ? 12 : 0);
		commit(new Time(hour, selected.minute));
	}

	function navigateOptions(event: KeyboardEvent) {
		if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
		event.preventDefault();
		const options = Array.from(
			(event.currentTarget as HTMLElement).parentElement?.querySelectorAll<HTMLElement>(
				'[role="option"]'
			) ?? []
		);
		const currentIndex = options.indexOf(event.currentTarget as HTMLElement);
		const nextIndex =
			event.key === 'Home'
				? 0
				: event.key === 'End'
					? options.length - 1
					: (currentIndex + (event.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length;
		options[nextIndex]?.focus();
	}
</script>

<Popover.Root bind:open>
	<div
		class={[
			'time-picker-field',
			(invalid || shownError) && 'time-picker-field--invalid',
			disabled && 'time-picker-field--disabled'
		]}
	>
		<label
			class={['time-picker-field__label', hideLabel && 'time-picker-field__label--hidden']}
			for={id}
			>{label}{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</label
		>
		<div class="time-picker-field__control">
			<input
				{id}
				type="text"
				inputmode="numeric"
				autocomplete="off"
				placeholder={hourCycle === 12 ? '9:30 AM' : '09:30'}
				value={draft}
				{disabled}
				{readonly}
				aria-invalid={invalid || Boolean(shownError)}
				aria-describedby={shownError ? `${id}-error` : undefined}
				oninput={handleInput}
				onblur={commitDraft}
				onkeydown={handleInputKeydown}
			/>
			<Popover.Trigger
				class="time-picker-field__trigger"
				aria-label={`Choose ${label.toLowerCase()}`}
				disabled={disabled || readonly}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html clockIcon}
			</Popover.Trigger>
		</div>
		{#if shownError}
			<p class="time-picker-field__error" id={`${id}-error`} role="alert">{shownError}</p>
		{/if}
	</div>

	<Popover.Portal>
		<Popover.Content
			class="time-picker-field__popover"
			data-elevation="elevated"
			sideOffset={6}
			collisionPadding={8}
		>
			<div class="time-picker-field__summary" aria-live="polite">
				<span>{label}</span>
				<strong>{formatTimeText(selected, hourCycle)}</strong>
			</div>
			<div class="time-picker-field__columns">
				<div class="time-picker-field__column-wrap">
					<span class="time-picker-field__column-label">Hour</span>
					<div class="time-picker-field__column" role="listbox" aria-label="Hour">
						{#each hourOptions as hour (hour)}
							<button
								type="button"
								role="option"
								aria-selected={selectedDisplayHour === hour}
								tabindex={selectedDisplayHour === hour ? 0 : -1}
								onclick={() => updateHour(hour)}
								onkeydown={navigateOptions}
								>{String(hour).padStart(hourCycle === 24 ? 2 : 1, '0')}</button
							>
						{/each}
					</div>
				</div>
				<div class="time-picker-field__column-wrap">
					<span class="time-picker-field__column-label">Minute</span>
					<div class="time-picker-field__column" role="listbox" aria-label="Minute">
						{#each minuteOptions as minute (minute)}
							<button
								type="button"
								role="option"
								aria-selected={selected.minute === minute}
								tabindex={selected.minute === minute ? 0 : -1}
								onclick={() => updateMinute(minute)}
								onkeydown={navigateOptions}>{String(minute).padStart(2, '0')}</button
							>
						{/each}
					</div>
				</div>
				{#if hourCycle === 12}
					<div class="time-picker-field__column-wrap time-picker-field__column-wrap--period">
						<span class="time-picker-field__column-label">Period</span>
						<div class="time-picker-field__column" role="listbox" aria-label="AM or PM">
							{#each ['AM', 'PM'] as period (period)}
								<button
									type="button"
									role="option"
									aria-selected={selectedPeriod === period}
									tabindex={selectedPeriod === period ? 0 : -1}
									onclick={() => updatePeriod(period as 'AM' | 'PM')}
									onkeydown={navigateOptions}>{period}</button
								>
							{/each}
						</div>
					</div>
				{/if}
			</div>
			<footer class="time-picker-field__footer">
				<span>Arrow keys move through each column</span>
				<button type="button" onclick={() => (open = false)}>Done</button>
			</footer>
		</Popover.Content>
	</Popover.Portal>
</Popover.Root>

<style lang="scss">
	.time-picker-field {
		position: relative;
		width: 100%;
		padding-top: var(--space-small);

		&__label {
			position: absolute;
			z-index: var(--elevation-base);
			top: 0;
			left: var(--space-slim);
			max-width: calc(100% - var(--space-large));
			padding: 0 var(--space-smaller);
			overflow: hidden;
			color: var(--color-text--secondary);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			line-height: var(--space-base);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__label--hidden {
			width: 1px;
			height: 1px;
			padding: 0;
			overflow: hidden;
			clip: rect(0 0 0 0);
			white-space: nowrap;
		}

		&__control {
			display: flex;
			min-height: var(--space-largest);
			align-items: center;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			transition:
				border-color var(--timing-quick),
				box-shadow var(--timing-quick);

			&:focus-within {
				box-shadow: var(--shadow-focus);
			}
		}

		input {
			width: 100%;
			min-width: 0;
			padding: var(--space-base);
			border: 0;
			outline: 0;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
		}

		input::placeholder {
			color: var(--color-text--secondary);
		}

		&__error {
			padding-top: var(--space-smaller);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&--invalid &__control {
			border-color: var(--color-critical);
		}

		&--disabled &__control {
			border-color: var(--color-border);
			background: var(--color-disabled--secondary);
		}
	}

	:global(.time-picker-field__trigger) {
		display: grid;
		width: var(--space-largest);
		height: var(--space-largest);
		flex: 0 0 auto;
		place-items: center;
		border: 0;
		border-left: var(--border-base) solid var(--color-border);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
		transition:
			color var(--timing-quick),
			background-color var(--timing-quick);
	}

	:global(.time-picker-field__trigger:hover),
	:global(.time-picker-field__trigger[data-state='open']) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}

	:global(.time-picker-field__trigger:focus-visible) {
		box-shadow: var(--shadow-focus);
	}

	:global(.time-picker-field__trigger svg) {
		width: 20px;
		height: 20px;
	}

	:global(.time-picker-field__popover) {
		z-index: var(--elevation-tooltip);
		width: min(320px, calc(100vw - var(--space-large)));
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.time-picker-field__summary) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding-bottom: var(--space-slim);
		border-bottom: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	:global(.time-picker-field__summary strong) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}

	:global(.time-picker-field__columns) {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-small);
		padding: var(--space-base) 0;
	}

	:global(.time-picker-field__column-wrap) {
		min-width: 0;
	}

	:global(.time-picker-field__column-label) {
		display: block;
		padding-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-align: center;
	}

	:global(.time-picker-field__column) {
		display: grid;
		max-height: 216px;
		gap: var(--space-smallest);
		overflow-y: auto;
		padding: var(--space-smallest);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
		scrollbar-width: thin;
	}

	:global(.time-picker-field__column button) {
		min-height: 36px;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: transparent;
		font: inherit;
		font-weight: 600;
		cursor: pointer;
	}

	:global(.time-picker-field__column button:hover),
	:global(.time-picker-field__column button:focus-visible) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
		outline: none;
		box-shadow: var(--shadow-focus);
	}

	:global(.time-picker-field__column button[aria-selected='true']) {
		color: var(--color-surface);
		background: var(--color-interactive);
	}

	:global(.time-picker-field__footer) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding-top: var(--space-slim);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	:global(.time-picker-field__footer button) {
		padding: var(--space-smaller) var(--space-base);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-surface);
		background: var(--color-interactive);
		font: inherit;
		font-weight: 700;
		cursor: pointer;
	}

	@media (max-width: 479px) {
		:global(.time-picker-field__popover) {
			width: min(296px, calc(100vw - var(--space-base)));
		}

		:global(.time-picker-field__footer span) {
			display: none;
		}

		:global(.time-picker-field__footer) {
			justify-content: flex-end;
		}
	}
</style>
