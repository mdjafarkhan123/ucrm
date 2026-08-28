<script lang="ts">
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	let {
		value = $bindable(''),
		id,
		label,
		placeholder = 'Search',
		ariaLabel = 'Search',
		disabled = false,
		class: className = '',
		onkeydown
	}: {
		value?: string;
		id: string;
		label?: string;
		placeholder?: string;
		ariaLabel?: string;
		disabled?: boolean;
		class?: string;
		onkeydown?: (event: KeyboardEvent) => void;
	} = $props();

	function clear() {
		value = '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class={`search-input ${className}`}
	class:search-input--disabled={disabled}
	class:search-input--labelled={Boolean(label)}
>
	{#if label}
		<label class="search-input__label" for={id}>{label}</label>
	{/if}
	<span class="search-input__icon" aria-hidden="true">{@html searchIcon}</span>
	<input
		{id}
		type="search"
		bind:value
		{placeholder}
		{disabled}
		{onkeydown}
		aria-label={label ? undefined : ariaLabel}
		autocomplete="off"
	/>
	{#if value}
		<button class="search-input__clear" type="button" aria-label="Clear search" onclick={clear}>
			<span aria-hidden="true">{@html xIcon}</span>
		</button>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.search-input {
		position: relative;
		display: flex;
		width: 100%;
		min-height: 40px;
		align-items: center;
		gap: var(--space-small);
		padding: 0 var(--space-small);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		transition:
			box-shadow var(--timing-quick),
			border-color var(--timing-quick);

		&.search-input--labelled {
			margin-top: var(--space-small);
		}

		.search-input__label {
			position: absolute;
			z-index: var(--elevation-base);
			top: calc(var(--space-small) * -1);
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

		&:focus-within {
			border-color: var(--color-interactive);
			box-shadow: var(--shadow-focus);
		}

		&__icon,
		&__clear {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
		}

		&__icon :global(svg) {
			width: 18px;
			height: 18px;
		}

		input {
			width: 100%;
			min-width: 0;
			padding: 0;
			border: 0;
			outline: 0;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			line-height: 20px;

			&::placeholder {
				color: var(--color-text--secondary);
				opacity: 1;
			}

			/* Chrome renders its own native clear icon for type="search" on top of the custom
			   .search-input__clear button below; suppress it so there's only one. */
			&::-webkit-search-cancel-button {
				display: none;
			}
		}

		input:focus-visible {
			outline: none;
			box-shadow: none;
		}

		&__clear {
			width: 28px;
			height: 28px;
			padding: 0;
			border: 0;
			border-radius: var(--radius-small);
			color: var(--color-text--secondary);
			background: transparent;
			cursor: pointer;

			&:hover {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			span,
			span :global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&--disabled {
			border-color: var(--color-border);
			background: var(--color-disabled--secondary);
			cursor: not-allowed;

			input {
				color: var(--color-disabled);
				-webkit-text-fill-color: var(--color-disabled);
			}
		}
	}
</style>
