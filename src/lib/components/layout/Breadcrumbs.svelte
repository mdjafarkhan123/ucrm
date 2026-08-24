<script lang="ts">
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';

	let { items }: { items: { label: string; href?: string }[] } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<nav class="breadcrumbs" aria-label="Breadcrumb">
	{#each items as item, i (item.label)}
		{#if i > 0}<span aria-hidden="true">/</span>{/if}
		{#if item.href}
			<a href={item.href}
				>{#if i === 0}<span aria-hidden="true">{@html arrowLeftIcon}</span>{/if}{item.label}</a
			>
		{:else}
			<span>{item.label}</span>
		{/if}
	{/each}
</nav>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.breadcrumbs {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-bottom: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		a {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smallest);
			color: var(--color-interactive);
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
</style>
