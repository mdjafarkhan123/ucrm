<script lang="ts">
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	let {
		open,
		title,
		size = 'default',
		onClose,
		children
	}: {
		open: boolean;
		title: string;
		size?: 'default' | 'small' | 'large';
		onClose: () => void;
		children: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<DialogPrimitive.Root {open} onOpenChange={(next) => { if (!next) onClose(); }}>
	<DialogPrimitive.Portal>
		<DialogPrimitive.Overlay class="dialog__overlay" />
		<DialogPrimitive.Content class="dialog__content dialog__content--{size}">
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
</style>
