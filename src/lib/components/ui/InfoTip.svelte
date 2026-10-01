<script lang="ts">
	import { Popover } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';

	// A small "i" button beside a label. Clicking it opens a short explanation next to it; Escape or a click
	// elsewhere closes it. Use it for plain-English help the label alone cannot give.
	let { label, title, children }: { label: string; title: string; children: Snippet } = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Popover.Root>
	<Popover.Trigger class="info-tip__trigger" aria-label={label}>
		{@html infoIcon}
	</Popover.Trigger>
	<Popover.Portal>
		<Popover.Content class="info-tip__content" sideOffset={8} collisionPadding={16}>
			<strong class="info-tip__title">{title}</strong>
			<div class="info-tip__body">{@render children()}</div>
			<Popover.Arrow class="info-tip__arrow" />
		</Popover.Content>
	</Popover.Portal>
</Popover.Root>

<style lang="scss">
	:global(.info-tip__trigger) {
		display: inline-grid;
		width: 24px;
		height: 24px;
		flex: 0 0 auto;
		place-items: center;
		padding: 0;
		border: 0;
		border-radius: var(--radius-circle);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		cursor: pointer;
		transition: filter var(--timing-quick) ease-out;
	}

	:global(.info-tip__trigger:hover) {
		filter: brightness(0.95);
	}

	:global(.info-tip__trigger:focus-visible) {
		outline: none;
		box-shadow: var(--shadow-focus);
	}

	:global(.info-tip__trigger svg) {
		width: 18px;
		height: 18px;
	}

	:global(.info-tip__content) {
		z-index: var(--elevation-tooltip);
		display: grid;
		gap: var(--space-small);
		width: min(360px, calc(100vw - 32px));
		padding: var(--space-base) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		border-top: 3px solid var(--color-informative);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.info-tip__title) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}

	:global(.info-tip__body) {
		display: grid;
		gap: var(--space-small);
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-large);
	}

	:global(.info-tip__body p) {
		margin: 0;
	}

	:global(.info-tip__body dt) {
		color: var(--color-heading);
		font-weight: 600;
	}

	:global(.info-tip__body dd) {
		margin: 0;
		color: var(--color-text--secondary);
	}

	:global(.info-tip__arrow) {
		color: var(--color-surface);
	}
</style>
