<svelte:options css="injected" />

<script lang="ts">
	import { navigating, page } from '$app/state';
	import { iconMap, activeNavigationHref, type NavGroup } from './navigation';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
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
						class="sidebar__mark-icon">{@html hammerIcon}</span
					>{/if}</span
			>
			<span class="sidebar__brand-text"
				><span class="sidebar__eyebrow">{eyebrow}</span><strong>{brand}</strong></span
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
			<div class="sidebar__group">
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
									href={item.href}
									onclick={onnavigate}
									aria-current={isActive(item.href) ? 'page' : undefined}
									aria-label={item.count ? `${item.label}, ${item.count} unread` : item.label}
									title={collapsed ? item.label : undefined}
								>
									<span class="sidebar__item-icon" aria-hidden="true"
										>{@html iconMap[item.icon] ?? iconMap.dashboard}</span
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
		flex: 0 0 248px;
		flex-direction: column;
		width: 248px;
		min-height: 0;
		height: 100%;
		padding: 18px 14px 16px;
		border: 1px solid var(--classic2-sidebar-edge);
		border-radius: 24px;
		background: linear-gradient(155deg, var(--classic2-sidebar-top), var(--classic2-sidebar));
		color: var(--classic2-sidebar-text);
		transition:
			width var(--timing-base),
			flex-basis var(--timing-base);
		&__brand-row {
			display: flex;
			align-items: center;
			gap: 6px;
			min-height: 60px;
			margin-bottom: 18px;
			padding: 10px;
			border: 1px solid var(--classic2-sidebar-line);
			border-radius: 16px;
			background: var(--classic2-sidebar-overlay);
		}
		&__brand {
			display: flex;
			flex: 1;
			min-width: 0;
			align-items: center;
			gap: 10px;
			color: #fff;
			text-decoration: none;
			&:hover {
				color: #fff;
			}
		}
		&__brand-text {
			min-width: 0;
		}
		&__brand strong {
			display: block;
			overflow: hidden;
			font-size: 15px;
			font-weight: 700;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__eyebrow {
			display: block;
			color: var(--classic2-sidebar-muted);
			font-size: 12px;
			line-height: 1.3;
		}
		&__mark {
			display: grid;
			flex: 0 0 40px;
			width: 40px;
			height: 40px;
			place-items: center;
			overflow: hidden;
			border-radius: 12px;
			background: linear-gradient(145deg, var(--classic2-logo-start), var(--classic2-solid-green));
			color: #fff;
		}
		&__mark-image {
			width: 100%;
			height: 100%;
			object-fit: cover;
		}
		&__mark-icon,
		&__mark-icon :global(svg) {
			display: block;
			width: 22px;
			height: 22px;
		}
		&__collapse {
			display: grid;
			flex: 0 0 28px;
			width: 28px;
			height: 28px;
			place-items: center;
			padding: 0;
			border: 0;
			border-radius: 8px;
			background: transparent;
			color: var(--classic2-sidebar-muted);
			cursor: pointer;
			&:hover {
				background: var(--classic2-sidebar-line);
				color: #fff;
			}
		}
		&__collapse span,
		&__collapse :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
		& nav {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-height: 0;
			overflow-y: auto;
			scrollbar-width: thin;
		}
		&__group + &__group {
			margin-top: 18px;
		}
		&__group:last-child {
			margin-top: auto;
			padding-top: 18px;
			border-top: 1px solid var(--classic2-sidebar-line);
		}
		&__group-label {
			margin: 0 0 8px;
			padding-inline: 12px;
			color: var(--classic2-sidebar-group);
			font-size: 11px;
			font-weight: 700;
			letter-spacing: 0.8px;
			text-transform: uppercase;
		}
		&__list {
			display: grid;
			gap: 3px;
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__item {
			display: flex;
			position: relative;
			align-items: center;
			gap: 12px;
			min-height: 38px;
			padding: 0 12px;
			border-radius: 12px;
			color: var(--classic2-sidebar-text);
			font-size: 14px;
			font-weight: 500;
			text-decoration: none;
			&:hover {
				background: var(--classic2-sidebar-line);
				color: #fff;
			}
			&--active,
			&--active:hover {
				background: var(--classic2-sidebar-active);
				color: #fff;
				font-weight: 600;
			}
			&--active .sidebar__item-icon {
				color: #fff;
			}
		}
		&__item-icon {
			display: inline-flex;
			flex: 0 0 18px;
			width: 18px;
			color: var(--classic2-sidebar-muted);
		}
		&__item-icon :global(svg) {
			width: 18px;
			height: 18px;
		}
		&__item-label {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__count {
			flex: 0 0 auto;
			min-width: 20px;
			margin-left: auto;
			padding: 0 4px;
			border-radius: 999px;
			background: var(--classic2-sidebar-active);
			color: #fff;
			font-size: 11px;
			font-weight: 700;
			line-height: 20px;
			text-align: center;
		}
		&__item--active .sidebar__count {
			background: #ffffff33;
		}
		a:focus-visible,
		button:focus-visible {
			outline: 3px solid #fff;
			outline-offset: 2px;
		}
	}
	.sidebar--collapsed {
		width: 76px;
		flex-basis: 76px;
		padding-inline: 8px;
		.sidebar__brand-row {
			flex-direction: column;
			justify-content: center;
			padding: 8px;
		}
		.sidebar__brand {
			flex: 0 0 auto;
		}
		.sidebar__brand-text,
		.sidebar__group-label,
		.sidebar__item-label {
			display: none;
		}
		.sidebar__collapse {
			flex: 0 0 28px;
		}
		.sidebar__item {
			justify-content: center;
			padding-inline: 0;
		}
		.sidebar__count {
			position: absolute;
			top: 1px;
			right: 0;
			min-width: 16px;
			line-height: 16px;
		}
	}
	@media (max-width: 767px) {
		.sidebar {
			display: none;
		}
	}
</style>
