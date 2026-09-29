<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';

	let {
		hasNextPage,
		isFetchingNextPage,
		onLoadMore,
		endLabel = 'That is all of them.',
		searchNarrowed = false
	}: {
		hasNextPage: boolean;
		isFetchingNextPage: boolean;
		onLoadMore: () => void;
		endLabel?: string;
		/** The search matched more clients than the list could include, so this is not all of them. */
		searchNarrowed?: boolean;
	} = $props();
</script>

<div class="list-load-more">
	{#if hasNextPage}
		<Button variant="secondary" onclick={onLoadMore} disabled={isFetchingNextPage}>
			{isFetchingNextPage ? 'Loading…' : 'Load more'}
		</Button>
	{:else}
		<span class="list-load-more__end">
			{searchNarrowed ? 'Many clients match — type more of the name to see the rest.' : endLabel}
		</span>
	{/if}
</div>

<style lang="scss">
	.list-load-more {
		display: flex;
		justify-content: center;
		padding: var(--space-base);

		&__end {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
