<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';

	let {
		title,
		description,
		icon,
		actions
	}: { title: string; description: string; icon: string; actions?: Snippet } = $props();
</script>

<!-- The Settings "App look" heading: a coloured icon tile beside the breadcrumb, title and sentence. -->
<div class="workflow-header">
	<!-- eslint-disable-next-line svelte/no-at-html-tags -->
	<span class="workflow-header__icon" aria-hidden="true">{@html icon}</span>
	<div class="workflow-header__copy">
		<Breadcrumbs
			items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: title }]}
		/>
		<PageHeader {title} {description} />
	</div>
	{#if actions}<div class="workflow-header__actions">{@render actions()}</div>{/if}
</div>

<style lang="scss">
	.workflow-header {
		display: flex;
		align-items: flex-start;
		gap: 18px;
		margin-top: 16px;
		margin-bottom: var(--space-large);

		&__icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 60px;
			height: 60px;
			margin-top: 4px;
			border-radius: 18px;
			background: var(--color-informative);
			color: var(--color-white);
			box-shadow: 0 6px 16px color-mix(in srgb, var(--color-informative) 35%, transparent);
		}
		&__icon :global(svg) {
			width: 28px;
			height: 28px;
		}
		&__copy {
			flex: 1;
			min-width: 0;
		}
		&__copy :global(.breadcrumbs) {
			margin-bottom: 6px;
			font-size: 13px;
			font-weight: 600;
		}
		&__copy :global(.breadcrumbs a:first-child) {
			color: var(--color-interactive);
		}
		&__copy :global(.breadcrumbs a svg) {
			display: none;
		}
		&__copy :global(.page-header) {
			margin: 0;
			padding: 0;
		}
		&__copy :global(.page-header__description) {
			max-width: none;
			font-size: 14px;
		}
		&__copy :global(.page-header h1) {
			font-size: 30px;
			font-weight: 800;
		}
		&__actions {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: 10px;
			align-self: flex-end;
		}
	}
	@media (max-width: 639px) {
		.workflow-header {
			flex-wrap: wrap;
		}
	}
</style>
