<script lang="ts">
	import { DropdownMenu as DropdownMenuPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import dotsIcon from '@tabler/icons/outline/dots-vertical.svg?raw';

	type MenuItem = {
		label: string;
		// Needed only where two items in one menu can carry the same label.
		key?: string;
		icon?: string;
		onSelect: () => void;
		destructive?: boolean;
		disabled?: boolean;
		// Still selectable, but drawn quietly: a choice that will answer with an explanation rather than
		// act. `note` says so to a screen reader, and names what `trailingIcon` means to everyone else.
		muted?: boolean;
		trailingIcon?: string;
		note?: string;
	};

	type MenuGroup = { heading: string; items: MenuItem[] };

	let {
		items = [],
		groups = [],
		wide = false,
		triggerLabel = 'Open menu',
		triggerIcon = dotsIcon,
		triggerClass = 'dropdown-menu__trigger',
		trigger,
		align = 'end',
		disabled = false,
		open = $bindable(false)
	}: {
		items?: MenuItem[];
		// Items under a heading each, drawn after `items`. For a menu long enough to need signposts.
		groups?: MenuGroup[];
		// Room for longer labels than a short action list needs.
		wide?: boolean;
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
{#snippet menuItem(item: MenuItem)}
	<DropdownMenuPrimitive.Item
		class={`dropdown-menu__item ${item.destructive ? 'dropdown-menu__item--destructive' : ''} ${item.muted ? 'dropdown-menu__item--muted' : ''}`}
		disabled={item.disabled}
		onSelect={() => item.onSelect()}
	>
		{#if item.icon}
			<span class="dropdown-menu__item-icon" aria-hidden="true">{@html item.icon}</span>
		{/if}
		<span class="dropdown-menu__item-label">{item.label}</span>
		{#if item.note}
			<span class="dropdown-menu__item-note">, {item.note}</span>
		{/if}
		{#if item.trailingIcon}
			<span class="dropdown-menu__item-icon" aria-hidden="true" title={item.note}>
				{@html item.trailingIcon}
			</span>
		{/if}
	</DropdownMenuPrimitive.Item>
{/snippet}

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
			class={`dropdown-menu__content ${wide ? 'dropdown-menu__content--wide' : ''}`}
			data-elevation="elevated"
			{align}
			sideOffset={4}
			collisionPadding={8}
		>
			{#each items as item (item.key ?? item.label)}
				{@render menuItem(item)}
			{/each}
			{#each groups as group (group.heading)}
				<DropdownMenuPrimitive.Group class="dropdown-menu__group">
					<DropdownMenuPrimitive.GroupHeading class="dropdown-menu__heading">
						{group.heading}
					</DropdownMenuPrimitive.GroupHeading>
					{#each group.items as item (item.key ?? item.label)}
						{@render menuItem(item)}
					{/each}
				</DropdownMenuPrimitive.Group>
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
		// A long menu scrolls inside the space the screen has left, rather than running off it.
		max-height: var(--bits-dropdown-menu-content-available-height);
		overflow-y: auto;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}

	:global(.dropdown-menu__content--wide) {
		width: 260px;
	}

	:global(.dropdown-menu__group + .dropdown-menu__group) {
		margin-top: var(--space-small);
		padding-top: var(--space-small);
		border-top: var(--border-base) solid var(--color-border);
	}

	:global(.dropdown-menu__heading) {
		padding: var(--space-smaller) var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
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

	:global(.dropdown-menu__item--muted),
	:global(.dropdown-menu__item--muted[data-highlighted]) {
		color: var(--color-text--secondary);
	}

	:global(.dropdown-menu__item--destructive) {
		color: var(--color-destructive);
	}

	:global(.dropdown-menu__item--destructive[data-highlighted]) {
		color: var(--color-destructive--hover);
		background: var(--color-critical--surface);
	}

	.dropdown-menu__item-label {
		flex: 1 1 auto;
		min-width: 0;
		overflow-wrap: anywhere;
	}

	// Read out, never drawn: the trailing icon says the same thing to the eye.
	.dropdown-menu__item-note {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
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
