<script lang="ts">
	import type { Snippet } from 'svelte';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import errorIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// The design system's Banner (design skill, alerts.md): a borderless tinted strip that stays until its
	// condition resolves. Message first, then an optional action.
	let {
		type = 'notice',
		icon,
		children,
		action
	}: {
		type?: 'notice' | 'success' | 'warning' | 'error';
		icon?: string;
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
	<div class="banner__content">{@render children()}</div>
	{#if action}<div class="banner__action">{@render action()}</div>{/if}
</div>

<style lang="scss">
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
