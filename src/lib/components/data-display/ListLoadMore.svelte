<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';

	let {
		hasNextPage,
		isFetchingNextPage,
		onLoadMore,
		endLabel = 'That is all of them.'
	}: {
		hasNextPage: boolean;
		isFetchingNextPage: boolean;
		onLoadMore: () => void;
		endLabel?: string;
	} = $props();
</script>

<div class="list-load-more">
	{#if hasNextPage}
		<Button variant="secondary" onclick={onLoadMore} disabled={isFetchingNextPage}>
			{isFetchingNextPage ? 'Loading…' : 'Load more'}
		</Button>
	{:else}
		<span class="list-load-more__end">{endLabel}</span>
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
