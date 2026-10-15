<script lang="ts">
	import type { Snippet } from 'svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	let {
		children,
		variant = 'primary',
		variation = 'work',
		size = 'base',
		type = 'button',
		disabled = false,
		loading = false,
		showCheckIcon = false,
		fullWidth = false,
		href,
		target,
		class: className = '',
		onclick,
		onhover
	}: {
		children: Snippet;
		variant?: 'primary' | 'secondary' | 'tertiary';
		variation?: 'work' | 'learning' | 'subtle' | 'destructive';
		size?: 'small' | 'base' | 'large';
		type?: 'button' | 'submit' | 'reset';
		disabled?: boolean;
		loading?: boolean;
		/** Shows the Tabler check mark used by a confirmed save action. */
		showCheckIcon?: boolean;
		fullWidth?: boolean;
		/** Renders a link instead of a button. Use it for anything that goes to another page, so the
		 *  browser can open it in a new tab and SvelteKit can preload the page on hover. */
		href?: string;
		/** Only meaningful with `href`. Use `'_blank'` for a link that leaves the app entirely (another
		 *  site, another app's deep link) so the page the customer was on stays open behind it. */
		target?: string;
		class?: string;
		onclick?: (event: MouseEvent) => void;
		/** Fires when the pointer or keyboard reaches the button, before it is pressed. Use it to start
		 *  loading whatever pressing it will reveal, so the panel is already there on the click. */
		onhover?: () => void;
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
		{target}
		rel={target === '_blank' ? 'noopener noreferrer' : undefined}
		class={classes}
		class:button--full-width={fullWidth}
		class:button--inactive={inactive}
		class:button--check-icon={showCheckIcon}
		aria-disabled={inactive ? 'true' : undefined}
		aria-busy={loading}
		{onclick}
		onmouseenter={onhover}
		onfocus={onhover}
	>
		{#if loading}<span class="button__spinner" aria-hidden="true"></span>{/if}
		{#if showCheckIcon && !loading}
			<span class="button__icon" aria-hidden="true">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html checkIcon}
			</span>
		{/if}
		{@render children()}
	</a>
	<!-- eslint-enable svelte/no-navigation-without-resolve -->
{:else}
	<button
		{type}
		class={classes}
		class:button--full-width={fullWidth}
		class:button--check-icon={showCheckIcon}
		disabled={inactive}
		aria-busy={loading}
		{onclick}
		onmouseenter={onhover}
		onfocus={onhover}
	>
		{#if loading}<span class="button__spinner" aria-hidden="true"></span>{/if}
		{#if showCheckIcon && !loading}
			<span class="button__icon" aria-hidden="true">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html checkIcon}
			</span>
		{/if}
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
		&__icon {
			display: none;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 16px;
			height: 16px;
		}
		&__icon :global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--check-icon .button__icon {
		display: inline-flex;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button {
		border-color: var(--classic2-border-control);
		border-radius: 12px;
		font-family: var(--classic2-font);
		font-size: var(--classic2-font-body);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--primary {
		border-color: var(--classic2-solid-green);
		color: var(--classic2-green-on);
		background: var(--classic2-solid-green);
		box-shadow: 0 6px 16px var(--classic2-shadow-green);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--primary:hover:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--primary:focus-visible:not(:disabled) {
		border-color: var(--classic2-green-hover);
		color: var(--classic2-green-on);
		background: var(--classic2-green-hover);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--secondary,
	:global(:root:has(.app-shell[data-presentation='classic'])) .button--tertiary {
		color: var(--classic2-body);
		background: var(--classic2-surface-soft);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--secondary:hover:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--secondary:focus-visible:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--tertiary:hover:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--tertiary:focus-visible:not(:disabled) {
		border-color: var(--classic2-green);
		color: var(--classic2-green);
		background: var(--classic2-surface-soft);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--tertiary {
		border-color: transparent;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--small {
		min-height: 30px;
		padding: 0 12px;
		border-radius: 9px;
		font-size: var(--classic2-font-small);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--base {
		min-height: 40px;
		padding: 0 16px;
		border-radius: 12px;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--large {
		min-height: 44px;
		padding: 0 18px;
		border-radius: 14px;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button--destructive.button--primary {
		border-color: var(--classic2-solid-rose);
		background: var(--classic2-solid-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--primary:hover:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--primary:focus-visible:not(:disabled) {
		border-color: var(--classic2-solid-rose);
		background: var(--classic2-solid-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--secondary,
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--tertiary {
		color: var(--classic2-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--secondary:hover:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--secondary:focus-visible:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--tertiary:hover:not(:disabled),
	:global(:root:has(.app-shell[data-presentation='classic']))
		.button--destructive.button--tertiary:focus-visible:not(:disabled) {
		color: var(--classic2-rose);
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button:focus-visible {
		outline: 3px solid var(--classic2-green-soft);
		outline-offset: 2px;
		box-shadow: none;
	}

	:global(:root:has(.app-shell[data-presentation='classic'])) .button:disabled,
	:global(:root:has(.app-shell[data-presentation='classic'])) .button--inactive {
		opacity: 0.45;
		box-shadow: none;
	}
</style>
