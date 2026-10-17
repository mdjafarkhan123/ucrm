<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	let {
		title,
		description,
		icon,
		children
	}: { title: string; description: string; icon: string; children: Snippet } = $props();
</script>

<div class="business-settings">
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: title }]}
	/>
	<div class="business-settings__heading">
		<!-- eslint-disable-next-line svelte/no-at-html-tags -->
		<span class="business-settings__icon" aria-hidden="true">{@html icon}</span>
		<PageHeader {title} {description} />
	</div>
	{@render children()}
</div>

<style lang="scss">
	.business-settings {
		&__heading {
			display: flex;
			align-items: center;
			gap: var(--space-base);
			margin: var(--space-base) 0 var(--space-large);
		}
		&__heading :global(.page-header) {
			margin: 0;
			padding: 0;
		}
		&__icon {
			display: grid;
			place-items: center;
			width: 56px;
			height: 56px;
			flex: 0 0 auto;
			background: var(--color-interactive);
			color: var(--color-text--reverse);
			border-radius: var(--radius-base);
			box-shadow: var(--shadow-base);
		}
		&__icon :global(svg) {
			width: 28px;
			height: 28px;
		}
		:global(.record-form__main) {
			padding: 0;
			border: 0;
			background: transparent;
			box-shadow: none;
			overflow: visible;
		}
		:global(.record-form__header) {
			display: none;
		}
		:global(.section-block) {
			margin: 0;
			padding: 24px;
			background: var(--color-surface);
			gap: 16px;
		}
		:global(.section-block .section-block__title) {
			position: static;
			max-width: none;
			transform: none;
			padding: 0;
			background: transparent;
			font-size: 16px;
		}
		:global(.section-block legend.section-block__title) {
			float: left;
			width: 100%;
			margin-bottom: 16px;
		}
		:global(.section-block__hint) {
			margin: -8px 0 0;
		}
		:global(.section-block__icon) {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			background: var(--color-job--surface);
		}
		:global(.section-block__icon svg) {
			color: var(--color-interactive);
		}
		:global(.sticky-action-bar) {
			max-width: 720px;
			margin-inline: auto;
			background: var(--color-base-blue--900);
			color: var(--color-base-white);
			justify-content: flex-end;
		}
	}
</style>
