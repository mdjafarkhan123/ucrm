<script lang="ts">
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	// A panel that slides in from the right and leaves the page behind it visible. Use it when the user
	// has to look at one record without losing their place in a list or a board — `Dialog` is the
	// centred one, for a decision that owns the whole screen.
	//
	// It is the same Bits UI dialog underneath, so focus trapping, Escape, and the overlay all behave
	// the way every other modal in the app does.
	let {
		open,
		title,
		subtitle,
		onClose,
		children,
		footer
	}: {
		open: boolean;
		title: string;
		/** One line under the title, for an amount, a reference, or a status summary. */
		subtitle?: string;
		onClose: () => void;
		children: Snippet;
		footer?: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<DialogPrimitive.Root
	{open}
	onOpenChange={(next) => {
		if (!next) onClose();
	}}
>
	<DialogPrimitive.Portal>
		<DialogPrimitive.Overlay class="side-panel__overlay" />
		<DialogPrimitive.Content class="side-panel__content">
			<header class="side-panel__header">
				<div class="side-panel__heading">
					<DialogPrimitive.Title level={2}>{title}</DialogPrimitive.Title>
					{#if subtitle}<p class="side-panel__subtitle">{subtitle}</p>{/if}
				</div>
				<DialogPrimitive.Close class="side-panel__close" aria-label="Close">
					{@html closeIcon}
				</DialogPrimitive.Close>
			</header>
			<div class="side-panel__body">
				{@render children()}
			</div>
			{#if footer}<div class="side-panel__footer">{@render footer()}</div>{/if}
		</DialogPrimitive.Content>
	</DialogPrimitive.Portal>
</DialogPrimitive.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.side-panel__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}

	:global(.side-panel__content) {
		position: fixed;
		top: 0;
		right: 0;
		bottom: 0;
		z-index: var(--elevation-modal);
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		width: min(100vw, var(--side-panel--width, 440px));
		overflow: hidden;
		border-left: var(--border-base) solid var(--color-border);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
	}

	.side-panel__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.side-panel__heading :global(h2) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tight);
	}
	.side-panel__subtitle {
		margin-top: var(--space-smallest);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	:global(.side-panel__close) {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
		width: var(--space-large);
		height: var(--space-large);
		border: none;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
	}
	:global(.side-panel__close:hover) {
		background: var(--color-surface--hover);
	}
	:global(.side-panel__close:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	:global(.side-panel__close svg) {
		width: 20px;
		height: 20px;
	}
	.side-panel__body {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		gap: var(--space-large);
		overflow-y: auto;
		padding: var(--space-large);
	}
	.side-panel__footer {
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}
</style>
