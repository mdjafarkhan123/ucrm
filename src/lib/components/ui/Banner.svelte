<script lang="ts">
	import type { Snippet } from 'svelte';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import errorIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// Persistent feedback. Classic uses the approved bordered card and tinted icon tile;
	// other presentations retain their tinted strip. A title and follow-up action are optional.
	let {
		type = 'notice',
		icon,
		title,
		children,
		action
	}: {
		type?: 'notice' | 'success' | 'warning' | 'error';
		icon?: string;
		title?: string;
		children: Snippet;
		action?: Snippet;
	} = $props();

	const defaultIcons = {
		notice: infoIcon,
		success: checkIcon,
		warning: alertIcon,
		error: errorIcon
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="banner banner--{type}" role={type === 'error' ? 'alert' : 'status'}>
	<span class="banner__icon" aria-hidden="true">{@html icon ?? defaultIcons[type]}</span>
	<div class="banner__content">
		{#if title}<strong class="banner__title">{title}</strong>{/if}
		{@render children()}
	</div>
	{#if action}<div class="banner__action">{@render action()}</div>{/if}
</div>

<style lang="scss">
	:global(:root:has(.app-shell[data-presentation='classic'])) .banner {
		gap: 12px;
		padding: 14px;
		border: 1px solid var(--classic2-border);
		border-radius: 14px;
		background: var(--classic2-surface);
		color: var(--classic2-body);
		font-family: var(--classic2-font);

		&--notice {
			--banner-solid: var(--classic2-blue);
			--banner-tile: var(--classic2-blue-soft);
		}
		&--success {
			--banner-solid: var(--classic2-green);
			--banner-tile: var(--classic2-green-soft);
		}
		&--warning {
			--banner-solid: var(--classic2-amber);
			--banner-tile: var(--classic2-amber-soft);
		}
		&--error {
			--banner-solid: var(--classic2-rose);
			--banner-tile: var(--classic2-rose-soft);
		}
		.banner__icon {
			align-items: center;
			justify-content: center;
			width: 34px;
			height: 34px;
			padding: 8px;
			border-radius: 10px;
			color: var(--banner-solid);
			background: var(--banner-tile);
		}
		.banner__content {
			flex-basis: 180px;
			font-size: 12px;
			line-height: 1.5;
			overflow-wrap: anywhere;
		}
		.banner__title {
			display: block;
			margin-bottom: 2px;
			color: var(--classic2-ink);
			font-size: 13px;
			font-weight: 700;
		}
	}

	.banner {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small) var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--banner-textColor);
		background: var(--banner-surface);

		&--notice {
			--banner-surface: var(--color-informative--surface);
			--banner-textColor: var(--color-informative--onSurface);
			--banner-solid: var(--color-informative);
		}

		&--success {
			--banner-surface: var(--color-success--surface);
			--banner-textColor: var(--color-success--onSurface);
			--banner-solid: var(--color-success);
		}

		&--warning {
			--banner-surface: var(--color-warning--surface);
			--banner-textColor: var(--color-warning--onSurface);
			--banner-solid: var(--color-warning);
		}

		&--error {
			--banner-surface: var(--color-critical--surface);
			--banner-textColor: var(--color-critical--onSurface);
			--banner-solid: var(--color-destructive);
		}

		&__icon {
			display: inline-flex;
			flex: 0 0 auto;
			align-self: flex-start;
			width: 2.4rem;
			height: 2.4rem;
			padding: var(--space-smaller);
			border-radius: var(--radius-circle);
			color: var(--color-surface);
			background: var(--banner-solid);

			:global(svg) {
				width: 100%;
				height: 100%;
			}
		}

		&__content {
			flex: 1 1 24rem;
			min-width: 0;
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-base);

			:global(p) {
				margin: 0;
			}

			:global(a) {
				color: inherit;
				text-decoration: underline;

				&:hover {
					color: var(--color-heading);
				}
			}
		}

		&__action {
			flex: 0 0 auto;
		}
	}
</style>
