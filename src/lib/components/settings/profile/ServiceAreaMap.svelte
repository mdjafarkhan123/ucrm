<script lang="ts">
	import homeIcon from '@tabler/icons/outline/home.svg?raw';
	import arrowsHorizontalIcon from '@tabler/icons/outline/arrows-horizontal.svg?raw';

	// The service area drawn as a plain map panel (Pencil: "Where you work"): pale roads, a ring for how far
	// the business travels, and the base in the middle. It is a picture of the setting, not a live map.
	let {
		miles,
		place
	}: {
		/** How far the business travels, or null before it has been set. */
		miles: number | null;
		/** The city and region the base sits in. */
		place: string;
	} = $props();

	// The ring grows with the distance but flattens out, so 5 and 500 miles both fit the panel.
	const ring = $derived(
		miles && miles > 0 ? Math.round(Math.max(56, (200 * miles) / (miles + 10))) : 0
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="service-map" role="img" aria-label={miles ? `${miles} miles around ${place}` : place}>
	<span class="service-map__road service-map__road--across"></span>
	<span class="service-map__road service-map__road--down"></span>
	<span class="service-map__road service-map__road--slant"></span>
	{#if ring}
		<span class="service-map__ring" style:width="{ring}px" style:height="{ring}px"></span>
		<span class="service-map__distance">
			<span aria-hidden="true">{@html arrowsHorizontalIcon}</span>{miles} mi
		</span>
	{/if}
	<span class="service-map__inner"></span>
	<span class="service-map__pin" aria-hidden="true">{@html homeIcon}</span>
	{#if place}<span class="service-map__place">{place}</span>{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.service-map {
		position: relative;
		display: grid;
		place-items: center;
		min-height: 220px;
		overflow: hidden;
		background: var(--color-surface--background--subtle);

		&__road {
			position: absolute;
			background: var(--color-surface);

			&--across {
				inset: 38% 0 auto;
				height: var(--space-small);
			}
			&--down {
				inset: 0 auto 0 66%;
				width: var(--space-small);
			}
			&--slant {
				inset: 62% -10% auto;
				height: var(--space-slim);
				transform: rotate(-12deg);
			}
		}
		&__ring,
		&__inner,
		&__pin {
			position: relative;
			grid-area: 1 / 1;
			border-radius: var(--radius-circle);
		}
		&__ring {
			background: var(--color-client--surface);
			border: 1.5px solid var(--color-client);
		}
		&__inner {
			width: 56px;
			height: 56px;
			background: var(--color-client--surface-edge);
		}
		&__pin {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			background: var(--color-client);
			border: 2px solid var(--color-surface);
			color: var(--color-surface);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__distance,
		&__place {
			position: absolute;
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: var(--space-smaller) var(--space-small);
			background: var(--color-surface);
			border-radius: var(--radius-circle);
			font-size: var(--typography--fontSize-smaller);
		}
		&__distance {
			top: var(--space-large);
			left: calc(50% + 24px);
			color: var(--color-heading);
			font-weight: 600;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&__place {
			bottom: var(--space-large);
			left: var(--space-large);
			color: var(--color-text--secondary);
			font-weight: 500;
		}
	}
</style>
