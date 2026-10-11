<svelte:options css="injected" />

<script lang="ts">
	import { page, navigating } from '$app/state';
	import { iconMap, activeNavigationHref, type NavGroup } from '../navigation';
	import collapseIcon from '@tabler/icons/outline/layout-sidebar-left-collapse.svg?raw';
	import expandIcon from '@tabler/icons/outline/layout-sidebar-left-expand.svg?raw';
	let {
		groups,
		brand,
		eyebrow,
		logoUrl,
		collapsed = $bindable(false),
		collapsible = true,
		onnavigate
	}: {
		groups: NavGroup[];
		brand: string;
		eyebrow: string;
		logoUrl: string | null;
		collapsed?: boolean;
		collapsible?: boolean;
		onnavigate?: () => void;
	} = $props();
	const activeHref = $derived(
		activeNavigationHref(groups, navigating.to?.url.pathname ?? page.url.pathname)
	);
	const brandHref = $derived(
		groups.flatMap((group) => group.items).find((item) => !item.unavailable)?.href ?? '/'
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<aside
	class={['botanical-nav', { 'botanical-nav--collapsed': collapsed }]}
	aria-label={`${eyebrow} navigation`}
	data-sveltekit-preload-data="false"
	data-sveltekit-preload-code="hover"
>
	<a class="botanical-nav__identity" href={brandHref} onclick={onnavigate} aria-label={brand}>
		<span class="botanical-nav__initial" aria-hidden="true">
			{#if logoUrl}<img src={logoUrl} alt="" />{:else}{brand.charAt(0).toUpperCase()}{/if}
		</span>
		<span class="botanical-nav__business"><strong>{brand}</strong><span>{eyebrow}</span></span>
	</a>
	<nav class="botanical-nav__scroll">
		{#each groups as group, index (group.label ?? index)}
			<section class="botanical-nav__group" aria-label={group.label}>
				{#if group.label}<p class="botanical-nav__heading">{group.label}</p>{/if}
				<ul class="botanical-nav__list">
					{#each group.items as item (item.href)}
						<li>
							{#snippet label()}
								<span class="botanical-nav__icon" aria-hidden="true"
									>{@html iconMap[item.icon] ?? iconMap.dashboard}</span
								>
								<span class="botanical-nav__label">{item.label}</span>
								{#if item.unavailable}<span class="botanical-nav__badge" aria-hidden="true"
										>Soon</span
									>
								{:else if item.count}<span class="botanical-nav__badge" aria-hidden="true"
										>{item.count > 99 ? '99+' : item.count}</span
									>{/if}
							{/snippet}
							{#if item.unavailable}
								<span
									class="botanical-nav__link"
									aria-disabled="true"
									aria-label={`${item.label}, coming soon`}
									title={`${item.label}, coming soon`}>{@render label()}</span
								>
							{:else}
								<a
									class="botanical-nav__link"
									href={item.href}
									onclick={onnavigate}
									aria-current={activeHref === item.href ? 'page' : undefined}
									aria-label={item.count ? `${item.label}, ${item.count} unread` : item.label}
									title={collapsed ? item.label : undefined}>{@render label()}</a
								>
							{/if}
						</li>
					{/each}
				</ul>
			</section>
		{/each}
	</nav>
	{#if collapsible}
		<footer class="botanical-nav__footer">
			<button
				class="botanical-nav__collapse"
				type="button"
				onclick={() => (collapsed = !collapsed)}
				aria-pressed={collapsed}
				aria-label={collapsed ? 'Expand navigation' : 'Collapse navigation'}
				title={collapsed ? 'Expand navigation' : 'Collapse navigation'}
			>
				<span class="botanical-nav__icon" aria-hidden="true"
					>{@html collapsed ? expandIcon : collapseIcon}</span
				>
				<span class="botanical-nav__collapse-label">Collapse sidebar</span>
			</button>
		</footer>
	{/if}
</aside>

<!-- eslint-enable svelte/no-at-html-tags, svelte/no-navigation-without-resolve -->
<style lang="scss">
	.botanical-nav {
		display: flex;
		flex-direction: column;
		min-height: 0;
		height: 100%;
		padding: 1.375rem 0.875rem 0.875rem;
		background: var(--botanical-nav-background);
		color: var(--botanical-nav-text);
		border: 1px solid var(--botanical-nav-border);
		border-radius: 1rem;
		font-family: Inter, 'Segoe UI', Arial, sans-serif;
		scrollbar-width: thin;
		scrollbar-color: #5c7867 transparent;
		&__identity {
			display: flex;
			align-items: flex-start;
			gap: 0.75rem;
			padding: 0 0.5rem 1.375rem;
			margin-bottom: 1.125rem;
			border-bottom: 1px solid #ffffff16;
			color: inherit;
			text-decoration: none;
			flex-shrink: 0;
		}
		&__initial {
			display: grid;
			place-items: center;
			width: 2.5rem;
			height: 2.5rem;
			flex-shrink: 0;
			border-radius: 0.75rem;
			background: linear-gradient(145deg, #e1eac7, #bfcea2);
			border: 1px solid #ebf0d94d;
			box-shadow: 0 3px 8px #09271924;
			color: #294d36;
			font-size: 1.0625rem;
			font-weight: 600;
			overflow: hidden;
			img {
				width: 100%;
				height: 100%;
				object-fit: contain;
			}
		}
		&__business {
			min-width: 0;
			padding-top: 1px;
			strong {
				display: block;
				color: #f5f8ef;
				font-size: 0.9375rem;
				font-weight: 600;
				letter-spacing: -0.2px;
				line-height: 1.4;
				overflow-wrap: anywhere;
			}
			> span {
				display: block;
				margin-top: 0.25rem;
				color: #b8cebd;
				font-size: 0.6875rem;
				line-height: 1.4;
			}
		}
		&__scroll {
			flex: 1;
			min-height: 0;
			overflow-y: auto;
			margin: -3px -3px 0.75rem;
			padding: 3px;
		}
		&__group {
			margin-bottom: 1.1875rem;
		}
		&__heading {
			display: flex;
			align-items: center;
			gap: 0.625rem;
			color: #b2c8b9;
			font-size: 0.6875rem;
			font-weight: 500;
			letter-spacing: 0.1px;
			padding-inline: 0.6875rem;
			margin-bottom: 0.4375rem;
			&::after {
				content: '';
				height: 1px;
				flex: 1;
				background: #ffffff12;
			}
		}
		&__list {
			display: grid;
			gap: 3px;
			list-style: none;
			margin: 0;
			padding: 0;
		}
		&__link {
			display: flex;
			align-items: center;
			min-height: 2.4375rem;
			padding: 0.5rem 0.6875rem;
			gap: 0.6875rem;
			border: 1px solid transparent;
			border-radius: 0.5625rem;
			color: var(--botanical-nav-text);
			text-decoration: none;
			font-size: 0.875rem;
			line-height: 1.35;
			font-weight: 400;
			&:hover {
				background: #ffffff0b;
				border-color: #ffffff0a;
				color: white;
			}
			&[aria-current='page'] {
				color: #214c32;
				background: linear-gradient(110deg, #e6edcf, #d4e4bc);
				border-color: #eef4da;
				box-shadow: 0 2px 5px #0927191a;
				font-weight: 600;
				.botanical-nav__icon {
					color: #245735;
				}
				&::after {
					content: '';
					width: 5px;
					height: 5px;
					flex-shrink: 0;
					border-radius: 50%;
					background: #507949;
					margin-left: auto;
				}
			}
			&[aria-disabled='true'] {
				color: #adbfaf;
				cursor: not-allowed;
				&:hover {
					background: transparent;
					border-color: transparent;
				}
				.botanical-nav__icon {
					color: #9ab49f;
				}
			}
		}
		&__icon {
			display: inline-flex;
			flex-shrink: 0;
			color: #d7e7dc;
			:global(svg) {
				width: 1.125rem;
				height: 1.125rem;
				stroke-width: 2;
			}
		}
		&__label {
			flex: 1;
			overflow-wrap: anywhere;
		}
		&__badge {
			font-size: 0.625rem;
			border: 1px solid #ffffff16;
			background: #ffffff07;
			color: #c4d5c8;
			border-radius: 5px;
			padding: 1px 5px;
			line-height: 1.4;
		}
		&__footer {
			flex-shrink: 0;
			border-top: 1px solid #ffffff16;
			padding-top: 0.625rem;
		}
		&__collapse {
			display: flex;
			align-items: center;
			gap: 0.75rem;
			width: 100%;
			min-height: 2.5rem;
			padding: 0.625rem 0.6875rem;
			color: #c4d5c8;
			background: transparent;
			border: 0;
			border-radius: 0.5625rem;
			font: inherit;
			font-size: 0.75rem;
			cursor: pointer;
			&:hover {
				background: #ffffff0b;
			}
		}
		a:focus-visible,
		button:focus-visible {
			outline: 3px solid #d6e6a4;
			outline-offset: 1px;
		}
		&--collapsed {
			padding-inline: 0.75rem;
			.botanical-nav__business,
			.botanical-nav__heading,
			.botanical-nav__label,
			.botanical-nav__badge,
			.botanical-nav__collapse-label {
				display: none;
			}
			.botanical-nav__identity {
				justify-content: center;
				padding: 0;
				border: 0;
				margin-bottom: 1.25rem;
			}
			.botanical-nav__link,
			.botanical-nav__collapse {
				justify-content: center;
				min-height: 2.75rem;
				padding-inline: 0;
			}
			.botanical-nav__link::after {
				display: none;
			}
			.botanical-nav__group + .botanical-nav__group {
				border-top: 1px solid #ffffff16;
				padding-top: 0.75rem;
			}
		}
	}
	@media (max-width: 767px) {
		.botanical-nav {
			border-radius: 0;
			border: 0;
			&__link {
				min-height: 2.75rem;
			}
		}
	}
	@media (forced-colors: active) {
		.botanical-nav__link[aria-current='page'] {
			outline: 2px solid Highlight;
		}
	}
</style>
