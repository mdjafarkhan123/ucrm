<script lang="ts">
	import type { Snippet } from 'svelte';

	// A card in a page's right rail. The title sits inside the card, not on its border — that border-notch
	// treatment belongs to the main column. See `.claude/skills/design/section-block.md`.
	let {
		title,
		icon,
		count,
		description,
		flush = false,
		actions,
		children,
		class: className = ''
	}: {
		title: string;
		icon?: string;
		count?: number;
		/** One quiet line under the title, e.g. "3 photos · 1 file". */
		description?: string;
		/** App look: the body runs edge to edge under the header, for rows that draw their own padding and
		 *  hairlines. Only the header keeps the card's side padding. */
		flush?: boolean;
		actions?: Snippet;
		children: Snippet;
		class?: string;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class={`rail-card ${className}`} class:rail-card--flush={flush}>
	<header class="rail-card__header">
		<div class="rail-card__heading">
			<h2 class="rail-card__title">
				{#if icon}<span class="rail-card__icon" aria-hidden="true">{@html icon}</span>{/if}
				{title}{#if count !== undefined}<span class="rail-card__count">{count}</span>{/if}
			</h2>
			{#if description}<p class="rail-card__description">{description}</p>{/if}
		</div>
		{#if actions}<div class="rail-card__actions">{@render actions()}</div>{/if}
	</header>
	{@render children()}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.rail-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__title {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: var(--typography--lineHeight-tight);
		}

		&__heading {
			display: grid;
			min-width: 0;
			gap: 2px;
		}

		&__description {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		// Outside the App look the count reads as "Tags (2)".
		&__count {
			&::before {
				content: '\00a0(';
			}
			&::after {
				content: ')';
			}
		}

		&__icon :global(svg) {
			display: block;
			width: 20px;
			height: 20px;
			color: var(--color-icon--secondary);
		}
	}

	// App look (inside `RecordDetailLayout cards`): 8px card, no shadow, a 16px/700 title in a header row
	// with 20px side padding. Rows placed straight in the card may run edge to edge.
	:global(.record-detail--cards) .rail-card {
		gap: 12px;
		padding: 18px 20px 20px;
		box-shadow: none;

		.rail-card__title {
			font-size: var(--typography--fontSize-large);
			letter-spacing: -0.2px;
		}
		.rail-card__icon {
			display: none;
		}
		.rail-card__count {
			margin-left: 8px;
			padding: 2px 8px;
			border-radius: 999px;
			color: var(--color-text--secondary);
			background: var(--color-border);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 0;
			line-height: 1.4;

			&::before,
			&::after {
				content: none;
			}
		}
		.rail-card__description {
			font-size: 12px;
		}
		&.rail-card--flush {
			gap: 0;
			padding: 0;
			overflow: clip;

			.rail-card__header {
				padding: 18px 20px 14px;
			}
		}
	}
</style>
