<script lang="ts">
	import type { Snippet } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	let {
		title = 'Something went wrong',
		description = 'We could not load this information. Try again.',
		retry,
		action,
		size = 'base'
	}: {
		title?: string;
		description?: string;
		retry?: () => void;
		action?: Snippet;
		/** `small` fits a narrow side card: a 32 tile, smaller words and a small Try again. */
		size?: 'base' | 'small';
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="error-state error-state--{size}" aria-labelledby="error-state-title" role="alert">
	<IconTile icon={alertIcon} tone="critical" size={size === 'small' ? 32 : 40} />
	<h2 id="error-state-title">{title}</h2>
	<p>{description}</p>
	{#if retry || action}
		<div class="error-state__action">
			{#if retry}<Button
					variant="secondary"
					size={size === 'small' ? 'small' : 'base'}
					onclick={retry}>{@html refreshIcon}Try again</Button
				>{/if}
			{#if action}{@render action()}{/if}
		</div>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Sits inside the card or page area whose content could not load (`concept.pen` → Pop-ups → Page states).
	.error-state {
		display: grid;
		justify-items: center;
		align-content: center;
		gap: var(--space-slim);
		padding: var(--space-larger) 40px;
		color: var(--color-text--secondary);
		text-align: center;
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		font-weight: 600;
		letter-spacing: -0.2px;
		line-height: var(--typography--lineHeight-tight);
	}
	p {
		max-width: 320px;
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-large);
	}
	.error-state--small {
		gap: var(--space-small);
		padding: var(--space-small);

		h2 {
			font-size: var(--typography--fontSize-label);
			letter-spacing: 0;
		}

		p {
			font-size: var(--typography--fontSize-small);
		}
	}
	.error-state__action {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-small);
		padding-top: var(--space-smaller);
	}
</style>
