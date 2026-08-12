<script lang="ts">
	import { resolve } from '$app/paths';
</script>

<svelte:head>
	<title>Card demo</title>
</svelte:head>

<h1>Cards</h1>
<p class="demo-intro">
	Design follows .agents/skills/design/cards.md. Static cards never hover; interactive cards get a
	hover background and pointer cursor. Card headings never exceed 20px.
</p>

<section class="demo-section">
	<h2>Static cards (summary)</h2>
	<div class="demo-grid">
		<div class="card">
			<h3 class="card__title">Total revenue</h3>
			<p class="card__stat">$48,250</p>
			<p class="card__sub">Last 30 days</p>
		</div>
		<div class="card">
			<h3 class="card__title">Open jobs</h3>
			<p class="card__stat">12</p>
			<p class="card__sub">3 scheduled this week</p>
		</div>
		<div class="card">
			<h3 class="card__title">Pending quotes</h3>
			<p class="card__stat">5</p>
			<p class="card__sub">$9,360 awaiting response</p>
		</div>
		<div class="card">
			<h3 class="card__title">Overdue invoices</h3>
			<p class="card__stat">2</p>
			<p class="card__sub">$1,940 outstanding</p>
		</div>
	</div>
</section>

<section class="demo-section">
	<h2>Static card — detail</h2>
	<div class="demo-grid demo-grid--detail">
		<div class="card">
			<h3 class="card__title">Furnace replacement</h3>
			<p class="card__text">Sarah Mitchell &middot; 42 Maple Street</p>
			<p class="card__text">Scheduled Aug 12, 2026 &middot; Derek Tan</p>
			<p class="card__text">$4,850.00</p>
		</div>
	</div>
</section>

<section class="demo-section">
	<h2>Interactive card</h2>
	<div class="demo-grid">
		<button class="card card--interactive" type="button">
			<span class="card__title">Water heater install</span>
			<span class="card__text">James O'Brien &middot; 8 Pine Court</span>
			<span class="card__text">Pending &middot; Aug 14, 2026</span>
		</button>
		<button class="card card--interactive" type="button">
			<span class="card__title">AC tune-up</span>
			<span class="card__text">Priya Sharma &middot; 17 Cedar Ave</span>
			<span class="card__text">Completed &middot; Aug 5, 2026</span>
		</button>
	</div>
</section>

<a href={resolve('/demo')} class="demo-back">Back to demo</a>

<style lang="scss">
	// =============================================================================
	// CARD — demo of .agents/skills/design/cards.md
	// =============================================================================

	.card {
		display: block;
		box-sizing: border-box;
		width: 100%;
		padding: var(--space-large);
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		box-shadow: var(--shadow-low);
		text-align: left;
	}

	.card--interactive {
		cursor: pointer;
		transition:
			background var(--timing-base) ease,
			box-shadow var(--timing-base) ease;

		&:hover,
		&:focus-visible {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}
	}

	.card__title {
		display: block;
		margin-block-end: var(--space-small);
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-larger);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
		color: var(--color-heading);

		@media (max-width: 640px) {
			font-size: var(--typography--fontSize-large);
		}
	}

	.card__stat {
		margin-block-end: var(--space-smaller);
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
		color: var(--color-heading);
	}

	.card__sub {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.card__text {
		display: block;
		margin-block-end: var(--space-smaller);
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
	}

	// =============================================================================
	// Demo page chrome (not part of the card styles)
	// =============================================================================

	h1 {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-jumbo);
		color: var(--color-heading);
	}

	h2 {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-largest);
		color: var(--color-heading);
	}

	.demo-intro {
		margin-block: var(--space-small) var(--space-largest);
		color: var(--color-text--secondary);
	}

	.demo-section {
		margin-block-end: var(--space-large);
	}

	.demo-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
		gap: var(--space-base);
		margin-block-start: var(--space-small);
	}

	.demo-back {
		display: inline-block;
		margin-block-start: var(--space-large);
	}
</style>
