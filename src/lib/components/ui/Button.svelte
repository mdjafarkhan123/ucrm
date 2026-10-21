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
		iconOnly = false,
		pressed,
		white = false,
		count,
		label,
		href,
		target,
		class: className = '',
		onclick,
		onhover,
		...rest
	}: {
		children: Snippet;
		/** `primary` is the green main button (red when `destructive`). `secondary` and `tertiary` are the grey
		 *  bordered button (red text when `destructive`). `quiet` is for link-like actions such as Clear filters. */
		variant?: 'primary' | 'secondary' | 'tertiary' | 'quiet';
		variation?: 'work' | 'learning' | 'subtle' | 'destructive';
		size?: 'small' | 'base' | 'large';
		type?: 'button' | 'submit' | 'reset';
		disabled?: boolean;
		loading?: boolean;
		fullWidth?: boolean;
		/** A square button that holds only an icon, as wide as its size is tall. Needs `label`. */
		iconOnly?: boolean;
		/** A switch-like button that stays on while what it opens is showing (Map, Unscheduled, Filters). Only
		 *  for the white bordered kinds. Sets `aria-pressed`, except on a menu or popover trigger, whose own
		 *  `aria-expanded` already tells a screen reader it is open. */
		pressed?: boolean;
		/** The grey kinds turn white: on a coloured top (record header, create-form header), where grey would
		 *  muddy the tint, and in a joined group (‹ Today ›), which is one white box. */
		white?: boolean;
		/** A number bubble after the label, e.g. how many filters are set. Hidden when null. */
		count?: number | null;
		/** The accessible name and hover title. Required for an icon-only button, which has no text. */
		label?: string;
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
		/** Anything else lands on the element, so a menu or tooltip trigger can hand its props through. */
		[key: string]: unknown;
	} = $props();

	const classes = $derived(
		`button button--${variant} button--${variation} button--${size} ${iconOnly ? 'button--icon-only' : ''} ${pressed ? 'button--pressed' : ''} ${white ? 'button--white' : ''} ${className}`
	);
	const ariaPressed = $derived(
		pressed === undefined || 'aria-expanded' in rest ? undefined : pressed
	);
	const inactive = $derived(disabled || loading);
</script>

