<svelte:options css="injected" />

<script lang="ts">
	import Header from './BotanicalHeader.svelte';
	import { Dialog } from 'bits-ui';
	import { page } from '$app/state';
	import BotanicalSidebar from './BotanicalSidebar.svelte';
	import type { ShellFrameProps } from './types';
	import closeIcon from '@tabler/icons/outline/x.svg?raw';
	let {
		notice,
		children,
		header,
		groups,
		brand,
		eyebrow,
		logoUrl,
		mobileOpen = $bindable(false),
		sidebarCollapsed = $bindable(false)
	}: ShellFrameProps = $props();
	const currentItem = $derived(
		groups
			.flatMap((group) => group.items)
			.filter(
				(item) =>
					!item.unavailable &&
					(page.url.pathname === item.href || page.url.pathname.startsWith(`${item.href}/`))
			)
			.sort((a, b) => b.href.length - a.href.length)[0]
	);
</script>

<div
	class={['botanical-shell', { 'botanical-shell--collapsed': sidebarCollapsed }]}
	data-presentation="botanical"
	style:--shell-nav-width={sidebarCollapsed ? '5.875rem' : '17.5rem'}
>
	<div class="botanical-shell__sidebar">
		<BotanicalSidebar {groups} {brand} {eyebrow} {logoUrl} bind:collapsed={sidebarCollapsed} />
	</div>
	<div class="botanical-shell__body">
		{#snippet identity()}<div class="botanical-shell__identity">
				<span>Workspace</span><strong>{currentItem?.label ?? 'Workspace'}</strong>
			</div>{/snippet}
		{@render header(Header, identity)}
		{@render notice?.()}
		<div class="botanical-shell__main scroll-y-auto">{@render children()}</div>
	</div>
	<Dialog.Root bind:open={mobileOpen}>
		<Dialog.Portal>
			<Dialog.Overlay class="botanical-drawer__overlay" />
			<Dialog.Content class="botanical-drawer" aria-describedby={undefined}>
				<div class="botanical-drawer__top">
					<Dialog.Title class="botanical-drawer__title">Navigation</Dialog.Title>
					<!-- eslint-disable svelte/no-at-html-tags -- Static Tabler SVG from the installed package. -->
					<Dialog.Close class="botanical-drawer__close" aria-label="Close navigation"
						><span aria-hidden="true">{@html closeIcon}</span></Dialog.Close
					>
					<!-- eslint-enable svelte/no-at-html-tags -->
				</div>
				<BotanicalSidebar
					{groups}
					{brand}
					{eyebrow}
					{logoUrl}
					collapsible={false}
					onnavigate={() => (mobileOpen = false)}
				/>
			</Dialog.Content>
		</Dialog.Portal>
	</Dialog.Root>
</div>

<style lang="scss">
	.botanical-shell {
		--botanical-canvas: #f5f4ef;
		--botanical-header: #fffefb;
		--botanical-ink: #243d34;
		--botanical-border: #e2e6da;
		--botanical-nav-background: linear-gradient(155deg, #204b3c 0%, #183e33 45%, #143429 100%);
		--botanical-nav-text: #d4e1d7;
		--botanical-nav-border: #254e40;
		--shell-edge: 12px;
		--shell-content-left: calc(var(--shell-nav-width) + 16px);
		--shell-content-right: 16px;
		display: flex;
		height: 100dvh;
		overflow: clip;
		background: var(--botanical-canvas);
		&__sidebar {
			width: var(--shell-nav-width);
			flex: 0 0 var(--shell-nav-width);
			padding: 12px 0 12px 12px;
		}
		&__body {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-width: 0;
			min-height: 0;
			overflow: clip;
			padding: 12px 16px;
		}
		&__main {
			flex: 1;
			min-height: 0;
			padding-top: 30px;
		}
		&__identity {
			display: flex;
			flex-direction: column;
			min-width: 7.5rem;
			font-family: Inter, 'Segoe UI', Arial, sans-serif;
			span {
				font-size: 0.6875rem;
				letter-spacing: 0.6px;
				color: #667260;
			}
			strong {
				color: var(--botanical-ink);
				font-size: 1.25rem;
				font-weight: 600;
				letter-spacing: -0.5px;
				line-height: 1.35;
				overflow-wrap: anywhere;
			}
		}
	}
	:global(.botanical-drawer__overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: #10281f88;
	}
	:global(.botanical-drawer) {
		--botanical-nav-background: linear-gradient(155deg, #204b3c 0%, #183e33 45%, #143429 100%);
		--botanical-nav-text: #d4e1d7;
		--botanical-nav-border: #254e40;
		position: fixed;
		z-index: var(--elevation-modal);
		inset: 0 auto 0 0;
		width: min(340px, calc(100% - 42px));
		height: 100dvh;
		overflow-y: auto;
		background: #183e33;
		color: #eaf0e8;
		border-radius: 0 16px 16px 0;
		outline: none;
	}
	:global(.botanical-drawer__top) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 12px 20px;
		border-bottom: 1px solid #ffffff16;
	}
	:global(.botanical-drawer__title) {
		font-size: 0.8125rem;
		color: #d4e1d7;
	}
	:global(.botanical-drawer__close) {
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		border: 0;
		border-radius: 8px;
		background: transparent;
		color: inherit;
		cursor: pointer;
		&:hover {
			background: #345544;
		}
		&:focus-visible {
			outline: 3px solid #d6e6a4;
		}
		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}
	@media (max-width: 767px) {
		.botanical-shell {
			--shell-content-left: 18px;
			--shell-content-right: 18px;
			&__sidebar {
				display: none;
			}
			&__body {
				padding: 0;
			}
			&__main {
				padding: 24px 18px;
			}
			&__identity {
				flex: 1;
				min-width: 0;
				strong {
					font-size: 1.125rem;
				}
			}
		}
	}
</style>
