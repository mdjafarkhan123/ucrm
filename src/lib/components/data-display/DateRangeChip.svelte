<script lang="ts">
	import { Popover } from 'bits-ui';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
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
			<IconTile icon={calendarIcon} tone="time" size={24} />
			<span class="date-range-chip__label">{label}</span>
			<span class="date-range-chip__divider" aria-hidden="true"></span>
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
				<div class="date-range-chip__panel-head">
					<IconTile icon={calendarIcon} tone="time" size={32} />
					<p class="date-range-chip__panel-title">{label}</p>
				</div>
				<div class="date-range-chip__fields">
					<CalendarPicker
						id={`${id}-from`}
						label={`${label} from`}
						value={calendarDateFromString(from)}
						maxValue={calendarDateFromString(to)}
						onchange={(value) => onchange({ from: calendarDateToString(value), to })}
					/>
					<span class="date-range-chip__arrow" aria-hidden="true">{@html arrowRightIcon}</span>
					<CalendarPicker
						id={`${id}-to`}
						label={`${label} to`}
						value={calendarDateFromString(to)}
						minValue={calendarDateFromString(from)}
						onchange={(value) => onchange({ from, to: calendarDateToString(value) })}
					/>
				</div>
				<div class="date-range-chip__panel-foot">
					<Button variant="quiet" size="small" disabled={!active} onclick={clear}>
						{@html closeIcon}Clear dates
					</Button>
					<Popover.Close>
						{#snippet child({ props })}
							<Button {...props} size="small">Done</Button>
						{/snippet}
					</Popover.Close>
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
	// Date range chip (`chips.md`, board `e18rX` B): the filter chip with the 24 date tile, so dates read as
	// dates across the toolbar.
	.date-range-chip {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		max-width: 100%;
		height: 36px;
		box-sizing: border-box;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-button);
		transition:
			border-color var(--timing-quick),
			background-color var(--timing-quick);

		&:hover {
			border-color: var(--color-border--interactive--hover);
			background: var(--color-surface--hover);
		}
		&--on,
		&--on:hover {
			border: 1.5px solid var(--color-interactive);
			background: var(--color-surface);
		}

		:global(.date-range-chip__trigger) {
			display: inline-flex;
			height: 34px;
			align-items: center;
			gap: 6px;
			padding: 0 10px 0 6px;
			border: none;
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			white-space: nowrap;
			cursor: pointer;
		}
		:global(.date-range-chip__trigger:focus-visible) {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.date-range-chip--on :global(.date-range-chip__trigger) {
		padding-right: 6px;
	}
	.date-range-chip__divider {
		width: 1px;
		height: 16px;
		background: var(--color-border--interactive);
	}
	.date-range-chip__chevron {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-icon);

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
		width: 24px;
		height: 24px;
		margin-right: 6px;
		padding: 0;
		border: none;
		border-radius: var(--radius-tile-small);
		color: var(--color-icon);
		background: var(--color-surface--hover);
		cursor: pointer;

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}
		&:hover {
			color: var(--color-heading);
			background: var(--color-surface--active);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	:global(.date-range-chip__panel) {
		z-index: var(--elevation-modal);
		box-sizing: border-box;
		width: min(440px, calc(100vw - var(--space-large)));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		color: var(--color-text);
	}
	:global(.date-range-chip__panel:focus-visible) {
		outline: none;
	}
	:global(.date-range-chip__panel-head) {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 14px var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	:global(.date-range-chip__panel-title) {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 600;
	}
	:global(.date-range-chip__fields) {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
		align-items: end;
		gap: var(--space-small);
		padding: var(--space-base);
	}
	:global(.date-range-chip__arrow) {
		display: inline-flex;
		height: 40px;
		align-items: center;
		color: var(--color-icon--secondary);
	}
	:global(.date-range-chip__arrow svg) {
		width: 16px;
		height: 16px;
	}
	:global(.date-range-chip__panel-foot) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: 10px var(--space-slim) 10px var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}
</style>
