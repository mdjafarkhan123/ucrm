<script lang="ts">
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	let {
		open,
		title,
		size = 'default',
		initialFocusId,
		icon,
		iconTone = 'success',
		onClose,
		children,
		footer
	}: {
		open: boolean;
		title: string;
		size?: 'default' | 'small' | 'medium' | 'large';
		initialFocusId?: string;
		/** A Tabler icon (raw SVG) in a tinted tile before the title. Also gives the close button its box. */
		icon?: string;
		/** What the tile's tint says: the kind of record the dialog is about. */
		iconTone?: 'success' | 'warning' | 'critical' | 'informative';
		onClose: () => void;
		children: Snippet;
		/** A bar under the body for the dialog's actions, so they stay in view while the body scrolls. */
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
		<DialogPrimitive.Overlay class="dialog__overlay" />
		<DialogPrimitive.Content
			class="dialog__content dialog__content--{size}"
			onOpenAutoFocus={(event) => {
				if (!initialFocusId) return;
				const target = document.getElementById(initialFocusId);
				if (!(target instanceof HTMLElement)) return;
				event.preventDefault();
				target.focus();
			}}
		>
			<header class="dialog__header" class:dialog__header--icon={icon}>
				{#if icon}
					<span class="dialog__tile dialog__tile--{iconTone}" aria-hidden="true">{@html icon}</span>
				{/if}
				<DialogPrimitive.Title level={2}>{title}</DialogPrimitive.Title>
				<DialogPrimitive.Close class="dialog__close" aria-label="Close">
					{@html closeIcon}
				</DialogPrimitive.Close>
			</header>
			<div class="dialog__body" class:dialog__body--footed={footer}>
				{@render children()}
			</div>
			{#if footer}
				<footer class="dialog__footer">{@render footer()}</footer>
			{/if}
		</DialogPrimitive.Content>
	</DialogPrimitive.Portal>
</DialogPrimitive.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

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
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
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

	:global(.dialog__header) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	:global(.dialog__header [data-slot='dialog-title']) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tightest);
	}

	:global(.dialog__close) {
		display: grid;
		flex: 0 0 auto;
		width: 32px;
		height: 32px;
		place-items: center;
		margin: calc(var(--space-smaller) * -1);
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	:global(.dialog__body) {
		overflow-y: auto;
		padding: var(--space-large);
	}

	// A dialog with its own icon tile and action bar: a header with no divider, a close button with a box
	// around it, and the actions pinned under the body.
	:global(.dialog__header--icon) {
		justify-content: flex-start;
		padding: 20px 24px 12px;
		border-bottom: none;

		:global([role='heading']) {
			flex: 1 1 auto;
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			font-weight: 700;
			letter-spacing: -0.3px;
			line-height: var(--typography--lineHeight-tightest);
		}

		:global(.dialog__close) {
			width: 34px;
			height: 34px;
			margin: 0;
			border: var(--border-base) solid var(--color-border--interactive);
			background: var(--color-surface);
		}
	}

	:global(.dialog__body--footed) {
		padding-top: var(--space-small);
	}

	:global(.dialog__tile) {
		display: grid;
		flex: 0 0 auto;
		width: 36px;
		height: 36px;
		place-items: center;
		border-radius: 10px;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}

	:global(.dialog__tile--success) {
		background-color: var(--color-success--surface);
		color: var(--color-success--onSurface);
	}

	:global(.dialog__tile--warning) {
		background-color: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
	}

	:global(.dialog__tile--critical) {
		background-color: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
	}

	:global(.dialog__tile--informative) {
		background-color: var(--color-informative--surface);
		color: var(--color-informative--onSurface);
	}

	:global(.dialog__footer) {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
		padding: 14px 24px;
		border-top: var(--border-base) solid var(--color-border);

		// A lone action sits at the right, where the main action of a dialog always is.
		> :only-child {
			margin-left: auto;
		}
	}
</style>
