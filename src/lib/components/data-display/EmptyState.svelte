<script lang="ts">
	import type { Snippet } from 'svelte';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	let {
		title,
		description,
		icon = inboxIcon,
		iconLabel,
		onIconClick,
		action
	}: {
		title: string;
		description?: string;
		icon?: string;
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
			class="empty-state__icon empty-state__icon--button"
			aria-label={iconLabel}
			title={iconLabel}
			onclick={onIconClick}
		>
			{@html icon}
		</button>
	{:else}
		<div class="empty-state__icon" aria-hidden="true">{@html icon}</div>
	{/if}
	<h2 id={titleId}>{title}</h2>
	{#if description}<p>{description}</p>{/if}
	{#if action}<div class="empty-state__action">{@render action()}</div>{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.empty-state {
		display: grid;
		justify-items: center;
		gap: var(--space-base);
		padding: var(--space-extravagant) var(--space-large);
		border: var(--border-base) dashed var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.empty-state__icon {
		display: grid;
		place-items: center;
		width: var(--space-largest);
		height: var(--space-largest);
		border-radius: var(--radius-circle);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.empty-state__icon :global(svg) {
		width: 24px;
		height: 24px;
	}
	.empty-state__icon--button {
		padding: 0;
		border: var(--border-base) solid transparent;
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover,
		&:focus-visible {
			border-color: var(--color-border--interactive);
			color: var(--color-interactive--hover);
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
		line-height: var(--typography--lineHeight-tight);
	}
	p {
		max-width: 48ch;
		line-height: var(--typography--lineHeight-large);
	}
</style>
