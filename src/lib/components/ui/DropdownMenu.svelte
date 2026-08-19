<script lang="ts">
	import { DropdownMenu as DropdownMenuPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import dotsIcon from '@tabler/icons/outline/dots-vertical.svg?raw';

	type MenuItem = {
		label: string;
		icon?: string;
		onSelect: () => void;
		destructive?: boolean;
		disabled?: boolean;
	};

	let {
		items,
		triggerLabel = 'Open menu',
		triggerIcon = dotsIcon,
		triggerClass = 'dropdown-menu__trigger',
		trigger,
		align = 'end',
		disabled = false,
		open = $bindable(false)
	}: {
		items: MenuItem[];
		triggerLabel?: string;
		triggerIcon?: string;
		// Overrides the default 32px icon button — the trigger content and its class travel together, so a
		// custom trigger (an avatar, say) never inherits the icon button's box.
		triggerClass?: string;
		trigger?: Snippet;
		align?: 'start' | 'center' | 'end';
		disabled?: boolean;
		open?: boolean;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<DropdownMenuPrimitive.Root bind:open>
	<DropdownMenuPrimitive.Trigger class={triggerClass} aria-label={triggerLabel} {disabled}>
		{#if trigger}
			{@render trigger()}
		{:else}
			{@html triggerIcon}
		{/if}
	</DropdownMenuPrimitive.Trigger>
	<DropdownMenuPrimitive.Portal>
		<DropdownMenuPrimitive.Content
			class="dropdown-menu__content"
			data-elevation="elevated"
			{align}
			sideOffset={4}
			collisionPadding={8}
		>
			{#each items as item (item.label)}
				<DropdownMenuPrimitive.Item
					class={`dropdown-menu__item ${item.destructive ? 'dropdown-menu__item--destructive' : ''}`}
					disabled={item.disabled}
					onSelect={() => item.onSelect()}
				>
					{#if item.icon}
						<span class="dropdown-menu__item-icon" aria-hidden="true">{@html item.icon}</span>
					{/if}
					<span>{item.label}</span>
				</DropdownMenuPrimitive.Item>
			{/each}
		</DropdownMenuPrimitive.Content>
	</DropdownMenuPrimitive.Portal>
</DropdownMenuPrimitive.Root>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.dropdown-menu__trigger) {
		display: inline-grid;
		width: 32px;
		height: 32px;
		flex: 0 0 auto;
		place-items: center;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-icon--secondary);
		background: transparent;
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover:not(:disabled) {
			color: var(--color-icon);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			color: var(--color-disabled);
			cursor: not-allowed;
		}

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	:global(.dropdown-menu__trigger[data-state='open']) {
		color: var(--color-icon);
		background: var(--color-surface--active);
	}

	:global(.dropdown-menu__content) {
		z-index: var(--elevation-modal);
		width: 200px;
		max-width: calc(100vw - var(--space-large) * 2);
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.dropdown-menu__item) {
		display: flex;
		width: 100%;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border-radius: var(--radius-small);
		outline: none;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		cursor: pointer;
		transition: background-color var(--timing-quick);
	}

	:global(.dropdown-menu__item[data-highlighted]) {
		color: var(--color-heading);
		background: var(--color-surface--hover);
	}

	:global(.dropdown-menu__item[data-disabled]) {
		color: var(--color-disabled);
		cursor: not-allowed;
	}

	:global(.dropdown-menu__item--destructive) {
		color: var(--color-destructive);
	}

	:global(.dropdown-menu__item--destructive[data-highlighted]) {
		color: var(--color-destructive--hover);
		background: var(--color-critical--surface);
	}

	.dropdown-menu__item-icon {
		display: grid;
		width: 16px;
		height: 16px;
		flex: 0 0 auto;
		place-items: center;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
</style>
