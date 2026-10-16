<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import chevronsDownIcon from '@tabler/icons/outline/chevrons-down.svg?raw';

	let {
		hasNextPage,
		isFetchingNextPage,
		onLoadMore,
		label = 'Load more',
		endLabel = 'That is all of them.',
		searchNarrowed = false,
		narrowedLabel = 'Many clients match — type more of the name to see the rest.',
		variant = 'default'
	}: {
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
<div class={['list-load-more', variant === 'card' && 'list-load-more--card']}>
	{#if hasNextPage}
		<Button
			variant="secondary"
			class={variant === 'card' ? 'list-load-more__button' : ''}
			onclick={onLoadMore}
			disabled={isFetchingNextPage}
		>
			{#if variant === 'card'}
				<span class="list-load-more__icon" aria-hidden="true">{@html chevronsDownIcon}</span>
			{/if}
			{isFetchingNextPage ? 'Loading…' : label}
		</Button>
	{:else}
		<span class="list-load-more__end">
			{searchNarrowed ? narrowedLabel : endLabel}
		</span>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.list-load-more {
		display: flex;
		justify-content: center;
		padding: var(--space-base);

		&__end {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&--card {
			padding: 14px var(--space-large);
		}
		&--card &__end {
			font-size: 13px;
		}
		&__icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 15px;
				height: 15px;
			}
		}
	}
	:global(.list-load-more__button) {
		min-height: 38px;
		padding: 0 var(--space-base);
		border-color: var(--color-border);
		border-radius: 12px;
		color: var(--color-text);
		font-size: 13px;
		gap: 6px;
	}
</style>
