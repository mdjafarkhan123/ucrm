<svelte:options css="injected" />

<script lang="ts">
	import { navigating, page } from '$app/state';
	import { iconMap, activeNavigationHref, type NavGroup } from './navigation';
	import leafIcon from '@tabler/icons/outline/leaf.svg?raw';
	import collapseIcon from '@tabler/icons/outline/layout-sidebar-left-collapse.svg?raw';
	import expandIcon from '@tabler/icons/outline/layout-sidebar-left-expand.svg?raw';

	let {
		groups,
		brand = 'Contractor CRM',
		eyebrow = 'Workspace',
		logoUrl = null,
		onnavigate,
		collapsible = true,
		collapsed = $bindable(false)
	}: {
		groups: NavGroup[];
		brand?: string;
		eyebrow?: string;
		logoUrl?: string | null;
		onnavigate?: () => void;
		collapsible?: boolean;
		collapsed?: boolean;
	} = $props();

	const allItems = $derived(groups.flatMap((group) => group.items));
	const currentPath = $derived(navigating.to?.url.pathname ?? page.url.pathname);
	const activeHref = $derived(activeNavigationHref(groups, currentPath));
	const isActive = (href: string) => activeHref === href;
	const brandHref = $derived(allItems.find((item) => !item.unavailable)?.href ?? '/');
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<aside
	class="sidebar"
	class:sidebar--collapsed={collapsed}
	aria-label={`${eyebrow} navigation`}
	data-sveltekit-preload-data="false"
	data-sveltekit-preload-code="hover"
