<script lang="ts">
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';

	// The small square edit affordance that sits beside a heading or at the end of a row. It carries no
	// label, so `label` is required and becomes both the accessible name and the hover title. Pass `href`
	// to go to an edit page, or `onclick` to open an editor in place.
	let {
		label,
		href,
		onclick,
		onhover,
		size = 'small',
		variation = 'subtle',
		variant = 'tertiary',
		disabled = false,
		class: className = ''
	}: {
		/** What this pencil edits, e.g. "Edit Riverbend Diner". Read out loud by a screen reader. */
		label: string;
		href?: string;
		onclick?: (event: MouseEvent) => void;
		/** Fires when the pointer or keyboard reaches the button, before it is pressed. Use it to start
		 *  loading whatever pressing it will reveal, so the editor is already there on the click. */
		onhover?: () => void;
		size?: 'small' | 'base';
		/** `subtle` for a calm in-context pencil; `work` when editing is the main action on the block. */
		variation?: 'subtle' | 'work';
		/** `tertiary` has no border; `secondary` keeps one, for a pencil on a busy surface. */
		variant?: 'tertiary' | 'secondary';
		disabled?: boolean;
		class?: string;
	} = $props();

	const classes = $derived(
		`pencil-button pencil-button--${size} pencil-button--${variation} pencil-button--${variant} ${className}`
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet glyph()}
	<span class="pencil-button__icon" aria-hidden="true">{@html pencilIcon}</span>
{/snippet}

{#if href && !disabled}
	<!-- The caller resolves the path; this component renders whatever it is handed. -->
	<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
	<a
		{href}
		class={classes}
		aria-label={label}
		title={label}
		{onclick}
		onmouseenter={onhover}
		onfocus={onhover}>{@render glyph()}</a
	>
{:else}
	<button
		type="button"
		class={classes}
		aria-label={label}
		title={label}
		{disabled}
		{onclick}
		onmouseenter={onhover}
		onfocus={onhover}
	>
		{@render glyph()}
	</button>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.pencil-button {
		--pencil-button--color: var(--color-interactive--subtle);
		--pencil-button--color--hover: var(--color-interactive--subtle--hover);
		display: inline-flex;
		box-sizing: border-box;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		padding: 0;
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		color: var(--pencil-button--color);
		background: transparent;
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		// Square, per the icon-only rule in the design skill: width equals the size height.
		&--small {
			width: var(--space-larger);
			height: var(--space-larger);
		}
		&--base {
			width: 40px;
			height: 40px;
		}

		&--work {
			--pencil-button--color: var(--color-interactive);
			--pencil-button--color--hover: var(--color-interactive--hover);
		}

		&--secondary {
			border-color: var(--color-border--interactive);
			background: var(--color-surface);
		}

		// Icon size follows the button size, the way the design skill pairs them: small with the small
		// icon, base with the base icon.
		&__icon :global(svg) {
			display: block;
			width: 20px;
			height: 20px;
		}
		&--base &__icon :global(svg) {
			width: 24px;
			height: 24px;
		}

		&:hover:not(:disabled),
		&:focus-visible:not(:disabled) {
			color: var(--pencil-button--color--hover);
			background: var(--color-surface--hover);
		}
		&--secondary:hover:not(:disabled),
		&--secondary:focus-visible:not(:disabled) {
			border-color: var(--pencil-button--color--hover);
		}

		&:active:not(:disabled) {
			background: var(--color-surface--active);
		}

		&:focus-visible {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			border-color: var(--color-disabled--secondary);
			color: var(--color-disabled);
			background: var(--color-disabled--secondary);
			cursor: not-allowed;
			pointer-events: none;
			user-select: none;
		}
	}
</style>
