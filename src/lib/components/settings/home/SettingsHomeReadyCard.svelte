<script lang="ts">
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import type { ReadyList } from '$lib/settings/home-ready';

	// "Ready for customers" (Pencil: Batch 63, Ready card): the screen's one feature card. How many of the
	// things a customer runs into are set up, one bar segment each, and the first two still to do.
	let {
		ready,
		hrefs
	}: {
		ready: ReadyList;
		/** Where each still-open item goes, by its key. */
		hrefs: Record<string, string>;
	} = $props();

	const left = $derived(ready.items.filter((item) => !item.done));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="home-ready" aria-labelledby="settings-ready-title">
	<p class="home-ready__eyebrow">Ready for customers</p>
	<p class="home-ready__count" id="settings-ready-title">
		{ready.done} of {ready.total}
		<span>set up</span>
	</p>
	<div class="home-ready__bar" role="img" aria-label="{ready.done} of {ready.total} things set up">
		{#each ready.items as item (item.key)}
			<span class:home-ready__segment--done={item.done}></span>
		{/each}
	</div>
	{#if left.length === 0}
		<p class="home-ready__all">
			<span aria-hidden="true">{@html circleCheckIcon}</span>Everything is set up
		</p>
	{:else}
		<ul class="home-ready__list">
			{#each left.slice(0, 2) as item (item.key)}
				<li>
					<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- hrefs are built with resolve() by the page -->
					<a class="home-ready__item" href={hrefs[item.key]}>
						<span class="home-ready__item-icon" aria-hidden="true">{@html circleCheckIcon}</span>
						<span class="home-ready__item-title">{item.title}</span>
						<span class="home-ready__item-arrow" aria-hidden="true">{@html arrowRightIcon}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.home-ready {
		display: flex;
		flex-direction: column;
		gap: 14px;
		padding: var(--space-medium) var(--space-large);
		color: var(--color-feature--text);
		background:
			radial-gradient(
				circle at 100% 0%,
				var(--color-feature--glow),
				var(--color-feature--glow-end) 60%
			),
			linear-gradient(200deg, var(--color-feature--start), var(--color-feature--end));
		border-radius: var(--radius-large);

		&__eyebrow {
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}
		&__count {
			display: flex;
			align-items: baseline;
			gap: var(--space-small);
			font-size: var(--typography--fontSize-stat);
			font-weight: 700;
			letter-spacing: -0.8px;

			span {
				color: var(--color-feature--text--secondary);
				font-size: var(--typography--fontSize-base);
				font-weight: 500;
				letter-spacing: 0;
			}
		}
		&__bar {
			display: flex;
			gap: 3px;

			span {
				flex: 1;
				height: 8px;
				background: var(--color-feature--subtle);
				border-radius: var(--radius-circle);
			}
			.home-ready__segment--done {
				background: var(--color-feature--text);
			}
		}
		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}
		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 10px var(--space-slim);
			color: var(--color-feature--text);
			text-decoration: none;
			background: var(--color-feature--subtle);
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-base);

			&:hover {
				background: var(--color-feature--border);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
		&__item-icon {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border: var(--border-base) solid var(--color-feature--border);
			border-radius: var(--radius-base);
		}
		&__item-title {
			flex: 1;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__item-icon,
		&__item-arrow {
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__item-arrow {
			display: grid;
		}
		&__all {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
	}
</style>
