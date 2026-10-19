<script lang="ts">
	import type { Snippet } from 'svelte';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	let {
		title,
		description,
		icon = inboxIcon,
		tone = 'informative',
		iconLabel,
		onIconClick,
		action
	}: {
		title: string;
		description?: string;
		icon?: string;
		/** The tile's colour family: the page's record or section colour (`client`, `job`, `time`…). */
		tone?: string;
		/** Accessible name for the icon button. Required when `onIconClick` is set. */
		iconLabel?: string;
		/** Turns the icon into a real button, for empty states whose icon starts the work. */
		onIconClick?: () => void;
		action?: Snippet;
	} = $props();

	// A page can show several of these at once, so each one labels itself.
	const uid = $props.id();
	const titleId = `${uid}-title`;
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="empty-state" aria-labelledby={titleId}>
	{#if onIconClick}
		<button
			type="button"
			class="empty-state__icon-button"
			aria-label={iconLabel}
			title={iconLabel}
			onclick={onIconClick}
		>
			<IconTile {icon} {tone} />
		</button>
	{:else}
		<IconTile {icon} {tone} />
	{/if}
	<h2 id={titleId}>{title}</h2>
	{#if description}<p>{description}</p>{/if}
	{#if action}<div class="empty-state__action">{@render action()}</div>{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// Sits inside the card or page area that would hold the content (`concept.pen` → Pop-ups → Page states).
	.empty-state {
		display: grid;
		justify-items: center;
		// Stretched to fill a tall page, the rows stay together in the middle instead of spreading apart.
		align-content: center;
		gap: var(--space-slim);
		padding: var(--space-larger) 40px;
		color: var(--color-text--secondary);
		text-align: center;
	}
	.empty-state__icon-button {
		display: inline-flex;
		padding: 0;
		border: 0;
		border-radius: var(--radius-tile-large);
		background: none;
		cursor: pointer;
		transition: box-shadow var(--timing-base) ease-out;

		&:hover {
			box-shadow: 0 0 0 var(--border-base) var(--color-border--interactive--hover);
		}
		&:focus-visible,
		&:active {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}
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
	.empty-state__action {
		padding-top: var(--space-smaller);
	}
</style>
