<script lang="ts">
	import type { Snippet } from 'svelte';
	import StickyActionBar from './StickyActionBar.svelte';

	// The shape every create and edit page shares: a titled main card, a right rail of cards, and the
	// action bar underneath. Each page decides what goes in the rail, so a request page can show Notes and
	// Attachments while a client page also shows Lead source.
	let {
		title,
		icon,
		main,
		rail,
		actions,
		class: className = ''
	}: {
		title: string;
		icon?: string;
		main: Snippet;
		rail?: Snippet;
		actions?: Snippet;
		class?: string;
	} = $props();

	const uid = $props.id();
	const titleId = `${uid}-title`;
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class={`record-form ${className}`}>
	<div class="record-form__grid" class:record-form__grid--no-rail={!rail}>
		<section class="record-form__main" aria-labelledby={titleId}>
			<header class="record-form__header">
				{#if icon}<span class="record-form__icon" aria-hidden="true">{@html icon}</span>{/if}
				<h1 id={titleId}>{title}</h1>
			</header>
			{@render main()}
		</section>

		{#if rail}
			<aside class="record-form__rail">{@render rail()}</aside>
		{/if}
	</div>

	{#if actions}
		<StickyActionBar>{@render actions()}</StickyActionBar>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.record-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__grid {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(300px, 360px);
			align-items: start;
			gap: var(--space-large);

			&--no-rail {
				grid-template-columns: minmax(0, 1fr);
			}
		}

		&__main {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			box-shadow: var(--shadow-low);
		}

		&__header {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			h1 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
				font-weight: 700;
				line-height: var(--typography--lineHeight-tight);
			}
		}

		&__icon :global(svg) {
			display: block;
			width: 20px;
			height: 20px;
			color: var(--color-icon--secondary);
		}

		&__rail {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}
	}

	@media (max-width: 1079px) {
		.record-form__grid {
			grid-template-columns: 1fr;
		}
	}

	@media (max-width: 767px) {
		.record-form__main {
			padding: var(--space-base);
		}
	}
</style>
