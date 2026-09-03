<script lang="ts">
	import { Popover as PopoverPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';

	// A popover that floats beside something the page has selected, rather than beside its own trigger.
	//
	// A calendar has hundreds of cards and one popover. Giving every card its own would build hundreds of
	// floating layers to keep one of them open, so the page keeps the selection and hands the chosen element
	// here as the anchor. Bits UI supports exactly this through `customAnchor`, and still owns the
	// positioning, Escape key, click-outside and focus behaviour.

	let {
		open,
		anchor,
		title,
		onClose,
		children
	}: {
		open: boolean;
		/** The element the popover points at. Nothing is drawn until there is one. */
		anchor: HTMLElement | null;
		title: string;
		onClose: () => void;
		children: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<PopoverPrimitive.Root
	open={open && anchor !== null}
	onOpenChange={(next) => {
		if (!next) onClose();
	}}
>
	<PopoverPrimitive.Portal>
		<PopoverPrimitive.Content
			class="popover"
			customAnchor={anchor}
			sideOffset={10}
			collisionPadding={16}
			onCloseAutoFocus={(event) => {
				// There is no trigger to hand focus back to, so the page's own anchor takes it. Without this
				// the focus ring would land back at the top of the document.
				event.preventDefault();
				anchor?.focus();
			}}
		>
			<header class="popover__header">
				<h2 class="popover__title">{title}</h2>
				<PopoverPrimitive.Close class="popover__close" aria-label="Close">
					{@html closeIcon}
				</PopoverPrimitive.Close>
			</header>
			<div class="popover__body">
				{@render children()}
			</div>
			<PopoverPrimitive.Arrow class="popover__arrow" />
		</PopoverPrimitive.Content>
	</PopoverPrimitive.Portal>
</PopoverPrimitive.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.popover) {
		z-index: var(--elevation-tooltip);
		box-sizing: border-box;
		width: max-content;
		max-width: 350px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background-color: var(--color-surface);
		box-shadow: var(--shadow-base);
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);

		&:focus-visible {
			outline: none;
		}
	}

	:global(.popover__arrow) {
		color: var(--color-border);
	}

	.popover__header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-small);
		padding: var(--space-base) var(--space-base) 0;
	}

	.popover__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
		line-height: var(--typography--lineHeight-large);
	}

	:global(.popover__close) {
		display: inline-flex;
		flex-shrink: 0;
		align-items: center;
		justify-content: center;
		padding: var(--space-smaller);
		border: none;
		border-radius: var(--radius-small);
		background: none;
		color: var(--color-icon--secondary);
		cursor: pointer;

		&:hover {
			background-color: var(--color-surface--hover);
			color: var(--color-icon);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.popover__body {
		padding: var(--space-base);
	}
</style>
