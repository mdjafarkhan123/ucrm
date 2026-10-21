<script lang="ts">
	import type { Snippet } from 'svelte';
	import leafIcon from '@tabler/icons/outline/leaf.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import IconTile from '$lib/components/ui/IconTile.svelte';

	// The split screen behind every Jafar Panel sign-in screen (`layout.md` → Sign-in screens, board `Y0A1Z`
	// B): the deep-green Uplift panel on the left, the same on every screen, and the page's own form or
	// message on the right with no card around it. `eyebrow` is the panel's pill.
	let {
		eyebrow,
		title,
		intro,
		titleId,
		busy = false,
		status,
		children
	}: {
		eyebrow: string;
		title: string;
		intro?: string;
		titleId: string;
		busy?: boolean;
		/** A message screen's 48 tile above the title: done (green) or expired (yellow). */
		status?: { icon: string; tone: 'success' | 'warning' };
		children?: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="jafar-auth">
	<aside class="jafar-auth__brand">
		<div class="jafar-auth__mark">
			<span class="jafar-auth__mark-tile" aria-hidden="true">{@html leafIcon}</span>
			Uplift
		</div>
		<div class="jafar-auth__brand-copy">
			<span class="jafar-auth__pill">
				<span aria-hidden="true">{@html lockIcon}</span>
				{eyebrow}
			</span>
			<p class="jafar-auth__brand-name">The control room</p>
			<p class="jafar-auth__brand-line">
				Private workspace for Uplift's business and the platform.
			</p>
		</div>
		<span aria-hidden="true"></span>
	</aside>
	<section class="jafar-auth__side" aria-labelledby={titleId} aria-busy={busy}>
		<div class="jafar-auth__column">
			{#if status}
				<IconTile icon={status.icon} tone={status.tone} size={48} />
			{/if}
			<div class="jafar-auth__heading">
				<h1 id={titleId} class="jafar-auth__title">{title}</h1>
				{#if intro}<p class="jafar-auth__intro">{intro}</p>{/if}
			</div>
			{@render children?.()}
		</div>
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.jafar-auth {
		display: grid;
		min-height: 100vh;
		box-sizing: border-box;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-slim);
		padding: var(--space-slim);
		background: var(--color-surface);
	}

	.jafar-auth__brand {
		display: flex;
		flex-direction: column;
		justify-content: space-between;
		padding: 56px;
		border-radius: var(--space-medium);
		color: var(--color-feature--text);
		background:
			radial-gradient(
				90% 220% at 85% 0%,
				var(--color-feature--glow),
				var(--color-feature--glow-end)
			),
			linear-gradient(200deg, var(--color-feature--start), var(--color-feature--end));
	}

	.jafar-auth__mark {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
	}

	.jafar-auth__mark-tile {
		display: grid;
		width: 40px;
		height: 40px;
		box-sizing: border-box;
		place-items: center;
		border: var(--border-base) solid var(--color-feature--border);
		border-radius: var(--radius-tile-large);
		background: var(--color-feature--subtle);

		:global(svg) {
			width: 20px;
			height: 20px;
		}
	}

	.jafar-auth__brand-copy {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
	}

	.jafar-auth__pill {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 6px var(--space-slim);
		border: var(--border-base) solid var(--color-feature--border);
		border-radius: var(--radius-circle);
		background: var(--color-feature--subtle);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: 0.6px;
		text-transform: uppercase;

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}

	.jafar-auth__brand-name {
		margin: 0;
		font-size: var(--typography--fontSize-extravagant);
		font-weight: 700;
		letter-spacing: -1.2px;
		line-height: 1.05;
	}

	.jafar-auth__brand-line {
		max-width: 420px;
		margin: 0;
		color: var(--color-feature--text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: 1.5;
	}

	.jafar-auth__side {
		display: grid;
		place-items: center;
		padding: var(--space-largest) var(--space-large);
	}

	.jafar-auth__column {
		display: flex;
		width: min(100%, 400px);
		flex-direction: column;
		gap: var(--space-medium);

		:global(form) {
			display: grid;
			gap: var(--space-base);
		}

		:global(.input__control),
		:global(input:not([type='checkbox']):not([type='radio'])) {
			min-height: 44px;
		}
	}

	.jafar-auth__heading {
		display: grid;
		gap: var(--space-small);
	}

	.jafar-auth__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-display);
		font-weight: 700;
		letter-spacing: -0.6px;
		line-height: 1.2;
	}

	.jafar-auth__intro {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: 1.5;
	}

	// A sign-in error: the critical box above the button. Each page renders it with this class.
	:global(.jafar-auth__error) {
		display: flex;
		align-items: flex-start;
		gap: 10px;
		margin: 0;
		padding: 10px var(--space-slim);
		border: var(--border-base) solid var(--color-critical--surface-edge);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
		font-size: var(--typography--fontSize-label);
		font-weight: 500;
		line-height: 1.4;
	}

	:global(.jafar-auth__error svg) {
		flex: 0 0 auto;
		width: 16px;
		height: 16px;
		margin-top: 1px;
		color: var(--color-critical);
	}
</style>
