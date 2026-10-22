<script lang="ts">
	import type { Snippet } from 'svelte';
	import { Dialog as DialogPrimitive } from 'bits-ui';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';

	// The header the form pop-up (`Dialog`) and the side drawer (`SidePanel`) share (`concept.pen` → Pop-ups):
	// a 40 tile in the colour of the record it is about, the title with an optional quiet line under it, the
	// close button, and a hairline underneath. Must sit inside a Bits UI dialog.
	let {
		title,
		subtitle,
		icon,
		tone,
		badge,
		closeDisabled = false
	}: {
		title: string;
		subtitle?: string;
		icon?: string;
		tone?: string;
		/** A small pill beside the title. */
		badge?: Snippet;
		/** While something can't be interrupted (buying), the × is greyed and does nothing. */
		closeDisabled?: boolean;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<header class="dialog-header">
	{#if icon}<IconTile {icon} {tone} />{/if}
	<div class="dialog-header__copy">
		<div class="dialog-header__title-row">
			<DialogPrimitive.Title level={2} class="dialog-header__title">{title}</DialogPrimitive.Title>
			{@render badge?.()}
		</div>
		{#if subtitle}<p class="dialog-header__subtitle">{subtitle}</p>{/if}
	</div>
	<DialogPrimitive.Close>
		{#snippet child({ props })}
			<Button {...props} variant="secondary" iconOnly label="Close" disabled={closeDisabled}
				>{@html closeIcon}</Button
			>
		{/snippet}
	</DialogPrimitive.Close>
</header>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.dialog-header {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-base) var(--space-base) var(--space-base) var(--space-medium);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.dialog-header__copy {
		display: grid;
		flex: 1 1 auto;
		min-width: 0;
		gap: 2px;
	}
	.dialog-header__title-row {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		min-width: 0;
	}
	:global(.dialog-header__title) {
		margin: 0;
		overflow-wrap: anywhere;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		font-weight: 600;
		letter-spacing: -0.2px;
		line-height: 1.25;
	}
	.dialog-header__subtitle {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
