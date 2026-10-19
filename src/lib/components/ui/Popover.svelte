<script lang="ts">
	import { Popover as PopoverPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import IconTile from './IconTile.svelte';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import type { PopoverAnchor } from './popover-anchor';

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
		subtitle,
		badge,
		concept = false,
		icon,
		iconTone = 'time',
		onClose,
		children
	}: {
		open: boolean;
		/** What the popover points at -- an element, or a bare point. Nothing is drawn until there is one. */
		anchor: PopoverAnchor | null;
		title: string;
		/** A line under the title, for what the title is about -- the work, or what a date holds. */
		subtitle?: Snippet;
		badge?: Snippet;
		concept?: boolean;
		icon?: string;
		iconTone?: string;
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
			class={['popover', concept && 'popover--concept']}
			customAnchor={anchor}
			sideOffset={10}
			collisionPadding={16}
			onCloseAutoFocus={(event) => {
				// There is no trigger to hand focus back to, so the page's own anchor takes it. Without this
				// the focus ring would land back at the top of the document. A point anchor is not an element
				// and has nothing to focus, so the ring simply stays where the browser left it.
				event.preventDefault();
				if (anchor instanceof HTMLElement) anchor.focus();
			}}
		>
			<header class="popover__header">
				{#if icon}<IconTile {icon} tone={iconTone} />{/if}
				<div class="popover__heading">
					<div class="popover__heading-line">
						<h2 class="popover__title">{title}</h2>
						{@render badge?.()}
					</div>
					{#if subtitle}<p class="popover__subtitle">{@render subtitle()}</p>{/if}
				</div>
				<PopoverPrimitive.Close class="popover__close" aria-label="Close">
					{@html closeIcon}
				</PopoverPrimitive.Close>
			</header>
			<div class="popover__body">
				{@render children()}
			</div>
			{#if !concept}<PopoverPrimitive.Arrow class="popover__arrow" />{/if}
		</PopoverPrimitive.Content>
	</PopoverPrimitive.Portal>
</PopoverPrimitive.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.popover--concept) {
		width: 368px;
		max-width: calc(100vw - var(--space-larger));
		border-radius: var(--radius-large);
		overflow: hidden;
	}
	:global(.popover--concept) .popover__header {
		align-items: center;
		padding: var(--space-medium);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	:global(.popover--concept) .popover__heading {
		flex: 1;
	}
	:global(.popover--concept) .popover__title {
		font-size: var(--typography--fontSize-larger);
		font-weight: 600;
		letter-spacing: -0.2px;
		line-height: 1.2;
		overflow-wrap: anywhere;
	}
	:global(.popover--concept) .popover__body {
		padding: var(--space-medium);
	}
	:global(.popover--concept .popover__close) {
		width: 32px;
		height: 32px;
	}

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

	.popover__heading-line {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.popover__heading {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
	}

	.popover__subtitle {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tight);
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
