<script lang="ts">
	import { Tooltip } from 'bits-ui';
	import type { Snippet } from 'svelte';

	// A short dark label that appears on hover or keyboard focus. The caller renders its own element and
	// spreads `props` onto it, so the tooltip can sit on a link, a chip or a button without extra wrappers.
	// `disabled` keeps the element but shows nothing (for text that is only sometimes cut off).
	let {
		text,
		disabled = false,
		side = 'top',
		children
	}: {
		text: string;
		disabled?: boolean;
		side?: 'top' | 'bottom' | 'left' | 'right';
		children: Snippet<[Record<string, unknown>]>;
	} = $props();
</script>

<Tooltip.Provider delayDuration={300}>
	<Tooltip.Root {disabled}>
		<Tooltip.Trigger>
			{#snippet child({ props })}
				{@render children(props)}
			{/snippet}
		</Tooltip.Trigger>
		<Tooltip.Portal>
			<Tooltip.Content class="tooltip" {side} sideOffset={8} collisionPadding={16}>
				{text}
				<Tooltip.Arrow class="tooltip__arrow" />
			</Tooltip.Content>
		</Tooltip.Portal>
	</Tooltip.Root>
</Tooltip.Provider>

<style lang="scss">
	:global(.tooltip) {
		z-index: var(--elevation-tooltip);
		max-width: 250px;
		padding: var(--space-small) calc(var(--space-small) + var(--space-smaller));
		border-radius: var(--radius-base);
		color: var(--color-text--reverse);
		background: var(--color-surface--reverse);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
		line-height: var(--typography--lineHeight-base);
		overflow-wrap: anywhere;
		pointer-events: none;
		animation: tooltip-in 150ms ease-out;
	}

	:global(.tooltip__arrow) {
		color: var(--color-surface--reverse);
	}

	@keyframes tooltip-in {
		from {
			opacity: 0;
		}

		to {
			opacity: 1;
		}
	}
</style>