>
	<div class="sidebar__brand-row">
		<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- brandHref is one of this variant's own static nav destinations, resolved at render time from approved config, not a literal route id. -->
		<a class="sidebar__brand" href={brandHref}>
			<span class="sidebar__mark" aria-hidden="true"
				>{#if logoUrl}<img class="sidebar__mark-image" src={logoUrl} alt="" />{:else}<span
						class="sidebar__mark-icon">{@html leafIcon}</span
					>{/if}</span
			>
			<span class="sidebar__brand-text"
				><strong>{brand}</strong><span class="sidebar__eyebrow">{eyebrow}</span></span
			>
		</a>
		{#if collapsible}
			<button
				class="sidebar__collapse"
				type="button"
				aria-pressed={collapsed}
				aria-label={collapsed ? 'Expand navigation' : 'Collapse navigation'}
				title={collapsed ? 'Expand navigation' : 'Collapse navigation'}
				onclick={() => (collapsed = !collapsed)}
			>
				<span aria-hidden="true">{@html collapsed ? expandIcon : collapseIcon}</span>
			</button>
		{/if}
	</div>
	<nav>
		{#each groups as group, index (group.label ?? index)}
			<div class="sidebar__group" class:sidebar__group--pinned={group.pinned}>
				{#if group.label}<p class="sidebar__group-label">{group.label}</p>{/if}
				<ul class="sidebar__list">
					{#each group.items as item (item.href)}
						<li>
							{#if item.unavailable}
								<span
									class="sidebar__item sidebar__item--unavailable"
									aria-disabled="true"
									aria-label={`${item.label}, coming soon`}
									title={`${item.label} — coming soon`}
								>
									<span class="sidebar__item-icon" aria-hidden="true"
										>{@html iconMap[item.icon] ?? iconMap.dashboard}</span
									>
									<span class="sidebar__item-label">{item.label}</span>
									<span class="sidebar__soon" aria-hidden="true">Soon</span>
								</span>
							{:else}
								<!-- eslint-disable svelte/no-navigation-without-resolve -- item.href comes from this variant's static approved nav config, not a literal route id. -->
								<a
									class="sidebar__item"
									class:sidebar__item--active={isActive(item.href)}
									style:--sidebar-item-tone={item.tone ? `var(--color-${item.tone})` : undefined}
									style:--sidebar-item-tone-surface={item.tone
										? `var(--color-${item.tone}--surface)`
										: undefined}
									href={item.href}
									onclick={onnavigate}
									aria-current={isActive(item.href) ? 'page' : undefined}
									aria-label={item.count ? `${item.label}, ${item.count} unread` : item.label}
									title={collapsed ? item.label : undefined}
								>
									<span
										class="sidebar__item-icon"
										class:sidebar__item-icon--tile={!!item.tone}
										aria-hidden="true">{@html iconMap[item.icon] ?? iconMap.dashboard}</span
									><span class="sidebar__item-label">{item.label}</span>
									{#if item.count}
										<span class="sidebar__count" aria-hidden="true"
											>{item.count > 99 ? '99+' : item.count}</span
										>
									{/if}
								</a>
								<!-- eslint-enable svelte/no-navigation-without-resolve -->
							{/if}
						</li>
					{/each}
				</ul>
			</div>
		{/each}
	</nav>
</aside>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.sidebar {
		display: flex;
		flex-direction: column;
		gap: 18px;
		width: 248px;
		flex: 0 0 248px;
		height: 100%;
		padding: 18px 14px 16px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		overflow-x: hidden;
		overflow-y: auto;
		transition:
			width var(--timing-base) ease-out,
			flex-basis var(--timing-base) ease-out;

		// The workspace switcher: who you are working for, with the collapse control beside it.
		&__brand-row {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: 10px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);
		}
		&__brand {
			display: flex;
			flex: 1;
			min-width: 0;
			align-items: center;
			gap: var(--space-slim);
			color: var(--color-heading);
			text-decoration: none;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
				border-radius: var(--radius-base);
			}
		}
		&__brand:hover {
			color: var(--color-heading);
		}
		&__brand-text {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
			overflow: hidden;
		}
		&__mark {
			display: grid;
			flex: 0 0 40px;
			place-items: center;
			width: 40px;
			height: 40px;
			overflow: hidden;
			border-radius: 12px;
			color: var(--color-surface);
			background: var(--color-interactive);
		}
		&__mark-image {
			width: 100%;
			height: 100%;
			object-fit: cover;
		}
		&__mark-icon {
			display: block;
			width: 20px;
			height: 20px;
		}
		&__mark-icon :global(svg) {
			width: 20px;
			height: 20px;
		}
		&__brand strong {
			display: block;
			overflow: hidden;
			color: var(--color-heading);
			font-size: 15px;
			font-weight: 700;
			line-height: 1.2;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__eyebrow {
			display: block;
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			line-height: 1.25;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__collapse {
			display: inline-grid;
			flex: 0 0 auto;
			width: 24px;
			height: 24px;
			place-items: center;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-icon);
			background: transparent;
			transition: all var(--timing-base) ease-out;
		}
		&__collapse:hover {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}
		&__collapse:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&__collapse span,
		&__collapse span :global(svg) {
			display: inline-flex;
			width: 18px;
			height: 18px;
		}
		nav {
			display: flex;
			flex: 1;
			min-height: 0;
			flex-direction: column;
			gap: 18px;
			overflow-x: hidden;
			overflow-y: auto;
		}
		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
		}
		// Settings: pinned to the foot of the sidebar behind a rule.
		&__group--pinned {
			margin-top: auto;
			padding-top: 10px;
			border-top: var(--border-base) solid var(--color-border);
		}
		&__group-label {
			margin-bottom: var(--space-smaller);
			padding: 0 var(--space-slim);
			color: var(--color-text--secondary);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 0.8px;
			text-transform: uppercase;
		}
		&__list {
			display: grid;
			gap: var(--space-smallest);
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__item {
			position: relative;
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			min-height: 38px;
			padding: 0 var(--space-slim);
			border-radius: 12px;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			text-decoration: none;
			transition: all var(--timing-base) ease-out;
		}
		&__item-icon {
			display: inline-flex;
			flex: 0 0 18px;
			width: 18px;
			color: var(--sidebar-item-tone, var(--color-icon));
		}
		&__item-icon :global(svg) {
			width: 18px;
			height: 18px;
		}
		// A page with a meaning colour sits on a soft tile of that colour.
		&__item-icon--tile {
			flex-basis: 24px;
			width: 24px;
			height: 24px;
			align-items: center;
			justify-content: center;
			border-radius: var(--radius-tile-small);
			background: var(--sidebar-item-tone-surface);
		}
		// The hover row is grey, so the tile turns white to stay visible.
		&__item:hover &__item-icon--tile {
			background: var(--color-surface);
		}
		&__item-icon--tile :global(svg) {
			width: 14px;
			height: 14px;
		}
		&__item-label {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__item:hover {
			color: var(--color-heading);
			background: var(--color-surface--hover);
		}
		&__item:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&__item--active,
		&__item--active:hover {
			color: var(--color-surface);
			background: var(--color-interactive);
			font-weight: 600;
		}
		&__item--active:hover {
			background: var(--color-interactive--hover);
		}
		&__item--active .sidebar__item-icon,
		&__item--active:hover .sidebar__item-icon {
			color: var(--color-surface);
		}
		// On the green current page the tile turns white and the icon green, like the count pill.
		&__item--active .sidebar__item-icon--tile,
		&__item--active:hover .sidebar__item-icon--tile {
			color: var(--color-interactive);
			background: var(--color-surface);
		}
		&__item--unavailable {
			color: var(--color-disabled);
			cursor: not-allowed;
		}
		&__item--unavailable .sidebar__item-icon {
			color: var(--color-disabled);
		}
		&__soon {
			flex: 0 0 auto;
			margin-left: auto;
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-large);
			color: var(--color-text--secondary);
			background: var(--color-inactive--surface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 600;
			white-space: nowrap;
		}
		&__count {
			flex: 0 0 auto;
			min-width: 20px;
			height: 20px;
			margin-left: auto;
			padding: 0 7px;
			border-radius: 10px;
			color: var(--color-surface);
			background: var(--color-interactive);
			font-size: 11px;
			font-weight: 700;
			line-height: 20px;
			text-align: center;
		}
		// On the green active item the pill would vanish, so it flips to the page colour.
		&__item--active &__count {
			color: var(--color-interactive);
			background: var(--color-surface);
		}
	}

	// Collapsed: a logo tile, an expand button, and one icon per page.
	.sidebar--collapsed {
		width: 76px;
		flex: 0 0 76px;
		align-items: center;
		gap: 14px;

		.sidebar__brand-row {
			flex-direction: column;
			gap: 14px;
			padding: 0;
			border: 0;
			background: transparent;
		}
		.sidebar__brand {
			flex: 0 0 auto;
		}
		.sidebar__collapse {
			width: 48px;
			height: 32px;
			border-radius: 10px;
		}
		.sidebar__brand-text,
		.sidebar__group-label,
		.sidebar__item-label,
		.sidebar__soon {
			display: none;
		}
		nav {
			align-items: center;
			gap: 14px;
			width: 100%;
		}
		.sidebar__group {
			align-items: center;
			gap: 14px;
		}
		.sidebar__group + .sidebar__group::before {
			display: block;
			width: 24px;
			height: var(--border-base);
			margin: 0 auto;
			background: var(--color-border);
			content: '';
		}
		.sidebar__group--pinned {
			padding-top: 0;
			border-top: 0;
		}
		.sidebar__list {
			gap: 4px;
		}
		.sidebar__item {
			justify-content: center;
			width: 48px;
			padding-inline: 0;
		}
		// Collapsed, the unread count becomes a small dot on the icon's corner so it still shows.
		.sidebar__count {
			position: absolute;
			top: 6px;
			right: 11px;
			width: 8px;
			min-width: 0;
			height: 8px;
			padding: 0;
			border: var(--border-base) solid var(--color-surface);
			box-sizing: content-box;
			font-size: 0;
		}
	}

	@media (max-width: 767px) {
		.sidebar {
			display: none;
		}
	}
</style>
