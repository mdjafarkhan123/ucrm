<script lang="ts">
	import type { Snippet } from 'svelte';
	import CardHeader from '$lib/components/ui/CardHeader.svelte';

	// The card every setup step sits in, the imports and New campaign (design skill `layout.md` → Setup steps):
	// the shared Card header with a tile in the flow's colour, the step's body, then the pop-up footer bar with
	// Back at the left and the main button at the right.
	let {
		title,
		hint,
		icon,
		tone,
		flush = false,
		children,
		footer
	}: {
		title: string;
		hint?: string | null;
		/** A Tabler icon (raw SVG) for the header tile. */
		icon: string;
		/** The flow's colour family (client import `client`, Price book `inactive`, balances `invoice`, campaigns `growth`). */
		tone: string;
		/** A body whose rows run edge to edge, such as the column-matching list. */
		flush?: boolean;
		children: Snippet;
		footer: Snippet;
	} = $props();
</script>

<section class="setup-step-card">
	<CardHeader {title} {hint} {icon} {tone} />
	<div class={['setup-step-card__body', flush && 'setup-step-card__body--flush']}>
		{@render children()}
	</div>
	<footer class="setup-step-card__footer">{@render footer()}</footer>
</section>

<style lang="scss">
	.setup-step-card {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-medium);

			&--flush {
				gap: 0;
				padding: 0;
			}
		}

		&__footer {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-base) var(--space-medium);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}

	// A step's hint can be a full sentence (opening balances), so it wraps instead of trailing off.
	.setup-step-card :global(.card-header__hint) {
		white-space: normal;
	}

	// Whatever comes last in the footer (the main button) sits at the right; a hint fills the space before it.
	.setup-step-card__footer > :global(:last-child) {
		margin-left: auto;
	}
</style>
