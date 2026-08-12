<script lang="ts">
	import { onMount } from 'svelte';
	import type { Snippet } from 'svelte';
	import moonIcon from '@tabler/icons/outline/moon.svg?raw';
	import sunIcon from '@tabler/icons/outline/sun.svg?raw';
	import menuIcon from '@tabler/icons/outline/menu-2.svg?raw';

	let {
		eyebrow = 'Workspace',
		title = 'Dashboard',
		onmenutoggle,
		children
	}: { eyebrow?: string; title?: string; onmenutoggle?: () => void; children?: Snippet } = $props();

	let isDark = $state(false);

	onMount(() => {
		const savedTheme = localStorage.getItem('ucrm-theme');
		isDark =
			savedTheme === 'dark' ||
			(savedTheme === null && matchMedia('(prefers-color-scheme: dark)').matches);
		applyTheme(isDark);
	});

	function applyTheme(dark: boolean) {
		document.documentElement.toggleAttribute('data-theme', dark);
		if (dark) document.documentElement.dataset.theme = 'dark';
	}

	function toggleTheme() {
		isDark = !isDark;
		localStorage.setItem('ucrm-theme', isDark ? 'dark' : 'light');
		applyTheme(isDark);
	}
</script>

<header class="topbar">
	<button class="topbar__menu" type="button" aria-label="Open navigation" onclick={onmenutoggle}>
		<span aria-hidden="true">{@html menuIcon}</span>
	</button>
	<div>
		<p class="topbar__eyebrow">{eyebrow}</p>
		<h1>{title}</h1>
	</div>
	<button
		class="topbar__theme"
		type="button"
		aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
		aria-pressed={isDark}
		title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
		onclick={toggleTheme}
	>
		<span aria-hidden="true">{@html isDark ? sunIcon : moonIcon}</span>
	</button>
	{#if children}<div class="topbar__actions">{@render children()}</div>{/if}
</header>

<style lang="scss">
	.topbar {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		min-height: 72px;
		padding: var(--space-base) var(--space-largest);
		border-bottom: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.topbar h1 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		line-height: var(--typography--lineHeight-tight);
	}
	.topbar__eyebrow {
		margin-bottom: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.topbar__actions {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.topbar__theme {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 40px;
		height: 40px;
		padding: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-icon);
		background: var(--color-surface);
		margin-left: auto;
		transition: all var(--timing-base) ease-out;
	}
	.topbar__theme:hover {
		border-color: var(--color-border--interactive);
		color: var(--color-interactive--subtle--hover);
		background: var(--color-surface--hover);
	}
	.topbar__theme:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.topbar__theme span,
	.topbar__theme span :global(svg) {
		display: inline-flex;
		width: 20px;
		height: 20px;
	}
	.topbar__menu {
		display: none;
		padding: var(--space-small);
		border: 0;
		border-radius: var(--radius-small);
		color: var(--color-icon);
		background: transparent;
		font-size: var(--typography--fontSize-largest);
	}
	.topbar__menu span,
	.topbar__menu span :global(svg) {
		display: inline-flex;
		width: 20px;
		height: 20px;
	}
	.topbar__menu:hover {
		background: var(--color-surface--hover);
	}
	.topbar__menu:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	@media (max-width: 767px) {
		.topbar {
			padding-inline: var(--space-base);
		}
		.topbar__menu {
			display: inline-grid;
			place-items: center;
		}
	}
</style>
