<script lang="ts">
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import chevronIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import folderIcon from '@tabler/icons/outline/folder.svg?raw';
	import fileIcon from '@tabler/icons/outline/file-text.svg?raw';

	let { items }: { items: { label: string; href?: string; icon?: string }[] } = $props();
</script>

<!-- Callers provide resolved hrefs, as with the shared Button. -->
<!-- eslint-disable svelte/no-navigation-without-resolve -->
<!-- eslint-disable svelte/no-at-html-tags -->
<nav class="breadcrumbs" aria-label="Breadcrumb">
	<ol class="breadcrumbs__trail">
		{#each items as item, i (`${i}-${item.label}`)}
			<li class="breadcrumbs__item">
				{#if i > 0}<span class="breadcrumbs__separator" aria-hidden="true">{@html chevronIcon}</span
					>{/if}
				{#if item.href && i !== items.length - 1}
					<a href={item.href} class={['breadcrumbs__step', i === 0 && 'breadcrumbs__step--first']}>
						<span
							class={['breadcrumbs__icon', i === 0 && 'breadcrumbs__icon--back']}
							aria-hidden="true">{@html i === 0 ? arrowLeftIcon : (item.icon ?? folderIcon)}</span
						>
						<span class="breadcrumbs__label">{item.label}</span>
					</a>
				{:else}
					<span
						class={['breadcrumbs__step', 'breadcrumbs__step--current']}
						aria-current={i === items.length - 1 ? 'page' : undefined}
					>
						<span class="breadcrumbs__icon" aria-hidden="true">{@html item.icon ?? fileIcon}</span>
						<span class="breadcrumbs__label">{item.label}</span>
					</span>
				{/if}
			</li>
		{/each}
	</ol>
</nav>

<!-- eslint-enable svelte/no-at-html-tags -->
<!-- eslint-enable svelte/no-navigation-without-resolve -->

<style lang="scss">
	.breadcrumbs {
		max-width: 100%;
		margin-bottom: 14px;
	}
	.breadcrumbs__trail {
		display: inline-flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-smallest);
		max-width: 100%;
		margin: 0;
		padding: var(--space-smaller);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-circle);
		background: var(--color-surface);
		list-style: none;
	}
	.breadcrumbs__item {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		min-width: 0;
		max-width: 100%;
	}
	.breadcrumbs__step {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		min-width: 0;
		padding: 6px var(--space-slim);
		border-radius: var(--radius-circle);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-label);
		font-weight: 500;
		line-height: 20px;
		text-decoration: none;
	}
	a.breadcrumbs__step {
		&:hover,
		&:active {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: 2px solid var(--color-focus);
			outline-offset: 2px;
		}
	}
	.breadcrumbs__step--first {
		padding: var(--space-smaller) var(--space-slim) var(--space-smaller) var(--space-smaller);
	}
	.breadcrumbs__step--current {
		color: var(--color-heading);
		background: var(--color-surface--background);
		font-weight: 600;
	}
	.breadcrumbs__icon,
	.breadcrumbs__separator {
		display: inline-flex;
		flex-shrink: 0;
		align-items: center;
		justify-content: center;
		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	.breadcrumbs__icon--back {
		width: 24px;
		height: 24px;
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--color-heading);
	}
	.breadcrumbs__separator {
		color: var(--color-icon--secondary);
		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.breadcrumbs__label {
		overflow-wrap: anywhere;
	}
</style>