{#if href}
	<!-- The caller resolves the path; this component only renders whatever it is handed. -->
	<!-- eslint-disable svelte/no-navigation-without-resolve -->
	<a
		{...rest}
		href={inactive ? undefined : href}
		{target}
		rel={target === '_blank' ? 'noopener noreferrer' : undefined}
		class={classes}
		class:button--full-width={fullWidth}
		class:button--inactive={inactive}
		aria-disabled={inactive ? 'true' : undefined}
		aria-busy={loading}
		aria-label={label}
		title={label}
		{onclick}
		onmouseenter={onhover}
		onfocus={onhover}
	>
		{#if loading}<span class="button__spinner" aria-hidden="true"></span>{/if}
		{@render children()}
		{#if count != null}<span class="button__count">{count}</span>{/if}
	</a>
	<!-- eslint-enable svelte/no-navigation-without-resolve -->
{:else}
	<button
		{...rest}
		{type}
		class={classes}
		class:button--full-width={fullWidth}
		disabled={inactive}
		aria-busy={loading}
		aria-pressed={ariaPressed}
		aria-label={label}
		title={label}
		{onclick}
		onmouseenter={onhover}
		onfocus={onhover}
	>
		{#if loading}<span class="button__spinner" aria-hidden="true"></span>{/if}
		{@render children()}
		{#if count != null}<span class="button__count">{count}</span>{/if}
	</button>
{/if}

<style lang="scss">
	// The concept's button set (`concept.pen` → Parts → Buttons; design skill `buttons.md`).
	.button {
		--button--color-variation: var(--color-interactive);
		--button--color-variation--hover: var(--color-interactive--hover);
		--button--icon-size: 16px;
		position: relative;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-small);
		min-height: 36px;
		padding: 0 14px;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
		text-decoration: none;
		transition: all var(--timing-base) ease-out;

		:global(svg) {
			flex: 0 0 auto;
			width: var(--button--icon-size);
			height: var(--button--icon-size);
		}

		&--destructive {
			--button--color-variation: var(--color-destructive);
			--button--color-variation--hover: var(--color-destructive--hover);
		}
		&--small {
			gap: 6px;
			min-height: 32px;
			padding: 0 12px;
			font-size: var(--typography--fontSize-label);
		}
		&--large {
			--button--icon-size: 18px;
			min-height: 44px;
			padding: 0 18px;
			font-size: var(--typography--fontSize-large);
		}
		&--full-width {
			width: 100%;
		}
		// Icon only: square at the size's height, no side padding.
		&--icon-only {
			width: 36px;
			padding: 0;
		}
		&--icon-only.button--secondary,
		&--icon-only.button--tertiary {
			color: var(--color-icon);
		}
		&--icon-only.button--small {
			width: 32px;
		}
		&--icon-only.button--large {
			width: 44px;
		}

		// Main: green (red for the final step of a delete), slightly raised.
		&--primary {
			color: var(--color-surface);
			background: var(--button--color-variation);
			box-shadow: var(--shadow-button--raised);

			&:hover {
				background: var(--button--color-variation--hover);
			}
			&:active {
				background: var(--button--color-variation--hover);
				box-shadow: inset 0 1px 3px rgb(0 0 0 / 25%);
			}
		}

		// The final button of a delete is raised in its own dark red.
		&--primary.button--destructive {
			box-shadow:
				0 1px 2px color-mix(in srgb, var(--color-destructive--hover) 30%, transparent),
				inset 0 1px 0 rgb(255 255 255 / 20%);

			&:active {
				box-shadow: inset 0 1px 3px rgb(0 0 0 / 25%);
			}
		}

		// Grey bordered: secondary, and danger when destructive. Stone grey so it never blends into a white card
		// or the page. White instead with `white`, or inside a `.tinted-surface` (app.scss).
		&--white {
			--button--grey-fill: var(--color-surface);
			--button--grey-fill--hover: var(--color-surface--hover);
			--button--grey-fill--active: var(--color-surface--active);
		}
		&--secondary,
		&--tertiary {
			color: var(--color-heading);
			border-color: var(--color-border--interactive);
			background: var(--button--grey-fill, var(--color-interactive--background));
			box-shadow: var(--shadow-button);

			&:hover {
				border-color: var(--color-border--interactive--hover);
				background: var(--button--grey-fill--hover, var(--color-surface--active));
			}
			&:active {
				border-color: var(--color-border--interactive--hover);
				background: var(--button--grey-fill--active, var(--color-interactive--background));
				box-shadow: none;
			}
		}
		&--secondary.button--destructive,
		&--tertiary.button--destructive {
			color: var(--color-destructive);

			&:hover,
			&:active {
				border-color: var(--color-destructive);
				background: var(--color-critical--surface);
			}
			&:active {
				box-shadow: none;
			}
		}

		// Switched on: brand-green border, label and icon on white, while its panel shows or its filter is set.
		&--pressed.button--secondary,
		&--pressed.button--tertiary {
			color: var(--color-interactive);
			border-color: var(--color-interactive);
			background: var(--color-surface);

			&:hover,
			&:active {
				color: var(--color-interactive--hover);
				border-color: var(--color-interactive--hover);
				background: var(--color-surface);
			}
			&:active {
				box-shadow: inset 0 1px 3px color-mix(in srgb, var(--color-heading) 12%, transparent);
			}
		}

		// The number bubble: grey while off, solid green while on.
		&__count {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			min-width: 20px;
			height: 20px;
			padding: 0 7px;
			border-radius: var(--radius-large);
			background: var(--color-inactive--surface);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			line-height: 1;
		}
		&--pressed &__count {
			background: var(--color-interactive);
			color: var(--color-surface);
		}
		&--pressed:hover &__count,
		&--pressed:active &__count {
			background: var(--color-interactive--hover);
		}
		&:disabled:not([aria-busy='true']) &__count {
			background: var(--color-surface);
			color: var(--color-disabled);
		}

		&--quiet {
			color: var(--color-text);
			background: transparent;

			&:hover {
				background: var(--color-surface--hover);
			}
			&:active {
				background: var(--color-surface--active);
			}
		}
		&--quiet.button--destructive {
			color: var(--color-destructive);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		// Loading keeps the button's own colour; only a real disabled button greys out.
		&:disabled:not([aria-busy='true']),
		&--inactive:not([aria-busy='true']) {
			pointer-events: none;
			color: var(--color-disabled);
			border-color: var(--color-disabled--secondary);
			background: var(--color-disabled--secondary);
			box-shadow: none;
			user-select: none;
		}
		&--quiet:disabled:not([aria-busy='true']),
		&--quiet.button--inactive:not([aria-busy='true']) {
			border-color: transparent;
			background: transparent;
		}
		&[aria-busy='true'] {
			pointer-events: none;
			cursor: not-allowed;
		}

		// The spinner takes the icon's place. With no icon, the label hides and the spinner sits in the
		// middle, so the button keeps its width.
		&__spinner {
			flex: 0 0 auto;
			width: var(--button--icon-size);
			height: var(--button--icon-size);
			border: 2px solid color-mix(in srgb, currentColor 25%, transparent);
			border-top-color: currentColor;
			border-radius: var(--radius-circle);
			animation: spinning var(--timing-loading) linear infinite;
		}
		&[aria-busy='true'] :global(svg) {
			display: none;
		}
		&[aria-busy='true']:not(:has(:global(svg))) {
			-webkit-text-fill-color: transparent;

			.button__spinner {
				position: absolute;
				inset: 0;
				margin: auto;
			}
		}
	}
</style>
