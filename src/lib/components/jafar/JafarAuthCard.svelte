<script lang="ts">
	import type { Snippet } from 'svelte';
	import shieldLockIcon from '@tabler/icons/outline/shield-lock.svg?raw';

	// The centred card behind every Jafar Panel sign-in screen: sign in, joining the team, and resetting a
	// password. Each page supplies its own form or message.
	let {
		eyebrow,
		title,
		intro,
		titleId,
		busy = false,
		children
	}: {
		eyebrow: string;
		title: string;
		intro?: string;
		titleId: string;
		busy?: boolean;
		children?: Snippet;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="jafar-auth">
	<section class="jafar-auth__card" aria-labelledby={titleId} aria-busy={busy}>
		<div class="jafar-auth__eyebrow">
			<span aria-hidden="true">{@html shieldLockIcon}</span>
			{eyebrow}
		</div>
		<h1 id={titleId} class="jafar-auth__title">{title}</h1>
		{#if intro}<p class="jafar-auth__intro">{intro}</p>{/if}
		{@render children?.()}
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.jafar-auth {
		min-height: 100vh;
		display: grid;
		place-items: center;
		padding: var(--space-large);
		background:
			radial-gradient(
				circle at 15% 10%,
				var(--color-interactive--background--subtle--hover),
				transparent 30%
			),
			var(--color-surface--background);
	}

	.jafar-auth__card {
		display: grid;
		gap: var(--space-base);
		width: min(100%, 440px);
		padding: var(--space-largest);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);

		:global(form) {
			display: grid;
			gap: var(--space-base);
		}
	}

	.jafar-auth__eyebrow {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.jafar-auth__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-jumbo);
		line-height: var(--typography--lineHeight-minuscule);
	}

	.jafar-auth__intro {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	@media (max-width: 639px) {
		.jafar-auth {
			align-items: start;
			padding: var(--space-base);
		}

		.jafar-auth__card {
			margin-top: var(--space-largest);
			padding: var(--space-large);
		}

		.jafar-auth__title {
			font-size: 28px;
		}
	}
</style>
