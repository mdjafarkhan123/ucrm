<script lang="ts">
	import { DropdownMenu as DropdownMenuPrimitive } from 'bits-ui';
	import type { Snippet } from 'svelte';
	import dotsIcon from '@tabler/icons/outline/dots.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import Button from './Button.svelte';

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
		// The chosen one in a pick-one menu: bold, with a green check at the end, read out as current.
		current?: boolean;
	};

	type MenuGroup = { heading: string; items: MenuItem[] };

	let {
		items = [],
		groups = [],
		footer = [],
		wide = false,
		triggerLabel,
		triggerIcon = dotsIcon,
		triggerText,
		triggerLeadingIcon,
		triggerChevron = true,
		triggerVariant = 'secondary',
		triggerSize,
		triggerClass,
		trigger,
		contentClass = '',
		align = 'end',
		disabled = false,
		unavailableReason,
		open = $bindable(false)
	}: {
		items?: MenuItem[];
		// Items under a heading each, drawn after `items`. For a menu long enough to need signposts.
		groups?: MenuGroup[];
		// Actions drawn last, below a divider and without a heading: the things to do with the list above.
		footer?: MenuItem[];
		// Room for longer labels than a short action list needs.
		wide?: boolean;
		// Names an icon-only trigger. A text trigger is named by its text unless this says more.
		triggerLabel?: string;
		// The icon of the default icon-only trigger (three dots).
		triggerIcon?: string;
		// Draws the trigger as a text button instead of an icon button: "More" with a chevron, or "Add" with
		// a leading icon (`triggerLeadingIcon`). `triggerChevron={false}` drops the chevron.
		triggerText?: string;
		triggerLeadingIcon?: string;
		triggerChevron?: boolean;
		triggerVariant?: 'primary' | 'secondary' | 'quiet';
		// Defaults: small for the icon-only trigger (it sits inside rows), base for a text trigger.
		triggerSize?: 'small' | 'base' | 'large';
		// A trigger that is not a button (an avatar or a picker field): the class and the `trigger` snippet
		// travel together, so it never inherits the button's box. Leave both out for the shared Button.
		triggerClass?: string;
		trigger?: Snippet;
		// Placement and size of the open list only (a menu that needs its own width); the look stays here.
		contentClass?: string;
		align?: 'start' | 'center' | 'end';
		disabled?: boolean;
		/** Nothing is behind this menu yet: the trigger shows disabled and says why, on hover and to a screen
		 *  reader, instead of sitting there dead. */
		unavailableReason?: string;
		open?: boolean;
	} = $props();

	const customTrigger = $derived(Boolean(trigger || triggerClass));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet triggerBody()}
	{#if triggerText}
		{#if triggerLeadingIcon}{@html triggerLeadingIcon}{/if}
		{triggerText}
		{#if triggerChevron}{@html chevronDownIcon}{/if}
	{:else}
		{@html triggerIcon}
	{/if}
{/snippet}

{#snippet menuItem(item: MenuItem)}
	<DropdownMenuPrimitive.Item
		class={`dropdown-menu__item ${item.destructive ? 'dropdown-menu__item--destructive' : ''} ${item.muted ? 'dropdown-menu__item--muted' : ''} ${item.current ? 'dropdown-menu__item--current' : ''}`}
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
		{#if item.current}
			<span class="dropdown-menu__item-note">, current</span>
			<span class="dropdown-menu__item-icon dropdown-menu__item-check" aria-hidden="true">
				{@html checkIcon}
			</span>
		{/if}
		{#if item.trailingIcon}
			<span class="dropdown-menu__item-icon" aria-hidden="true" title={item.note}>
				{@html item.trailingIcon}
			</span>
		{/if}
	</DropdownMenuPrimitive.Item>
{/snippet}

{#if unavailableReason}
	<span class="dropdown-menu__unavailable" title={unavailableReason}>
		<Button
			variant={triggerVariant}
			size={triggerSize ?? (triggerText ? 'base' : 'small')}
			class={triggerText === 'More' ? 'dropdown-menu__more-button' : ''}
			iconOnly={!triggerText}
			label={triggerLabel ?? (triggerText ? undefined : 'Open menu')}
			disabled
		>
			{@render triggerBody()}
		</Button>
		<span class="dropdown-menu__unavailable-reason">{unavailableReason}</span>
	</span>
{:else}
	<DropdownMenuPrimitive.Root bind:open>
		{#if customTrigger}
			<DropdownMenuPrimitive.Trigger
				class={triggerClass ?? 'dropdown-menu__trigger'}
				aria-label={triggerLabel ?? 'Open menu'}
				{disabled}
			>
				{#if trigger}
					{@render trigger()}
				{:else}
					{@html triggerIcon}
				{/if}
			</DropdownMenuPrimitive.Trigger>
		{:else}
			<DropdownMenuPrimitive.Trigger {disabled}>
				{#snippet child({ props })}
					<Button
						{...props}
						variant={triggerVariant}
						size={triggerSize ?? (triggerText ? 'base' : 'small')}
						class={triggerText === 'More' ? 'dropdown-menu__more-button' : ''}
						iconOnly={!triggerText}
						label={triggerLabel ?? (triggerText ? undefined : 'Open menu')}
						{disabled}
					>
						{@render triggerBody()}
					</Button>
				{/snippet}
			</DropdownMenuPrimitive.Trigger>
		{/if}
		<DropdownMenuPrimitive.Portal>
			<DropdownMenuPrimitive.Content
				class={`dropdown-menu__content ${wide ? 'dropdown-menu__content--wide' : ''} ${contentClass}`}
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
				{#if footer.length > 0}
					<DropdownMenuPrimitive.Group class="dropdown-menu__group">
						{#each footer as item (item.key ?? item.label)}
							{@render menuItem(item)}
						{/each}
					</DropdownMenuPrimitive.Group>
				{/if}
			</DropdownMenuPrimitive.Content>
		</DropdownMenuPrimitive.Portal>
	</DropdownMenuPrimitive.Root>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.button.dropdown-menu__more-button) {
		gap: 6px;
		padding-inline: 14px 10px;
	}
	:global(.button.dropdown-menu__more-button svg) {
		color: var(--color-icon);
	}
	:global(.button.button--secondary.dropdown-menu__more-button:disabled:not([aria-busy='true'])) {
		border-color: var(--color-border--interactive);
		background: var(--color-surface);
	}
	.dropdown-menu__unavailable {
		position: relative;
		display: inline-flex;
	}
	.dropdown-menu__unavailable-reason {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
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

	:global(.dropdown-menu__group + .dropdown-menu__group),
	// The footer's divider also follows plain items, not only another group.
	:global(.dropdown-menu__item + .dropdown-menu__group) {
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

	:global(.dropdown-menu__item--current) .dropdown-menu__item-label {
		color: var(--color-heading);
		font-weight: 600;
	}

	.dropdown-menu__item-check {
		color: var(--color-interactive);
	}

	.dropdown-menu__item-label {
		flex: 1 1 auto;
		min-width: 0;
		overflow-wrap: anywhere;
	}

	/* Read out, never drawn: the trailing icon says the same thing to the eye. */
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
