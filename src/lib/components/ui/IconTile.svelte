<script lang="ts">
	// A soft rounded square in a meaning colour with its icon on it (design skill `icon-shapes.md`): the
	// kind of record, the part of the app, or the status. Every icon tile in the app is this part.
	let {
		icon,
		tone = 'inactive',
		size = 40,
		white = false,
		class: className = ''
	}: {
		/** A Tabler icon (raw SVG). */
		icon: string;
		/** The colour family: a record (`job`, `invoice`…), a section (`time`, `growth`…) or a status. */
		tone?: string;
		/** 20 is the record header's fact tile; 24, 32 and 40 are the everyday sizes; 56 stands in for a
		 *  line's photo in the crew's work list. */
		size?: 20 | 24 | 32 | 40 | 48 | 56;
		/** A white tile, for one that sits on its own colour (a tinted band or header top). */
		white?: boolean;
		/** Placement only (margins, alignment); the tile's own look stays here. */
		class?: string;
	} = $props();

	// The yellow families are too light for an icon on their own surface, so they use their text colour.
	// `feature` is the dark green money card: a see-through white tile with its own edge.
	const ink = $derived(
		tone === 'feature'
			? 'var(--color-feature--text--secondary)'
			: tone === 'warning' || tone === 'event'
				? `var(--color-${tone}--onSurface)`
				: `var(--color-${tone})`
	);
	const surface = $derived(
		tone === 'feature'
			? 'var(--color-feature--subtle)'
			: white
				? 'var(--color-surface)'
				: `var(--color-${tone}--surface)`
	);
	const edge = $derived(
		tone === 'feature' ? 'var(--color-feature--border)' : `var(--color-${tone}--surface-edge)`
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span
	class="icon-tile icon-tile--{size} {className}"
	style:--icon-tile-ink={ink}
	style:--icon-tile-surface={surface}
	style:--icon-tile-edge={edge}
	aria-hidden="true">{@html icon}</span
>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.icon-tile {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		// The hairline edge (the next palette step) keeps the tile from fading into a white card.
		border: var(--border-base) solid var(--icon-tile-edge);
		color: var(--icon-tile-ink);
		background: var(--icon-tile-surface);

		:global(svg) {
			display: block;
		}

		&--20 {
			width: 20px;
			height: 20px;
			border-radius: 5px;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}
		&--24 {
			width: 24px;
			height: 24px;
			border-radius: var(--radius-tile-small);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
		&--32 {
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&--40 {
			width: 40px;
			height: 40px;
			border-radius: var(--radius-tile-large);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
		&--48 {
			width: 48px;
			height: 48px;
			border-radius: var(--radius-tile-large);

			:global(svg) {
				width: 24px;
				height: 24px;
			}
		}
		&--56 {
			width: 56px;
			height: 56px;
			border-radius: var(--radius-tile-large);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
	}
</style>
