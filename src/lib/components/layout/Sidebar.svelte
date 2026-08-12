<script lang="ts">
	import { page } from '$app/state';
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

	export type NavItem = { label: string; href: string; icon: string };

	let {
		items,
		brand = 'Contractor CRM',
		eyebrow = 'Workspace',
		onnavigate
	}: { items: NavItem[]; brand?: string; eyebrow?: string; onnavigate?: () => void } = $props();

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
		mail: mailIcon
	};

	const activeHref = $derived.by(() => {
		const pathname = page.url.pathname;
		return items
			.filter(
				(item) =>
					pathname === item.href || (item.href !== '/' && pathname.startsWith(`${item.href}/`))
			)
			.sort((left, right) => right.href.length - left.href.length)[0]?.href;
	});
	const isActive = (href: string) => activeHref === href;
	const toPath = (href: string) => href;
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<aside class="sidebar" aria-label={`${eyebrow} navigation`}>
	<a class="sidebar__brand" href={toPath(items[0]?.href ?? '/')}>
		<span class="sidebar__mark" aria-hidden="true"
			><span class="sidebar__mark-icon">{@html iconMap.hammer}</span></span
		>
		<span><span class="sidebar__eyebrow">{eyebrow}</span><strong>{brand}</strong></span>
	</a>
	<nav>
		<ul class="sidebar__list">
			{#each items as item (item.href)}
				<li>
					<a
						class:sidebar__item--active={isActive(item.href)}
						class="sidebar__item"
						href={toPath(item.href)}
						onclick={onnavigate}
						aria-current={isActive(item.href) ? 'page' : undefined}
					>
						<span class="sidebar__item-icon" aria-hidden="true"
							>{@html iconMap[item.icon] ?? iconMap.dashboard}</span
						><span>{item.label}</span>
					</a>
				</li>
			{/each}
		</ul>
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

		&__brand {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 48px;
			margin-bottom: var(--space-large);
			padding: var(--space-small);
			color: var(--color-heading);
			text-decoration: none;
		}
		&__brand:hover {
			color: var(--color-heading);
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
			font-weight: 700;
		}
		&__eyebrow {
			display: block;
			margin-bottom: var(--space-smaller);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: 1;
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
			width: 20px;
			color: var(--color-icon);
		}
		&__item-icon :global(svg) {
			width: 20px;
			height: 20px;
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
	}

	@media (max-width: 767px) {
		.sidebar {
			display: none;
		}
	}
</style>
