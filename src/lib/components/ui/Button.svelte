<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		children,
		variant = 'primary',
		variation = 'work',
		size = 'base',
		type = 'button',
		disabled = false,
		loading = false,
		fullWidth = false,
		href,
		class: className = '',
		onclick
	}: {
		children: Snippet;
		variant?: 'primary' | 'secondary' | 'tertiary';
		variation?: 'work' | 'learning' | 'subtle' | 'destructive';
		size?: 'small' | 'base' | 'large';
		type?: 'button' | 'submit' | 'reset';
		disabled?: boolean;
		loading?: boolean;
		fullWidth?: boolean;
		/** Renders a link instead of a button. Use it for anything that goes to another page, so the
		 *  browser can open it in a new tab and SvelteKit can preload the page on hover. */
		href?: string;
		class?: string;
		onclick?: (event: MouseEvent) => void;
	} = $props();

	const classes = $derived(
		`button button--${variant} button--${variation} button--${size} ${className}`
	);
	const inactive = $derived(disabled || loading);
</script>

{#if href}
	<!-- The caller resolves the path; this component only renders whatever it is handed. -->
	<!-- eslint-disable svelte/no-navigation-without-resolve -->
	<a
		href={inactive ? undefined : href}
		class={classes}
		class:button--full-width={fullWidth}
		class:button--inactive={inactive}
		aria-disabled={inactive ? 'true' : undefined}
		aria-busy={loading}
		{onclick}
	>
		{#if loading}<span class="button__spinner" aria-hidden="true"></span>{/if}
		{@render children()}
	</a>
	<!-- eslint-enable svelte/no-navigation-without-resolve -->
{:else}
	<button
		{type}
		class={classes}
		class:button--full-width={fullWidth}
		disabled={inactive}
		aria-busy={loading}
		{onclick}
	>
		{#if loading}<span class="button__spinner" aria-hidden="true"></span>{/if}
		{@render children()}
	</button>
{/if}

<style lang="scss">
	.button {
		--button--color-variation: var(--color-interactive);
		--button--color-variation--hover: var(--color-interactive--hover);
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-smaller);
		min-height: 40px;
		padding: 0 var(--space-base);
		border: var(--border-base) solid var(--button--color-variation);
		border-radius: var(--radius-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
		text-decoration: none;
		transition: all var(--timing-base) ease-out;

		&--learning {
			--button--color-variation: var(--color-interactive--subtle);
			--button--color-variation--hover: var(--color-interactive--subtle--hover);
		}
		&--subtle {
			--button--color-variation: var(--color-interactive--subtle);
			--button--color-variation--hover: var(--color-interactive--subtle--hover);
		}
		&--destructive {
			--button--color-variation: var(--color-destructive);
			--button--color-variation--hover: var(--color-destructive--hover);
		}
		&--small {
			min-height: 32px;
			padding: 0 var(--space-slim);
			font-size: var(--typography--fontSize-base);
		}
		&--large {
			min-height: 48px;
			padding: 0 20px;
			font-size: var(--typography--fontSize-large);
		}
		&--full-width {
			width: 100%;
		}
		&--primary {
			color: var(--color-surface);
			background: var(--button--color-variation);
		}
		&--secondary {
			color: var(--button--color-variation);
			background: var(--color-surface);
		}
		&--tertiary {
			color: var(--button--color-variation);
			border-style: dashed;
			background: var(--color-surface);
		}

		&:hover:not(:disabled),
		&:focus-visible:not(:disabled) {
			color: var(--button--color-variation--hover);
			background: var(--color-surface--hover);
		}
		&--primary:hover:not(:disabled),
		&--primary:focus-visible:not(:disabled) {
			color: var(--color-surface);
			background: var(--button--color-variation--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&:disabled,
		&--inactive {
			pointer-events: none;
			color: var(--color-disabled);
			border-color: var(--color-disabled--secondary);
			background: var(--color-disabled--secondary);
			user-select: none;
		}
		&[aria-busy='true'] {
			cursor: not-allowed;
		}
		&__spinner {
			width: 1em;
			height: 1em;
			border: 2px solid currentColor;
			border-right-color: transparent;
			border-radius: var(--radius-circle);
			animation: spinning var(--timing-loading) linear infinite;
		}
	}
</style>
