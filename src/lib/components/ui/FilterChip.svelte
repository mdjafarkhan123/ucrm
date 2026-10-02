<script lang="ts">
	import Select from '$lib/components/ui/Select.svelte';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	type ChipOption = {
		value: string;
		label: string;
		disabled?: boolean;
	};

	// One filter in a toolbar, drawn the way Stripe and Linear draw theirs: a chip only as wide as its own
	// words. Resting, it shows just its name. Once a value is picked it shows the name and that value,
	// highlighted, with a cross that puts it back to rest. A chip with no resting value (a sort order, say)
	// always shows its value and never highlights.
	let {
		id,
		label,
		value,
		options,
		restValue,
		onchange
	}: {
		id: string;
		label: string;
		value: string;
		options: ChipOption[];
		/** The value that means "not filtering". Leave out for a control that always has an answer. */
		restValue?: string;
		onchange: (value: string) => void;
	} = $props();

	const filtering = $derived(restValue !== undefined && value !== restValue);
	const resting = $derived(restValue !== undefined && value === restValue);
	const selectedLabel = $derived(options.find((option) => option.value === value)?.label ?? '');
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span class={['filter-chip', filtering && 'filter-chip--on', resting && 'filter-chip--resting']}>
	<Select
		{id}
		class="filter-chip__select"
		{value}
		{options}
		prefix={label}
		ariaLabel={resting ? label : `${label}: ${selectedLabel}`}
		fitOptions
		{onchange}
	/>
	{#if filtering && restValue !== undefined}
		<button
			type="button"
			class="filter-chip__clear"
			aria-label={`Clear ${label}`}
			title={`Clear ${label}`}
			onclick={() => onchange(restValue)}
		>
			<span aria-hidden="true">{@html closeIcon}</span>
		</button>
	{/if}
</span>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.filter-chip {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		max-width: 100%;
		min-height: 44px;
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
	.filter-chip--on {
		border-color: var(--color-interactive);
		background: var(--color-surface--active);
	}

	// The select gives up its own box and width, so the chip is the only shape drawn and hugs its words.
	.filter-chip :global(.filter-chip__select) {
		width: auto;
		min-width: 0;
	}
	.filter-chip :global(.filter-chip__select .select__trigger) {
		width: auto;
		min-height: 42px;
		padding: 0 var(--space-slim);
		gap: var(--space-small);
		border: none;
		border-radius: var(--radius-base);
		background: transparent;
		font-size: var(--typography--fontSize-base);
	}
	.filter-chip :global(.filter-chip__select .select__value) {
		max-width: 180px;
		font-weight: 600;
	}

	// Resting: the name alone says what the chip is for, in the same weight as the buttons beside it.
	.filter-chip--resting :global(.filter-chip__select .select__value) {
		display: none;
	}
	.filter-chip--resting :global(.filter-chip__select .select__prefix) {
		color: var(--color-heading);
	}

	// Filtering: the cross takes the chevron's place, so the chip does not grow a second icon.
	.filter-chip--on :global(.filter-chip__select .select__trigger) {
		padding-right: var(--space-smaller);
	}
	.filter-chip--on :global(.filter-chip__select .select__chevron) {
		display: none;
	}

	.filter-chip__clear {
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
</style>
