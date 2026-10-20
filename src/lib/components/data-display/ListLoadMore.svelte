<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
 import searchIcon from '@tabler/icons/outline/search.svg?raw';
 import chevronsDownIcon from '@tabler/icons/outline/chevrons-down.svg?raw';

	let {
		hasNextPage,
		isFetchingNextPage,
		onLoadMore,
		label = 'Load more',
		endLabel = 'That is all of them.',
		searchNarrowed = false,
		narrowedLabel = 'Many clients match — type more of the name to see the rest.',
		count, recordName = 'records', recordColor = 'inactive'
	}: {
		count?: number; recordName?: string; recordColor?: string;
 hasNextPage: boolean;
		isFetchingNextPage: boolean;
		onLoadMore: () => void;
		/** The button's words, e.g. "Load more jobs". */
		label?: string;
		endLabel?: string;
		/** The search matched more records than the list could include, so this is not all of them. */
		searchNarrowed?: boolean;
		/** What to say when `searchNarrowed` is true. */
		narrowedLabel?: string;
		/** `card` is the footer of a record-list card: a quiet button with a double-chevron icon. */
		variant?: 'default' | 'card';
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="list-load-more" style:--record-color={`var(--color-${recordColor})`}>
 {#if hasNextPage}
 <span class="list-load-more__count">{count === undefined ? '' : `Showing ${count} ${recordName}`}</span>
 <Button variant="secondary" size="small" loading={isFetchingNextPage} onclick={onLoadMore}><span class="list-load-more__icon" aria-hidden="true">{@html chevronsDownIcon}</span>{label}</Button>
 {:else}<span class={['list-load-more__tile',searchNarrowed && 'list-load-more__tile--search']} aria-hidden="true">{@html searchNarrowed ? searchIcon : checkIcon}</span><span>{searchNarrowed ? narrowedLabel : count === undefined ? endLabel : `All ${count} ${recordName} are showing`}</span>{/if}
</div>
<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
.list-load-more {display:flex;align-items:center;gap:10px;padding:10px 12px 10px 16px;border-top:1px solid var(--color-border);background:var(--color-surface--background--subtle);color:var(--color-heading);font-size:var(--typography--fontSize-small);font-weight:500;
 &__count{margin-right:auto;color:var(--color-text--secondary);} &__icon{display:flex;color:var(--record-color);:global(svg){width:16px;height:16px;}}
 &__tile{display:grid;place-items:center;flex:0 0 24px;height:24px;border-radius:var(--radius-tile-small);background:var(--color-success--surface);color:var(--color-success);:global(svg){width:14px;height:14px;}}
 &__tile--search{background:var(--color-informative--surface);color:var(--color-informative);}}
</style>
