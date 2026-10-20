<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { Snippet } from 'svelte';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';
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

	// The tile takes the banner's own colour family.
	const tones = { notice: 'informative', success: 'success', warning: 'warning', error: 'critical' };

	const defaultIcons = {
		notice: infoIcon,
		success: checkIcon,
		warning: alertIcon,
		error: errorIcon
	};
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="banner banner--{type}" role={type === 'error' ? 'alert' : 'status'}>
	<IconTile icon={icon ?? defaultIcons[type]} tone={tones[type]} size={32} white />
	<div class="banner__content">{@render children()}</div>
	{#if action}<div class="banner__action">{@render action()}</div>{/if}
</div>

<style lang="scss">
	.banner {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-slim);
		border-radius: var(--radius-large);
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
			--banner-solid: var(--color-warning--onSurface);
		}

		&--error {
			--banner-surface: var(--color-critical--surface);
			--banner-textColor: var(--color-critical--onSurface);
			--banner-solid: var(--color-critical);
		}

		&__content {
			flex: 1 1 200px;
			min-width: 0;
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			line-height: 1.45;

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
