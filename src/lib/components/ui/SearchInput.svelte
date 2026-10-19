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
		size = 'base',
		class: className = '',
		onkeydown
	}: {
		value?: string;
		id: string;
		label?: string;
		placeholder?: string;
		ariaLabel?: string;
		disabled?: boolean;
		/** `compact` is the 38px search that sits inside a table card's header. */
		size?: 'base' | 'compact';
		class?: string;
		onkeydown?: (event: KeyboardEvent) => void;
	} = $props();

	let inputElement: HTMLInputElement;

	function clear() {
		value = '';
		inputElement.focus();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class={`search-input ${className}`}
	class:search-input--disabled={disabled}
	class:search-input--labelled={Boolean(label)}
	class:search-input--compact={size === 'compact'}
>
	{#if label}
		<label class="search-input__label" for={id}>{label}</label>
	{/if}
	<span class="search-input__icon" aria-hidden="true">{@html searchIcon}</span>
	<input
		bind:this={inputElement}
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
		<button
			class="search-input__clear"
			type="button"
			{disabled}
			aria-label="Clear search"
			onclick={clear}
		>
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
		padding: 0 var(--space-slim);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		background: var(--color-surface);
		transition:
			box-shadow var(--timing-quick),
			border-color var(--timing-quick);

		&.search-input--compact {
			min-height: 38px;
			padding: 0 var(--space-slim);
			border-color: var(--color-border);
			font-size: 13px;
			font-weight: 500;

			.search-input__icon :global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&.search-input--labelled {
			margin-top: 25px;
		}

		.search-input__label {
			position: absolute;
			z-index: var(--elevation-base);
			top: -25px;
			left: 0;
			max-width: calc(100% - var(--space-large));
			padding: 0;
			overflow: hidden;
			color: var(--color-heading);
			background: transparent;
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
			line-height: var(--space-base);
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&:hover:not(.search-input--disabled) {
			border-color: var(--color-border--interactive--hover);
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
			width: 16px;
			height: 16px;
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
			width: 24px;
			height: 24px;
			padding: 0;
			border: 1px solid transparent;
			border-radius: var(--radius-tile-small);
			color: var(--color-text--secondary);
			background: var(--color-surface--hover);
			cursor: pointer;

			&:hover {
				color: var(--color-heading);
				background: var(--color-surface--active);
			}

			&:active:not(:disabled) {
				border-color: var(--color-border--interactive--hover);
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			span,
			span :global(svg) {
				display: block;
				width: 14px;
				height: 14px;
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
