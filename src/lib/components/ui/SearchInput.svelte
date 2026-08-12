<script lang="ts">
	import searchIcon from '@tabler/icons/outline/search.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	let {
		value = $bindable(''),
		id,
		placeholder = 'Search',
		ariaLabel = 'Search',
		disabled = false,
		class: className = ''
	}: {
		value?: string;
		id: string;
		placeholder?: string;
		ariaLabel?: string;
		disabled?: boolean;
		class?: string;
	} = $props();

	function clear() {
		value = '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class={`search-input ${className}`} class:search-input--disabled={disabled}>
	<span class="search-input__icon" aria-hidden="true">{@html searchIcon}</span>
	<input
		{id}
		type="search"
		bind:value
		{placeholder}
		{disabled}
		aria-label={ariaLabel}
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
		transition: box-shadow var(--timing-quick), border-color var(--timing-quick);

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
