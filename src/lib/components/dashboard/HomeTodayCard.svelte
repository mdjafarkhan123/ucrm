<script lang="ts">
	import DayClockCard from '$lib/components/time-clock/DayClockCard.svelte';

	// Home's one feature card: today's date, the greeting as the page title, a one-line summary of the day,
	// and the day clock at the right for people who time their work.
	let {
		date,
		greeting,
		summary,
		showClock = false
	}: {
		date: string;
		greeting: string;
		summary: string;
		showClock?: boolean;
	} = $props();
</script>

<section class="home-today" aria-labelledby="home-today-title">
	<div class="home-today__greeting">
		<p class="home-today__date">{date}</p>
		<h1 id="home-today-title">{greeting}</h1>
		<p class="home-today__summary">{summary}</p>
	</div>
	{#if showClock}<DayClockCard tone="feature" />{/if}
</section>

<style lang="scss">
	.home-today {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base) var(--space-large);
		padding: var(--space-large) var(--space-larger);
		border-radius: var(--radius-large);
		color: var(--color-feature--text);
		background:
			radial-gradient(
				90% 220% at 85% 0%,
				var(--color-feature--glow),
				var(--color-feature--glow-end)
			),
			linear-gradient(200deg, var(--color-feature--start), var(--color-feature--end));

		&__greeting {
			display: grid;
			min-width: 0;
			gap: var(--space-smaller);
		}
		&__date {
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-overline);
			font-weight: 600;
			letter-spacing: 0.8px;
			text-transform: uppercase;
		}
		h1 {
			color: var(--color-feature--text);
			font-size: var(--typography--fontSize-display);
			font-weight: 700;
			letter-spacing: -0.6px;
			line-height: 1.2;
		}
		&__summary {
			color: var(--color-feature--text--secondary);
			font-size: var(--typography--fontSize-base);
		}
	}
</style>
