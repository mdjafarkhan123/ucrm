<script lang="ts">
	import type { Snippet } from 'svelte';

	// Jafar business management E1/E2: a public booking page's settled state -- booked, requested, moved, cancelled,
	// or a link that no longer works -- as one centred icon, a heading and what happens next.

	type Props = {
		icon: string;
		tone?: 'success' | 'waiting' | 'neutral';
		title: string;
		children: Snippet;
	};

	let { icon, tone = 'neutral', title, children }: Props = $props();
</script>

<div class="booking-status">
	<span class="booking-status__icon booking-status__icon--{tone}" aria-hidden="true"
		>{@html icon}</span
	>
	<h1 class="booking-status__title">{title}</h1>
	{@render children()}
</div>

<style lang="scss">
	.booking-status {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-largest) var(--space-large);
		text-align: center;

		:global(> p) {
			margin: 0;
			color: var(--color-text--secondary);
			line-height: var(--typography--lineHeight-base);
			overflow-wrap: anywhere;
		}

		@media (max-width: 640px) {
			padding: var(--space-larger) var(--space-base);
		}
	}

	.booking-status__title {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
	}

	.booking-status__icon {
		display: inline-grid;
		place-items: center;
		width: 4rem;
		height: 4rem;
		border-radius: var(--radius-circle);

		:global(svg) {
			width: 2rem;
			height: 2rem;
		}
	}

	.booking-status__icon--neutral {
		background: var(--color-surface--background);
		color: var(--color-text--secondary);
	}

	.booking-status__icon--success {
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
	}

	.booking-status__icon--waiting {
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
	}
</style>
