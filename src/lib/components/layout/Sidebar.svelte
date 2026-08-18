<script lang="ts">
	import { navigating, page } from '$app/state';
	import dashboardIcon from '@tabler/icons/outline/layout-dashboard.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import fileInvoiceIcon from '@tabler/icons/outline/file-invoice.svg?raw';
	import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import messagesIcon from '@tabler/icons/outline/messages.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import routeIcon from '@tabler/icons/outline/route.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import trendingUpIcon from '@tabler/icons/outline/trending-up.svg?raw';
	import usersGroupIcon from '@tabler/icons/outline/users-group.svg?raw';
	import chartBarIcon from '@tabler/icons/outline/chart-bar.svg?raw';
	import collapseIcon from '@tabler/icons/outline/layout-sidebar-left-collapse.svg?raw';
	import expandIcon from '@tabler/icons/outline/layout-sidebar-left-expand.svg?raw';

	export type NavItem = { label: string; href: string; icon: string; unavailable?: boolean };
	export type NavGroup = { label?: string; items: NavItem[] };

	let {
		groups,
		brand = 'Contractor CRM',
		eyebrow = 'Workspace',
		onnavigate,
		collapsible = true,
		collapsed = $bindable(false)
	}: {
		groups: NavGroup[];
		brand?: string;
		eyebrow?: string;
		onnavigate?: () => void;
		collapsible?: boolean;
		collapsed?: boolean;
	} = $props();

	const iconMap: Record<string, string> = {
		dashboard: dashboardIcon,
		users: usersIcon,
		inbox: inboxIcon,
		fileInvoice: fileInvoiceIcon,
		tools: toolsIcon,
		calendar: calendarIcon,
		receipt: receiptIcon,
		messages: messagesIcon,
		hammer: hammerIcon,
		package: packageIcon,
		building: buildingIcon,
		alertTriangle: alertTriangleIcon,
		settings: settingsIcon,
		mail: mailIcon,
		route: routeIcon,
		star: starIcon,
		trendingUp: trendingUpIcon,
		usersGroup: usersGroupIcon,
		chartBar: chartBarIcon
	};

	const allItems = $derived(groups.flatMap((group) => group.items));
	const currentPath = $derived(navigating.to?.url.pathname ?? page.url.pathname);
	const activeHref = $derived.by(() => {
		const pathname = currentPath;
		return allItems
			.filter(
				(item) =>
					!item.unavailable &&
					(pathname === item.href || (item.href !== '/' && pathname.startsWith(`${item.href}/`)))
			)
			.sort((left, right) => right.href.length - left.href.length)[0]?.href;
	});
	const isActive = (href: string) => activeHref === href;
	const brandHref = $derived(allItems.find((item) => !item.unavailable)?.href ?? '/');
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<aside
	class="sidebar"
	class:sidebar--collapsed={collapsed}
	aria-label={`${eyebrow} navigation`}
	data-sveltekit-preload-data="false"
	data-sveltekit-preload-code="eager"
>
	<div class="sidebar__brand-row">
		<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- brandHref is one of this variant's own static nav destinations, resolved at render time from approved config, not a literal route id. -->
		<a class="sidebar__brand" href={brandHref}>
			<span class="sidebar__mark" aria-hidden="true"
				><span class="sidebar__mark-icon">{@html hammerIcon}</span></span
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
									aria-label={item.label}
									title={collapsed ? item.label : undefined}
								>
									<span class="sidebar__item-icon" aria-hidden="true"
										>{@html iconMap[item.icon] ?? iconMap.dashboard}</span
									><span class="sidebar__item-label">{item.label}</span>
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
		position: sticky;
		top: var(--space-large);
		display: flex;
		flex-direction: column;
		width: 256px;
		flex: 0 0 256px;
		height: 95vh;
		padding: var(--space-base) var(--space-slim);
		border-right: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		overflow: hidden;
		transition:
			width var(--timing-base) ease-out,
			flex-basis var(--timing-base) ease-out;

		&__brand-row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-bottom: var(--space-large);
		}
		&__brand {
			display: flex;
			flex: 1;
			min-width: 0;
			align-items: center;
			gap: var(--space-small);
			min-height: 48px;
			padding: var(--space-small);
			color: var(--color-heading);
			text-decoration: none;
		}
		&__brand:hover {
			color: var(--color-heading);
		}
		&__brand-text {
			min-width: 0;
			overflow: hidden;
		}
		&__mark {
			display: grid;
			flex: 0 0 32px;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			color: var(--color-surface);
			background: var(--color-brand);
			font-size: var(--typography--fontSize-large);
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
			font-weight: 700;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__eyebrow {
			display: block;
			margin-bottom: var(--space-smaller);
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: 1;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
		&__collapse {
			display: inline-grid;
			flex: 0 0 auto;
			width: 28px;
			height: 28px;
			place-items: center;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-small);
			color: var(--color-icon);
			background: var(--color-surface);
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
			width: 16px;
			height: 16px;
		}
		nav {
			overflow-y: auto;
		}
		&__group + &__group {
			margin-top: var(--space-base);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}
		&__group-label {
			margin-bottom: var(--space-small);
			padding: 0 var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: var(--typography--letterSpacing-loose);
			text-transform: uppercase;
		}
		&__list {
			display: grid;
			gap: var(--space-small);
			padding: 0;
			list-style: none;
		}
		&__item {
			position: relative;
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			min-height: 40px;
			padding: var(--space-small);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			text-decoration: none;
			transition: all var(--timing-base) ease-out;
		}
		&__item-icon {
			display: inline-flex;
			flex: 0 0 20px;
			width: 20px;
			color: var(--color-icon);
		}
		&__item-icon :global(svg) {
			width: 20px;
			height: 20px;
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
		&__item--active {
			color: var(--color-interactive);
			background: var(--color-surface--active);
		}
		&__item--active::before {
			position: absolute;
			left: 0;
			width: 3px;
			height: 24px;
			border-radius: 0 var(--radius-small) var(--radius-small) 0;
			background: var(--color-brand);
			content: '';
		}
		&__item--active .sidebar__item-icon {
			color: var(--color-interactive);
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
	}

	.sidebar--collapsed {
		width: 76px;
		flex: 0 0 76px;

		.sidebar__brand-text,
		.sidebar__group-label,
		.sidebar__item-label,
		.sidebar__soon {
			display: none;
		}
		.sidebar__brand {
			flex: 0 0 auto;
			padding: var(--space-small) 0;
		}
		.sidebar__brand-row {
			justify-content: center;
		}
		.sidebar__item {
			justify-content: center;
			padding-inline: 0;
		}
	}

	@media (max-width: 767px) {
		.sidebar {
			display: none;
		}
	}
</style>
