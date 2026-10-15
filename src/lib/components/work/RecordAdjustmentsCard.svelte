<script lang="ts">
	import type { Snippet } from 'svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';

	// The one rail card that holds a record's discount and tax, one `AdjustmentRow` each, so the two small
	// settings read as a pair instead of two near-empty cards.
	let { children }: { children: Snippet } = $props();
</script>

<RailCard title="Discount and tax" class="adjustments-card">
	{@render children()}
</RailCard>

<style lang="scss">
	// The rows run edge to edge with hairlines between them, so the card gives up its own padding.
	:global(:root:has(.app-shell[data-presentation='classic'])) :global(.rail-card.adjustments-card) {
		gap: 0;
		padding: 0;
		overflow: hidden;
	}
	:global(:root:has(.app-shell[data-presentation='classic']))
		:global(.rail-card.adjustments-card .rail-card__header) {
		padding: 18px 20px 14px;
	}
	:global(:root:has(.app-shell[data-presentation='classic']))
		:global(.rail-card.adjustments-card .rail-card__title) {
		font-size: var(--classic2-font-card);
		letter-spacing: -0.2px;
	}
</style>
