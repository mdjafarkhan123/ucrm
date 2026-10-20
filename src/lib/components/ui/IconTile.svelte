<script lang="ts">
	// A soft rounded square in a meaning colour with its icon on it (design skill `icon-shapes.md`): the
	// kind of record, the part of the app, or the status. Every icon tile in the app is this part.
	let {
		icon,
		tone = 'inactive',
		size = 40,
		class: className = ''
	}: {
		/** A Tabler icon (raw SVG). */
		icon: string;
		/** The colour family: a record (`job`, `invoice`…), a section (`time`, `growth`…) or a status. */
		tone?: string;
		/** 20 is the record header's fact tile; 24, 32 and 40 are the everyday sizes. */
		size?: 20 | 24 | 32 | 40;
		/** Placement only (margins, alignment); the tile's own look stays here. */
		class?: string;
	} = $props();

	// The yellow families are too light for an icon on their own surface, so they use their text colour.
	const ink = $derived(
		tone === 'warning' || tone === 'event'
			? `var(--color-${tone}--onSurface)`
			: `var(--color-${tone})`
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span
	class="icon-tile icon-tile--{size} {className}"
	style:--icon-tile-ink={ink}
	style:--icon-tile-surface={`var(--color-${tone}--surface)`}
	style:--icon-tile-edge={`var(--color-${tone}--surface-edge)`}
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
	}
</style>
