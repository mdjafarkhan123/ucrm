<script lang="ts">
	import { Popover } from 'bits-ui';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	// A table card's date filter, drawn like its Status and Type chips: the name, then the answer
	// ("Any time", or the dates picked), then a chevron. Opening it shows the From and To pickers. A range
	// that has been set shows a cross that puts it back to "Any time" in one click.
	let {
		id,
		label,
		from = '',
		to = '',
		emptyLabel = 'Any time',
		onchange
	}: {
		id: string;
		label: string;
		/** The start day as `YYYY-MM-DD`, or empty for no start. */
		from?: string;
		/** The end day as `YYYY-MM-DD`, or empty for no end. */
		to?: string;
		emptyLabel?: string;
		onchange: (range: { from: string; to: string }) => void;
	} = $props();

	let open = $state(false);

	const active = $derived(from !== '' || to !== '');
	const formatter = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	function show(day: string) {
		const value = calendarDateFromString(day);
		return value ? formatter.format(new Date(value.year, value.month - 1, value.day)) : '';
	}
	const summary = $derived.by(() => {
		if (from && to) return `${show(from)} – ${show(to)}`;
		if (from) return `From ${show(from)}`;
		if (to) return `Until ${show(to)}`;
		return emptyLabel;
	});

	function clear() {
		onchange({ from: '', to: '' });
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span class={['date-range-chip', active && 'date-range-chip--on']}>
	<Popover.Root bind:open>
		<Popover.Trigger
			class="date-range-chip__trigger"
			aria-label={active ? `${label}: ${summary}` : label}
		>
			<span class="date-range-chip__icon" aria-hidden="true">{@html calendarIcon}</span>
			<span class="date-range-chip__label">{label}</span>
			<span class="date-range-chip__value">{summary}</span>
			{#if !active}
				<span class="date-range-chip__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
			{/if}
		</Popover.Trigger>
		<Popover.Portal>
			<Popover.Content
				class="date-range-chip__panel"
				data-elevation="elevated"
				align="end"
				sideOffset={6}
				collisionPadding={8}
			>
				<p class="date-range-chip__panel-title">{label}</p>
				<div class="date-range-chip__fields">
					<CalendarPicker
						id={`${id}-from`}
						label={`${label} from`}
						value={calendarDateFromString(from)}
						maxValue={calendarDateFromString(to)}
						onchange={(value) => onchange({ from: calendarDateToString(value), to })}
					/>
					<CalendarPicker
						id={`${id}-to`}
						label={`${label} to`}
						value={calendarDateFromString(to)}
						minValue={calendarDateFromString(from)}
						onchange={(value) => onchange({ from, to: calendarDateToString(value) })}
					/>
				</div>
				<div class="date-range-chip__panel-foot">
					<button type="button" class="date-range-chip__reset" disabled={!active} onclick={clear}>
						Clear dates
					</button>
					<Popover.Close class="date-range-chip__done">Done</Popover.Close>
				</div>
			</Popover.Content>
		</Popover.Portal>
	</Popover.Root>
	{#if active}
		<button
			type="button"
			class="date-range-chip__clear"
			aria-label={`Clear ${label}`}
			title={`Clear ${label}`}
			onclick={clear}
		>
			<span aria-hidden="true">{@html closeIcon}</span>
		</button>
	{/if}
</span>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.date-range-chip {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		max-width: 100%;
		min-height: 38px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		transition:
			border-color var(--timing-quick),
			background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}
		&--on {
			border-color: var(--color-interactive);
			background: var(--color-surface);
		}

		:global(.date-range-chip__trigger) {
			display: inline-flex;
			min-height: 36px;
			align-items: center;
			gap: 6px;
			padding: 0 var(--space-slim);
			border: none;
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: transparent;
			font: inherit;
			font-size: 13px;
			font-weight: 500;
			white-space: nowrap;
			cursor: pointer;
		}
		:global(.date-range-chip__trigger:focus-visible) {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.date-range-chip--on .date-range-chip__icon {
		color: var(--color-interactive);
	}
	.date-range-chip--on :global(.date-range-chip__trigger) {
		padding-right: var(--space-smaller);
	}
	.date-range-chip__icon,
	.date-range-chip__chevron {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-icon--secondary);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
	.date-range-chip__value {
		color: var(--color-heading);
		font-weight: 600;
	}
	.date-range-chip__clear {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		width: 28px;
		height: 36px;
		padding: 0;
		border: none;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
		&:hover {
			color: var(--color-heading);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	:global(.date-range-chip__panel) {
		z-index: var(--elevation-modal);
		box-sizing: border-box;
		width: min(320px, calc(100vw - var(--space-large)));
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		color: var(--color-text);
	}
	:global(.date-range-chip__panel:focus-visible) {
		outline: none;
	}
	:global(.date-range-chip__panel-title) {
		margin-bottom: var(--space-slim);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
	}
	:global(.date-range-chip__fields) {
		display: grid;
		gap: var(--space-base);
	}
	:global(.date-range-chip__panel-foot) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		margin-top: var(--space-base);
	}
	:global(.date-range-chip__reset),
	:global(.date-range-chip__done) {
		min-height: 32px;
		padding: 0 var(--space-slim);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: var(--color-surface);
		font: inherit;
		font-size: 13px;
		font-weight: 600;
		cursor: pointer;
	}
	:global(.date-range-chip__done) {
		border-color: var(--color-interactive);
		color: var(--color-surface);
		background: var(--color-interactive);
	}
	:global(.date-range-chip__reset:hover:not(:disabled)) {
		background: var(--color-surface--hover);
	}
	:global(.date-range-chip__done:hover) {
		background: var(--color-interactive--hover);
	}
	:global(.date-range-chip__reset:disabled) {
		color: var(--color-disabled);
		border-color: var(--color-disabled--secondary);
		background: var(--color-disabled--secondary);
		cursor: not-allowed;
	}
	:global(.date-range-chip__reset:focus-visible),
	:global(.date-range-chip__done:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
</style>
