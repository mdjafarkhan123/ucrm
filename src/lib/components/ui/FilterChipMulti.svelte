<script lang="ts">
	import { Popover as PopoverPrimitive } from 'bits-ui';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	type ChipOption = {
		value: string;
		label: string;
		/** How many records the option would find, shown beside it. */
		count?: number;
	};

	// A filter chip that takes several answers, drawn like `FilterChip`: resting, it shows just its name; once
	// something is chosen it shows the name and the choice (the first one, then "+2"), highlighted, with a
	// cross that puts it back to rest. Opening it lists every option with a checkbox, the way Stripe and
	// Linear list a multi-value filter, and picking is instant: each tick reports the new list at once.
	// Anything in the same chip is an OR (a record matching any chosen option is found); separate chips narrow
	// each other, which is the page's concern, not this control's.
	let {
		id,
		label,
		options,
		values,
		icon,
		size = 'base',
		onchange
	}: {
		id: string;
		label: string;
		/** A Tabler icon (raw SVG) before the name, in the interactive colour. */
		icon?: string;
		options: ChipOption[];
		/** The chosen option values, in any order. */
		values: string[];
		/** `small` matches the 34px controls of a toolbar such as the calendar bar. */
		size?: 'base' | 'small';
		onchange: (values: string[]) => void;
	} = $props();

	let open = $state(false);

	const filtering = $derived(values.length > 0);
	const firstLabel = $derived(
		options.find((option) => option.value === values[0])?.label ?? values[0] ?? ''
	);
	const extra = $derived(values.length > 1 ? `+${values.length - 1}` : '');

	// Keeps the list in the options' own order, so the same choice is always the same address in the URL.
	function toggle(value: string, checked: boolean) {
		const next = checked ? [...values, value] : values.filter((candidate) => candidate !== value);
		onchange(options.map((option) => option.value).filter((candidate) => next.includes(candidate)));
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span
	class={[
		'filter-chip-multi',
		filtering && 'filter-chip-multi--on',
		size === 'small' && 'filter-chip-multi--small'
	]}
>
	<PopoverPrimitive.Root bind:open>
		<PopoverPrimitive.Trigger
			{id}
			class="filter-chip-multi__trigger"
			aria-label={filtering ? `${label}: ${values.length} chosen` : label}
		>
			{#if icon}<span class="filter-chip-multi__icon" aria-hidden="true">{@html icon}</span>{/if}
			<span class="filter-chip-multi__name">{label}</span>
			{#if filtering}
				<span class="filter-chip-multi__value">{firstLabel}</span>
				{#if extra}<span class="filter-chip-multi__extra">{extra}</span>{/if}
			{/if}
			{#if !filtering}
				<span class="filter-chip-multi__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
			{/if}
		</PopoverPrimitive.Trigger>

		<PopoverPrimitive.Portal>
			<PopoverPrimitive.Content
				class="filter-chip-multi__content"
				data-elevation="elevated"
				align="start"
				sideOffset={4}
				collisionPadding={8}
			>
				<div class="filter-chip-multi__head">
					<span class="filter-chip-multi__head-name">{label}</span>
					{#if filtering}<span class="filter-chip-multi__head-count">{values.length} chosen</span>{/if}
				</div>
				<ul class="filter-chip-multi__list" aria-label={label}>
					{#each options as option (option.value)}
						<li
							class="filter-chip-multi__row"
							class:filter-chip-multi__row--on={values.includes(option.value)}
						>
							<Checkbox
								id={`${id}-${option.value}`}
								label={option.label}
								checked={values.includes(option.value)}
								onchange={(checked) => toggle(option.value, checked)}
							/>
							{#if option.count !== undefined}
								<span class="filter-chip-multi__count">{option.count}</span>
							{/if}
						</li>
					{:else}
						<li class="filter-chip-multi__empty">Nothing to choose from yet.</li>
					{/each}
				</ul>
				{#if filtering}
					<footer class="filter-chip-multi__footer">
						<button type="button" class="filter-chip-multi__reset" onclick={() => onchange([])}>
							<span aria-hidden="true">{@html closeIcon}</span>Clear {label.toLowerCase()}
						</button>
					</footer>
				{/if}
			</PopoverPrimitive.Content>
		</PopoverPrimitive.Portal>
	</PopoverPrimitive.Root>

	{#if filtering}
		<button
			type="button"
			class="filter-chip-multi__clear"
			aria-label={`Clear ${label}`}
			title={`Clear ${label}`}
			onclick={() => onchange([])}
		>
			<span aria-hidden="true">{@html closeIcon}</span>
		</button>
	{/if}
</span>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.filter-chip-multi {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		max-width: 100%;
		min-height: 36px;
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		transition:
			border-color var(--timing-quick),
			background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}
	}
	.filter-chip-multi--on {
		border-color: var(--color-interactive);
		background: var(--color-surface);
	}

	.filter-chip-multi :global(.filter-chip-multi__trigger) {
		display: inline-flex;
		min-width: 0;
		min-height: 34px;
		align-items: center;
		gap: var(--space-small);
		padding: 0 var(--space-slim);
		border: none;
		border-radius: var(--radius-base);
		color: var(--color-heading);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		cursor: pointer;
		white-space: nowrap;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.filter-chip-multi--on :global(.filter-chip-multi__trigger) {
		padding-right: var(--space-smaller);
	}

	.filter-chip-multi--small {
		min-height: 34px;

		:global(.filter-chip-multi__trigger) {
			min-height: 32px;
			padding-inline: var(--space-small);
			font-size: var(--typography--fontSize-small);
		}

		.filter-chip-multi__clear {
			height: 32px;
		}
	}

	// Filtering: the name steps back and the choice leads, as it does in `FilterChip`.
	.filter-chip-multi__name {
		color: var(--color-text--secondary);
		font-weight: 500;
	}
	.filter-chip-multi:not(.filter-chip-multi--on) .filter-chip-multi__name {
		color: var(--color-heading);
		font-weight: 600;
	}
	.filter-chip-multi__value {
		max-width: 180px;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.filter-chip-multi__chevron {
		display: grid;
		width: 16px;
		height: 16px;
		place-items: center;
		color: var(--color-icon--secondary);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
	.filter-chip-multi
		:global(.filter-chip-multi__trigger[data-state='open'] .filter-chip-multi__chevron) {
		transform: rotate(180deg);
	}

	.filter-chip-multi__clear {
		display: inline-grid;
		flex: 0 0 auto;
		place-items: center;
		width: 32px;
		height: 42px;
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

	:global(.filter-chip-multi__content) {
		z-index: var(--elevation-modal);
		box-sizing: border-box;
		width: max-content;
		min-width: max(var(--bits-floating-anchor-width), calc(var(--space-extravagant) * 2.5));
		max-width: min(calc(var(--space-extravagant) * 5), var(--bits-floating-available-width));
		max-height: min(calc(var(--space-extravagant) * 3), var(--bits-floating-available-height));
		overflow-y: auto;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);

		&:focus-visible {
			outline: none;
		}
	}

	.filter-chip-multi__list {
		margin: 0;
		padding: var(--space-small);
		list-style: none;
	}
	.filter-chip-multi__row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small);
		border-radius: var(--radius-small);
		transition: background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}
		// The whole row is the target, not just the box and its words.
		:global(.checkbox) {
			flex: 1 1 auto;
			min-width: 0;
		}
	}
	.filter-chip-multi__count {
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-variant-numeric: tabular-nums;
	}
	.filter-chip-multi__empty {
		padding: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.filter-chip-multi__footer {
		padding: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}
	.filter-chip-multi__reset {
		padding: var(--space-small);
		border: none;
		border-radius: var(--radius-small);
		color: var(--color-interactive);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.filter-chip-multi {
		box-shadow: var(--shadow-button);
	}
	.filter-chip-multi--on .filter-chip-multi__name {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		&::after {
			content: '';
			width: 1px;
			height: 16px;
			background: var(--color-border--interactive);
		}
	}
	.filter-chip-multi .filter-chip-multi__clear {
		width: 24px;
		height: 24px;
		margin-right: 6px;
		border-radius: var(--radius-tile-small);
		background: var(--color-surface--hover);
		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	// Multi-choice filter chip (`chips.md`, board `e18rX` B).
	.filter-chip-multi--on {
		border-width: 1.5px;
	}
	.filter-chip-multi :global(.filter-chip-multi__trigger) {
		gap: 6px;
	}
	.filter-chip-multi__icon {
		display: inline-flex;
		color: var(--color-interactive);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.filter-chip-multi:not(.filter-chip-multi--on) .filter-chip-multi__name {
		color: var(--color-heading);
	}
	.filter-chip-multi--on .filter-chip-multi__name {
		color: var(--color-text);
	}
	.filter-chip-multi__value {
		color: var(--color-heading);
		font-weight: 600;
	}
	.filter-chip-multi__extra {
		color: var(--color-interactive);
		font-weight: 600;
	}
	:global(.filter-chip-multi__content) {
		width: 250px;
		min-width: 0;
		max-height: min(420px, var(--bits-floating-available-height));
		border-radius: var(--radius-large);
	}
	.filter-chip-multi__head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base) var(--space-smaller) 18px;
	}
	.filter-chip-multi__head-name {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		letter-spacing: 0.6px;
		text-transform: uppercase;
	}
	.filter-chip-multi__head-count {
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.filter-chip-multi__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		padding: var(--space-small);
	}
	.filter-chip-multi__row {
		min-height: 36px;
		box-sizing: border-box;
		gap: 10px;
		padding: 0 10px;
		border-radius: var(--radius-base);

		:global(.checkbox__content) {
			min-width: 0;
		}

		:global(.checkbox__label) {
			display: block;
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}
	.filter-chip-multi__row--on :global(.checkbox__label) {
		font-weight: 600;
	}
	.filter-chip-multi__count {
		display: inline-grid;
		min-width: 20px;
		height: 20px;
		box-sizing: border-box;
		place-items: center;
		padding: 0 6px;
		border-radius: var(--radius-circle);
		background: var(--color-surface--background);
		font-weight: 600;
	}
	.filter-chip-multi__footer {
		background: var(--color-surface--background--subtle);
	}
	.filter-chip-multi__reset {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--color-text);

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}
	}
</style>
