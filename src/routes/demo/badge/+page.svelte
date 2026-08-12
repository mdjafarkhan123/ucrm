<script lang="ts">
	import { resolve } from '$app/paths';
</script>

<svelte:head>
	<title>Status & badge demo</title>
</svelte:head>

<h1>Status &amp; badges</h1>
<p class="demo-intro">
	Design follows .agents/skills/design/badges.md and status-indicators.md. No borders, no pill
	radius; only the 5 statuses. Dots are always paired with text.
</p>

<section class="demo-section">
	<h2>StatusLabel (dot + label pill)</h2>
	<div class="demo-row">
		<div
			class="status-label"
			role="status"
			style="--label-background: var(--color-success--surface); --label-text: var(--color-success--onSurface); --dot: var(--color-success);"
		>
			<span class="status-label__dot"></span>
			<span class="status-label__text">Paid</span>
		</div>
		<div
			class="status-label"
			role="status"
			style="--label-background: var(--color-warning--surface); --label-text: var(--color-warning--onSurface); --dot: var(--color-warning);"
		>
			<span class="status-label__dot"></span>
			<span class="status-label__text">Due Soon</span>
		</div>
		<div
			class="status-label"
			role="status"
			style="--label-background: var(--color-critical--surface); --label-text: var(--color-critical--onSurface); --dot: var(--color-critical);"
		>
			<span class="status-label__dot"></span>
			<span class="status-label__text">Overdue</span>
		</div>
		<div
			class="status-label"
			role="status"
			style="--label-background: var(--color-inactive--surface); --label-text: var(--color-inactive--onSurface); --dot: var(--color-inactive);"
		>
			<span class="status-label__dot"></span>
			<span class="status-label__text">Closed</span>
		</div>
		<div
			class="status-label"
			role="status"
			style="--label-background: var(--color-informative--surface); --label-text: var(--color-informative--onSurface); --dot: var(--color-informative);"
		>
			<span class="status-label__dot"></span>
			<span class="status-label__text">Scheduled</span>
		</div>
	</div>

	<h3>End alignment (dot follows text)</h3>
	<div class="demo-row demo-row--end">
		<div
			class="status-label status-label--end"
			role="status"
			style="--label-background: var(--color-success--surface); --label-text: var(--color-success--onSurface); --dot: var(--color-success);"
		>
			<span class="status-label__dot"></span>
			<span class="status-label__text">Paid</span>
		</div>
		<div
			class="status-label status-label--end"
			role="status"
			style="--label-background: var(--color-critical--surface); --label-text: var(--color-critical--onSurface); --dot: var(--color-critical);"
		>
			<span class="status-label__dot"></span>
			<span class="status-label__text">Cancelled</span>
		</div>
	</div>
</section>

<section class="demo-section">
	<h2>InlineLabel (generic badges)</h2>
	<div class="demo-row">
		<span class="inline-label">Active</span>
		<span class="inline-label inline-label--red">↓ 15</span>
		<span class="inline-label inline-label--orange">Sales</span>
		<span class="inline-label inline-label--green">99+</span>
		<span class="inline-label inline-label--blue">New</span>
		<span class="inline-label inline-label--navy">Task</span>
		<span class="inline-label inline-label--yellow">Hold</span>
		<span class="inline-label inline-label--lime">Lime</span>
		<span class="inline-label inline-label--purple">Invoice</span>
		<span class="inline-label inline-label--pink">Quote</span>
		<span class="inline-label inline-label--teal">Teal</span>
		<span class="inline-label inline-label--job">Job</span>
		<span class="inline-label inline-label--blue-dark">Dark</span>
		<span class="inline-label inline-label--light-blue">Info</span>
		<span class="inline-label inline-label--indigo">Request</span>
	</div>

	<h3>Sizes</h3>
	<div class="demo-row">
		<span class="inline-label inline-label--small">Small</span>
		<span class="inline-label">Base</span>
		<span class="inline-label inline-label--large">Large</span>
		<span class="inline-label inline-label--larger">Larger</span>
	</div>
</section>

<section class="demo-section">
	<h2>StatusIndicator (bare dot)</h2>
	<div class="demo-row">
		<span class="status-indicator" style="background-color: var(--color-success);"></span>
		<span class="dot-type">Success</span>
		<span class="status-indicator" style="background-color: var(--color-warning);"></span>
		<span class="dot-type">Warning</span>
		<span class="status-indicator" style="background-color: var(--color-critical);"></span>
		<span class="dot-type">Critical</span>
		<span class="status-indicator" style="background-color: var(--color-inactive);"></span>
		<span class="dot-type">Inactive</span>
		<span class="status-indicator" style="background-color: var(--color-informative);"></span>
		<span class="dot-type">Informative</span>
	</div>
	<p class="demo-note">Never used alone — always paired with text in real UI.</p>
</section>

<section class="demo-section">
	<h2>Chip (interactive pill)</h2>
	<div class="demo-row">
		<button class="chip" type="button">Filter</button>
		<button class="chip chip--subtle" type="button">Subtle</button>
		<button class="chip chip--invalid" type="button">Invalid</button>
		<button class="chip chip--dismissible" type="button">
			<span>Warnings</span>
			<span class="chip__dismiss" aria-label="Remove">×</span>
		</button>
	</div>
</section>

<a href={resolve('/demo')} class="demo-back">Back to demo</a>

