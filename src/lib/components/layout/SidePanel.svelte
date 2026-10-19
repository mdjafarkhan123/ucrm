<script lang="ts">
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import DialogHeader from '$lib/components/ui/DialogHeader.svelte';

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
		icon,
		iconTone = 'inactive',
		onClose,
		children,
		footer
	}: {
		open: boolean;
		title: string;
		/** One line under the title, for an amount, a reference, or a status summary. */
		subtitle?: string;
		/** A Tabler icon (raw SVG) on a tile before the title. */
		icon?: string;
		/** The tile's colour family: the record or part of the app the panel shows. */
		iconTone?: string;
		onClose: () => void;
		children: Snippet;
		footer?: Snippet;
	} = $props();
</script>

<DialogPrimitive.Root
	{open}
	onOpenChange={(next) => {
		if (!next) onClose();
	}}
>
	<DialogPrimitive.Portal>
		<DialogPrimitive.Overlay class="side-panel__overlay" />
		<DialogPrimitive.Content class="side-panel__content">
			<DialogHeader {title} {subtitle} {icon} tone={iconTone} />
			<div class="side-panel__body">
				{@render children()}
			</div>
			{#if footer}<div class="side-panel__footer">{@render footer()}</div>{/if}
		</DialogPrimitive.Content>
	</DialogPrimitive.Portal>
</DialogPrimitive.Root>

<style lang="scss">
	:global(.side-panel__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}

	// Floats 12 from the window's edges, so it reads as a card laid over the page.
	:global(.side-panel__content) {
		position: fixed;
		top: var(--space-slim);
		right: var(--space-slim);
		bottom: var(--space-slim);
		z-index: var(--elevation-modal);
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		width: min(calc(100vw - var(--space-slim) * 2), var(--side-panel--width, 480px));
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	.side-panel__body {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		gap: var(--space-medium);
		overflow-y: auto;
		padding: var(--space-medium);
	}
	.side-panel__footer {
		flex: 0 0 auto;
		padding: var(--space-base) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}
</style>
