<script lang="ts">
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import DialogHeader from '$lib/components/ui/DialogHeader.svelte';

	// The form pop-up (`concept.pen` → Pop-ups): a short form that belongs to the page behind it.
	let {
		open,
		title,
		subtitle,
		size = 'default',
		width,
		initialFocusId,
		icon,
		iconTone = 'success',
		flush = false,
		badge,
		lead,
		bare = false,
		closeDisabled = false,
		onClose,
		children,
		footer
	}: {
		open: boolean;
		title: string;
		subtitle?: string;
		size?: 'default' | 'small' | 'medium' | 'large';
		/** A drawn width in pixels between the named sizes, e.g. 440 for the discount pop-up. */
		width?: number;
		initialFocusId?: string;
		/** A Tabler icon (raw SVG) on a tile before the title. */
		icon?: string;
		/** The tile's colour family: the record the dialog is about (`job`, `invoice`…), or a status. */
		iconTone?: string;
		/** No padding round the body, for a body that lays out its own panels edge to edge. */
		flush?: boolean;
		/** A small pill beside the title, e.g. "Recurring". */
		badge?: Snippet;
		/** Drawn in place of the icon tile, e.g. a country's flag. */
		lead?: Snippet;
		/** Only the × at the top, for a centred result that names itself in its body; the title stays for screen readers. */
		bare?: boolean;
		/** While something can't be interrupted, the × is greyed and Escape or a click outside does nothing. */
		closeDisabled?: boolean;
		onClose: () => void;
		children: Snippet;
		/** A bar under the body for the dialog's actions, so they stay in view while the body scrolls. */
		footer?: Snippet;
	} = $props();
</script>

<DialogPrimitive.Root
	{open}
	onOpenChange={(next) => {
		if (!next && !closeDisabled) onClose();
	}}
>
	<DialogPrimitive.Portal>
		<DialogPrimitive.Overlay class="dialog__overlay" />
		<DialogPrimitive.Content
			class="dialog__content dialog__content--{size}"
			style={width ? `--modal--width: ${width}px` : undefined}
			escapeKeydownBehavior={closeDisabled ? 'ignore' : 'close'}
			interactOutsideBehavior={closeDisabled ? 'ignore' : 'close'}
			onOpenAutoFocus={(event) => {
				if (!initialFocusId) return;
				const target = document.getElementById(initialFocusId);
				if (!(target instanceof HTMLElement)) return;
				event.preventDefault();
				target.focus();
			}}
		>
			<DialogHeader {title} {subtitle} {icon} tone={iconTone} {badge} {lead} {bare} {closeDisabled} />
			<div class="dialog__body" class:dialog__body--flush={flush}>
				{@render children()}
			</div>
			{#if footer}
				<footer class="dialog__footer">{@render footer()}</footer>
			{/if}
		</DialogPrimitive.Content>
	</DialogPrimitive.Portal>
</DialogPrimitive.Root>

<style lang="scss">
	:global(.dialog__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}

	:global(.dialog__content) {
		position: fixed;
		top: 50%;
		left: 50%;
		z-index: var(--elevation-modal);
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		width: min(calc(100vw - var(--space-large) * 2), var(--modal--width, 600px));
		max-height: calc(100dvh - var(--space-large) * 2);
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		transform: translate(-50%, -50%);
	}

	:global(.dialog__content--small) {
		--modal--width: 400px;
	}

	:global(.dialog__content--medium) {
		--modal--width: 640px;
	}

	:global(.dialog__content--large) {
		--modal--width: 940px;
	}

	:global(.dialog__body) {
		flex: 1 1 auto;
		overflow-y: auto;
		padding: var(--space-medium);
	}

	:global(.dialog__body--flush) {
		padding: 0;
	}

	:global(.dialog__footer) {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-base) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);

		// A lone action sits at the right, where the main action of a dialog always is.
		> :global(:only-child) {
			margin-left: auto;
		}
	}
</style>
