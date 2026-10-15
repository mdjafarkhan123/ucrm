<script lang="ts">
	import type { Snippet } from 'svelte';

	// The Classic record-page card from classic.pen: a heading block (title, optional count chip, one line
	// underneath) with its actions on the right, rows that run edge to edge below it, and an optional tinted
	// footer. `size="rail"` is the narrower right-column version with a smaller title and tighter padding.
	//
	// Rows are the caller's own markup; each row draws its own top divider and side padding, so the card
	// never has to know what a row is.
	let {
		title,
		count,
		subtitle,
		size = 'main',
		level = 2,
		id,
		lead,
		actions,
		children,
		footer,
		class: className = ''
	}: {
		title: string;
		count?: number | string;
		subtitle?: string;
		size?: 'main' | 'rail';
		level?: 2 | 3;
		id?: string;
		/** Drawn before the heading, e.g. the Close-out progress ring. */
		lead?: Snippet;
		actions?: Snippet;
		children?: Snippet;
		footer?: Snippet;
		class?: string;
	} = $props();

	const titleId = $derived(id ? `${id}-title` : undefined);
</script>

<section class={`record-card record-card--${size} ${className}`} {id} aria-labelledby={titleId}>
	<header class="record-card__header">
		{#if lead}<div class="record-card__lead">{@render lead()}</div>{/if}
		<div class="record-card__heading">
			<div class="record-card__title-row">
				{#if level === 2}
					<h2 class="record-card__title" id={titleId}>{title}</h2>
				{:else}
					<h3 class="record-card__title" id={titleId}>{title}</h3>
				{/if}
				{#if count !== undefined}<span class="record-card__count">{count}</span>{/if}
			</div>
			{#if subtitle}<p class="record-card__subtitle">{subtitle}</p>{/if}
		</div>
		{#if actions}<div class="record-card__actions">{@render actions()}</div>{/if}
	</header>
	{#if children}{@render children()}{/if}
	{#if footer}<footer class="record-card__footer">{@render footer()}</footer>{/if}
</section>

<style lang="scss">
	.record-card {
		display: flex;
		flex-direction: column;
		min-width: 0;
		overflow: hidden;
		border-radius: var(--classic2-radius-card);
		background: var(--classic2-surface);
		box-shadow:
			inset 0 0 0 1px var(--classic2-border),
			0 1px 2px var(--classic2-shadow-near),
			0 10px 28px var(--classic2-shadow-far);
		font-family: var(--classic2-font);

		&__header {
			display: flex;
			align-items: center;
			gap: 14px;
			padding: 20px 24px;
		}

		&__lead {
			flex: 0 0 auto;
		}

		&__heading {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 3px;
			min-width: 0;
		}

		&__title-row {
			display: flex;
			align-items: center;
			gap: 8px;
		}

		&__title {
			margin: 0;
			color: var(--classic2-ink);
			font-size: 17px;
			font-weight: 700;
			letter-spacing: -0.2px;
			line-height: 1.25;
		}

		&__count {
			display: inline-flex;
			align-items: center;
			padding: 2px 8px;
			border: 1px solid var(--classic2-border);
			border-radius: 999px;
			background: var(--classic2-surface-soft);
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 600;
			line-height: 1.25;
		}

		&__subtitle {
			margin: 0;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-label);
			font-weight: 500;
			line-height: 1.25;
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: 8px;
			margin-left: auto;
		}

		&__footer {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
			padding: 12px 24px;
			border-top: 1px solid var(--classic2-divider);
			background: var(--classic2-surface-soft);
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-small);
			font-weight: 500;
		}

		&--rail &__header {
			padding: 18px 20px 14px;
		}

		&--rail &__heading {
			gap: 2px;
		}

		&--rail &__title {
			font-size: var(--classic2-font-card);
		}

		&--rail &__subtitle {
			font-size: var(--classic2-font-small);
		}

		&--rail &__footer {
			padding: 12px 20px;
		}
	}

	@media (max-width: 767px) {
		.record-card__header {
			flex-wrap: wrap;
			padding: 16px;
		}

		.record-card__footer {
			padding: 12px 16px;
		}
	}
</style>