<style lang="scss">
	// =============================================================================
	// STATUS + BADGE — demo of badges.md + status-indicators.md
	// =============================================================================

	// =====================================================================
	// StatusLabel — pill: dot + text. 24px tall, 12px radius, no border.
	// =====================================================================

	.status-label {
		display: flex;
		width: fit-content;
		flex-flow: row nowrap;
		align-items: center;
		gap: 6px;
		padding: 6px 10px 6px 8px;
		border-radius: 12px;
		background: var(--label-background);
	}

	.status-label--end {
		flex-direction: row-reverse;
	}

	.status-label__dot {
		flex-shrink: 0;
		width: 8px;
		height: 8px;
		border-radius: var(--radius-circle);
		background: var(--dot);
	}

	.status-label__text {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		line-height: 1;
		color: var(--label-text);
	}

	// =====================================================================
	// InlineLabel — generic badges. Base: 12px text, 16px radius.
	// =====================================================================

	.inline-label {
		display: inline-flex;
		width: fit-content;
		align-items: center;
		padding: 6px 10px;
		border-radius: var(--radius-large);
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
		line-height: 1;
		color: var(--color-heading);
		background: var(--color-inactive--surface);
	}

	.inline-label--small {
		padding: var(--space-smallest) var(--space-small);
		font-size: var(--typography--fontSize-smaller);
	}

	.inline-label--large {
		padding: 10px var(--space-slim);
		font-size: var(--typography--fontSize-large);
	}

	.inline-label--larger {
		padding: var(--space-slim) var(--space-base);
		font-size: var(--typography--fontSize-large);
		border-radius: var(--radius-larger);
	}

	.inline-label--red {
		background: var(--color-critical--surface);
		color: var(--color-critical--onSurface);
	}

	.inline-label--orange {
		background: var(--color-base-orange--200);
		color: var(--color-base-orange--600);
	}

	.inline-label--green {
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
	}

	.inline-label--blue {
		background: var(--color-inactive--surface);
		color: var(--color-inactive--onSurface);
	}

	.inline-label--navy {
		background: var(--color-task--surface);
		color: var(--color-task--onSurface);
	}

	.inline-label--yellow {
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
	}

	.inline-label--lime {
		background: var(--color-base-lime--200);
		color: var(--color-base-lime--700);
	}

	.inline-label--purple {
		background: var(--color-invoice--surface);
		color: var(--color-invoice--onSurface);
	}

	.inline-label--pink {
		background: var(--color-quote--surface);
		color: var(--color-quote--onSurface);
	}

	.inline-label--teal {
		background: var(--color-base-teal--200);
		color: var(--color-base-teal--700);
	}

	.inline-label--job {
		background: var(--color-job--surface);
		color: var(--color-job--onSurface);
	}

	.inline-label--blue-dark {
		background: var(--color-surface--reverse);
		color: var(--color-text--reverse--secondary);
	}

	.inline-label--light-blue {
		background: var(--color-informative--surface);
		color: var(--color-informative--onSurface);
	}

	.inline-label--indigo {
		background: var(--color-request--surface);
		color: var(--color-request--onSurface);
	}

	// =====================================================================
	// StatusIndicator — the only dot primitive (8px circle).
	// =====================================================================

	.status-indicator {
		display: inline-block;
		width: 8px;
		height: 8px;
		flex-shrink: 0;
		border-radius: var(--radius-circle);
	}

	.dot-type {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	// =====================================================================
	// Chip — interactive pill, 40px tall, 20px radius.
	// =====================================================================

	.chip {
		display: inline-flex;
		align-items: center;
		height: 40px;
		padding: 0 var(--base-unit);
		border: var(--border-base) solid transparent;
		border-radius: 20px;
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-base);
		font-weight: 400;
		color: var(--color-heading);
		background: var(--color-inactive--surface);
		cursor: pointer;
		transition: background var(--timing-base) ease;

		&:hover,
		&:focus-visible {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}
	}

	.chip--subtle {
		border-color: var(--color-border--interactive);
		background: var(--color-surface);

		&:hover,
		&:focus-visible {
			background: var(--color-interactive--background);
		}
	}

	.chip--invalid {
		border-color: var(--color-critical);
		background: var(--color-critical--surface);
	}

	.chip--dismissible {
		gap: var(--space-small);
	}

	.chip__dismiss {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: var(--space-large);
		height: var(--space-large);
		margin-inline-end: -8px;
		border-radius: var(--radius-circle);
		font-size: var(--typography--fontSize-large);
		line-height: 1;
		color: var(--color-heading);
		background: var(--color-surface);
		transition: background var(--timing-base) ease;

		&:hover,
		&:focus-visible {
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}
	}

	// =============================================================================
	// Demo page chrome (not part of the badge styles)
	// =============================================================================

	h1 {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-jumbo);
		color: var(--color-heading);
	}

	h2,
	h3 {
		font-family: var(--typography--fontFamily-normal);
		color: var(--color-heading);
	}

	h2 {
		font-size: var(--typography--fontSize-largest);
	}

	h3 {
		margin-block-start: var(--space-small);
		font-size: var(--typography--fontSize-larger);
	}

	.demo-intro {
		margin-block: var(--space-small) var(--space-largest);
		color: var(--color-text--secondary);
	}

	.demo-section {
		margin-block-end: var(--space-large);
	}

	.demo-row {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-base);
		align-items: center;
		padding: var(--space-large);
		margin-block-start: var(--space-small);
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.demo-row--end {
		justify-content: flex-start;
	}

	.demo-note {
		margin-block-start: var(--space-small);
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.demo-back {
		display: inline-block;
		margin-block-start: var(--space-large);
	}
</style>
