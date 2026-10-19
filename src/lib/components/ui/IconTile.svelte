<script lang="ts">
	// A soft rounded square in a meaning colour with its icon on it (design skill `icon-shapes.md`): the
	// kind of record, the part of the app, or the status. Used by pop-up headers and page states.
	let {
		icon,
		tone = 'inactive',
		size = 40
	}: {
		/** A Tabler icon (raw SVG). */
		icon: string;
		/** The colour family: a record (`job`, `invoice`…), a section (`time`, `growth`…) or a status. */
		tone?: string;
		size?: 24 | 32 | 40;
	} = $props();

	// The yellow families are too light for an icon on their own surface, so they use their text colour.
	const ink = $derived(
		tone === 'warning' || tone === 'event' ? `var(--color-${tone}--onSurface)` : `var(--color-${tone})`
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<span
	class="icon-tile icon-tile--{size}"
	style:--icon-tile-ink={ink}
	style:--icon-tile-surface={`var(--color-${tone}--surface)`}
	aria-hidden="true">{@html icon}</span
>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.icon-tile {
		display: inline-flex;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		color: var(--icon-tile-ink);
		background: var(--icon-tile-surface);

		:global(svg) {
			display: block;
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
