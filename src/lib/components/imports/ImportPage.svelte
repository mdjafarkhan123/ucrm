<script lang="ts">
	import type { Snippet } from 'svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import ImportStepper from './ImportStepper.svelte';

	// The frame every import wizard shares (design skill `layout.md` → Setup steps): one centred 760 column with
	// the page header (a 40 tile in the import's colour), the step track, then the current step's card.
	let {
		title,
		lede,
		icon,
		tone,
		step,
		children
	}: {
		title: string;
		lede: string;
		/** A Tabler icon (raw SVG) for the header tile. */
		icon: string;
		/** The import's colour family (clients `client`, Price book `inactive`, balances `invoice`). */
		tone: string;
		/** The current step, 1–4. */
		step: number;
		children: Snippet;
	} = $props();
</script>

<div class="import-page">
	<header class="import-page__head">
		<IconTile {icon} {tone} />
		<div class="import-page__copy">
			<h1>{title}</h1>
			<p>{lede}</p>
		</div>
	</header>

	<ImportStepper current={step} />

	{@render children()}
</div>

<style lang="scss">
	.import-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		max-width: 760px;
		margin-inline: auto;
		padding-block: var(--space-large);
		padding-inline: var(--space-base);
		box-sizing: content-box;

		&__head {
			display: flex;
			align-items: center;
			gap: 14px;
		}

		&__copy {
			display: flex;
			flex-direction: column;
			gap: 2px;
			min-width: 0;

			h1 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-largest);
				font-weight: 700;
				letter-spacing: -0.5px;
			}
			p {
				margin: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-base);
				line-height: 1.45;
			}
		}
	}
</style>
