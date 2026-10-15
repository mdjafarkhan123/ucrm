<script lang="ts">
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	let {
		open,
		title,
		size = 'default',
		initialFocusId,
		onClose,
		children
	}: {
		open: boolean;
		title: string;
		size?: 'default' | 'small' | 'large';
		initialFocusId?: string;
		onClose: () => void;
		children: Snippet;
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
			<header class="dialog__header">
				<DialogPrimitive.Title level={2}>{title}</DialogPrimitive.Title>
				<DialogPrimitive.Close class="dialog__close" aria-label="Close">
					{@html closeIcon}
				</DialogPrimitive.Close>
			</header>
			<div class="dialog__body">
				{@render children()}
			</div>
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

	:global(:root:has(.app-shell[data-presentation='classic'])) .dialog__overlay {
		background: var(--classic2-overlay);
		backdrop-filter: blur(2px);
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) .dialog__content {
		width: min(calc(100vw - 48px), var(--modal--width, 600px));
		max-height: calc(100dvh - 48px);
		border-color: var(--classic2-border);
		border-radius: var(--classic2-radius-card);
		background: var(--classic2-surface);
		box-shadow: 0 20px 56px var(--classic2-shadow-lift);
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) .dialog__header {
		gap: var(--classic2-space-3);
		padding: var(--classic2-space-4) var(--classic2-space-5);
		border-color: var(--classic2-divider);
	}
	:global(:root:has(.app-shell[data-presentation='classic']))
		.dialog__header
		[data-slot='dialog-title'] {
		color: var(--classic2-ink);
		font-family: var(--classic2-font);
		font-size: var(--classic2-font-section);
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) .dialog__close {
		border-radius: 10px;
		color: var(--classic2-muted);
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) .dialog__close:hover {
		color: var(--classic2-ink);
		background: var(--classic2-surface-soft);
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) .dialog__close:focus-visible {
		outline: 3px solid var(--classic2-green-soft);
		outline-offset: 2px;
	}
	:global(:root:has(.app-shell[data-presentation='classic'])) .dialog__body {
		padding: var(--classic2-space-5);
	}
</style>
