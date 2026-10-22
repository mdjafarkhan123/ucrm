<script lang="ts">
	import { countryFlag } from '$lib/settings/country-names';

	// A country's flag in a round frame: 32 in the paperwork list, 40 beside an opened set's title.
	let { code, size = 32 }: { code: string; size?: 32 | 40 } = $props();
</script>

<span class="paperwork-flag" style:--flag-size={`${size}px`} aria-hidden="true"
	>{countryFlag(code)}</span
>

<style lang="scss">
	.paperwork-flag {
		display: inline-grid;
		flex: none;
		place-items: center;
		width: var(--flag-size);
		height: var(--flag-size);
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-circle);
		background: var(--color-surface--background--subtle);
		// The emoji flag is drawn larger than the circle so the circle crops it like a round flag.
		font-size: calc(var(--flag-size) * 1.3);
		line-height: 1;
	}
</style>
