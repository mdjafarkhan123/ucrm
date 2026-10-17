<script lang="ts">
	import type { Snippet } from 'svelte';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';

	let {
		title,
		description,
		icon,
		tone = 'informative',
		presentation = 'workflow',
		compactDescription = false,
		actions
	}: {
		title: string;
		description: string;
		icon: string;
		tone?: 'informative' | 'warning' | 'job' | 'invoice' | 'quote' | 'task';
		/** Preserves the three approved Settings heading compositions. */
		presentation?: 'business' | 'workflow' | 'communication';
		compactDescription?: boolean;
		actions?: Snippet;
	} = $props();
</script>

<div
	class={['settings-page-header', `settings-page-header--${presentation}`, compactDescription && 'settings-page-header--compact-description']}
	style={`--settings-header-tone: var(--color-${tone}); --settings-header-ink: var(--color-${tone === 'warning' ? 'heading' : 'text--reverse'})`}
>
	{#snippet breadcrumb()}
		<Breadcrumbs items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: title }]} />
	{/snippet}
	{#if presentation === 'business'}{@render breadcrumb()}{/if}
	<div class="settings-page-header__row">
		<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted build-time Tabler icon -->
		<span class="settings-page-header__icon" aria-hidden="true">{@html icon}</span>
		<div class="settings-page-header__copy">
			{#if presentation !== 'business'}{@render breadcrumb()}{/if}
			<PageHeader {title} {description} />
		</div>
		{#if actions}<div class="settings-page-header__actions">{@render actions()}</div>{/if}
	</div>
</div>

<style lang="scss">
	.settings-page-header {
		&__row {
			display: flex;
			align-items: flex-start;
			gap: 18px;
			margin-top: 16px;
		}
		&__icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 60px;
			height: 60px;
			margin-top: 4px;
			border-radius: 18px;
			background: var(--settings-header-tone);
			color: var(--settings-header-ink);
			box-shadow: 0 6px 16px color-mix(in srgb, var(--settings-header-tone) 35%, transparent);
		}
		&__icon :global(svg) { display: block; width: 28px; height: 28px; }
		&__copy { flex: 1; min-width: 0; }
		&__copy :global(.page-header) { margin: 0; padding: 0; }
		&__actions {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			align-self: flex-end;
			gap: 10px;
		}
		&--workflow {
			margin-bottom: var(--space-large);
			:global(.breadcrumbs) { margin-bottom: 6px; font-size: 13px; font-weight: 600; }
			:global(.breadcrumbs a svg) { display: none; }
			:global(.page-header h1) { font-size: 36px; font-weight: 900; }
			:global(.page-header__description) { max-width: none; font-size: 14px; }
		}
		&--communication {
			:global(.breadcrumbs) { margin-bottom: 4px; font-size: 13px; font-weight: 600; }
			:global(.breadcrumbs a svg) { display: none; }
			:global(.page-header__copy) { gap: var(--space-smaller); }
			:global(.page-header h1) { font-size: 36px; line-height: var(--typography--lineHeight-tight); }
			:global(.page-header__description) { max-width: none; font-size: 14px; }
		}
		&--compact-description :global(.page-header__copy) { gap: 2px; }
		&--business &__row {
			align-items: center;
			gap: var(--space-base);
			margin: var(--space-base) 0 var(--space-large);
		}
		&--business &__icon {
			width: 56px;
			height: 56px;
			margin-top: 0;
			border-radius: var(--radius-base);
			box-shadow: var(--shadow-base);
		}
	}
	@media (max-width: 639px) {
		.settings-page-header--workflow .settings-page-header__row { flex-wrap: wrap; }
		.settings-page-header--communication :global(.page-header h1) { font-size: 28px; }
	}
</style>
