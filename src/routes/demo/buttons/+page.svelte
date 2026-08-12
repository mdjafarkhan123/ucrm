<script lang="ts">
	import { resolve } from '$app/paths';
</script>

<svelte:head>
	<title>Button states demo</title>
</svelte:head>

<h1>Button states</h1>
<p class="demo-intro">
	Hover, focus (Tab / click), and press any interactive button. Simulated states are shown beneath
	each group.
</p>

<section class="demo-section">
	<h2>Sizes</h2>
	<div class="demo-row">
		<button class="btn btn--primary btn--small">Small</button>
		<button class="btn btn--primary">Base</button>
		<button class="btn btn--primary btn--large">Large</button>
	</div>
</section>

<section class="demo-section">
	<h2>Types</h2>
	<div class="demo-row">
		<button class="btn btn--work btn--primary">Primary</button>
		<button class="btn btn--work btn--secondary">Secondary</button>
		<button class="btn btn--work btn--tertiary">Tertiary</button>
	</div>

	<h3>Learning</h3>
	<div class="demo-row">
		<button class="btn btn--learning btn--primary">Primary</button>
		<button class="btn btn--learning btn--secondary">Secondary</button>
		<button class="btn btn--learning btn--tertiary">Tertiary</button>
	</div>

	<h3>Subtle</h3>
	<div class="demo-row">
		<button class="btn btn--subtle btn--primary">Primary</button>
		<button class="btn btn--subtle btn--secondary">Secondary</button>
		<button class="btn btn--subtle btn--tertiary">Tertiary</button>
	</div>

	<h3>Destructive</h3>
	<div class="demo-row">
		<button class="btn btn--destructive btn--primary">Primary</button>
		<button class="btn btn--destructive btn--secondary">Secondary</button>
		<button class="btn btn--destructive btn--tertiary">Tertiary</button>
	</div>
</section>

<section class="demo-section">
	<h2>States (simulated)</h2>
	<div class="demo-row">
		<button class="btn btn--work btn--primary btn--sim-hover">Hover</button>
		<button class="btn btn--work btn--secondary btn--sim-hover">Hover</button>
		<button class="btn btn--work btn--tertiary btn--sim-hover">Hover</button>
	</div>
	<div class="demo-row">
		<button class="btn btn--work btn--primary btn--sim-focus">Focus</button>
		<button class="btn btn--work btn--secondary btn--sim-focus">Focus</button>
		<button class="btn btn--work btn--tertiary btn--sim-focus">Focus</button>
	</div>
	<div class="demo-row">
		<button class="btn btn--work btn--primary btn--sim-active">Active</button>
		<button class="btn btn--work btn--secondary btn--sim-active">Active</button>
		<button class="btn btn--work btn--tertiary btn--sim-active">Active</button>
	</div>
</section>

<section class="demo-section">
	<h2>Disabled</h2>
	<div class="demo-row">
		<button class="btn btn--work btn--primary" disabled>Primary</button>
		<button class="btn btn--work btn--secondary" disabled>Secondary</button>
		<button class="btn btn--work btn--tertiary" disabled>Tertiary</button>
		<button class="btn btn--destructive btn--primary" disabled>Destructive</button>
	</div>
</section>

<section class="demo-section">
	<h2>Loading</h2>
	<div class="demo-row">
		<button class="btn btn--work btn--primary btn--loading" aria-busy="true">Sending</button>
		<button class="btn btn--work btn--secondary btn--loading" aria-busy="true">Sending</button>
		<button class="btn btn--work btn--tertiary btn--loading" aria-busy="true">Sending</button>
	</div>
</section>

<section class="demo-section">
	<h2>Interact with a live button</h2>
	<div class="demo-row">
		<button class="btn btn--work btn--primary">Save Changes</button>
		<button class="btn btn--work btn--secondary">Go Back</button>
		<button class="btn btn--destructive btn--secondary">Delete Visit</button>
	</div>
</section>

<a href={resolve('/demo')} class="demo-back">Back to demo</a>

<style lang="scss">
	// =============================================================================
	// BUTTON — design system component demo (mirrors .codex/skills/design/buttons.md)
	// =============================================================================

	.btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		box-sizing: border-box;
		gap: var(--space-smaller);
		min-height: 40px;
		padding-inline: var(--space-base);
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
		line-height: var(--typography--lineHeight-base);
		text-decoration: none;
		user-select: none;
		cursor: pointer;
		transition: all var(--timing-base) ease-out;

		&:hover,
		&:focus-visible,
		&:active {
			background: var(--button--color-variation--hover);
		}

		&:focus-visible,
		&:active {
			outline: transparent;
			box-shadow: var(--shadow-focus);
		}

		&:disabled {
			background: var(--color-disabled--secondary);
			border-color: var(--color-disabled--secondary);
			color: var(--color-disabled);
			cursor: not-allowed;
			pointer-events: none;
			user-select: none;
		}
	}

	.btn--small {
		min-height: 32px;
		padding-block: var(--space-smaller);
		padding-inline: var(--space-slim);
	}

	.btn--large {
		min-height: 48px;
		padding-inline: calc(var(--space-base) + var(--space-smaller));
		font-size: var(--typography--fontSize-large);
	}

	// =============================================================================
	// SIZES done. Variations set the semantic action color pair.
	// =============================================================================

	.btn--work {
		--button--color-variation: var(--color-interactive);
		--button--color-variation--hover: var(--color-interactive--hover);
	}

	.btn--learning {
		--button--color-variation: var(--color-interactive--subtle);
		--button--color-variation--hover: var(--color-interactive--subtle--hover);
	}

	.btn--subtle {
		--button--color-variation: var(--color-interactive--subtle);
		--button--color-variation--hover: var(--color-interactive--subtle--hover);
	}

	.btn--destructive {
		--button--color-variation: var(--color-destructive);
		--button--color-variation--hover: var(--color-destructive--hover);
	}

	// =====================================================================
	// Types — hierarchy using the variation color pair.
	// =====================================================================

	.btn--primary {
		background: var(--button--color-variation);
		border-color: var(--button--color-variation);
		color: var(--color-surface);
	}

	.btn--secondary {
		background: var(--color-surface);
		border-color: var(--color-border--interactive);
		color: var(--button--color-variation);

		&:hover,
		&:focus-visible,
		&:active {
			background: var(--color-surface--hover);
			border-color: var(--button--color-variation--hover);
			color: var(--button--color-variation--hover);
		}
	}

	.btn--tertiary {
		background: var(--color-surface);
		border-color: transparent;
		color: var(--button--color-variation);

		&:hover,
		&:focus-visible,
		&:active {
			background: var(--color-surface--hover);
			color: var(--button--color-variation--hover);
		}
	}

	// =====================================================================
	// Simulated states — for static preview only (same rules as interact).
	// =====================================================================

	.btn--sim-hover {
		background: var(--button--color-variation--hover);
		border-color: var(--button--color-variation--hover);
		color: var(--color-surface);
	}

	.btn--secondary.btn--sim-hover,
	.btn--tertiary.btn--sim-hover {
		background: var(--color-surface--hover);
		border-color: var(--button--color-variation--hover);
		color: var(--button--color-variation--hover);
	}

	.btn--sim-focus {
		outline: transparent;
		box-shadow: var(--shadow-focus);

		&:not(.btn--secondary):not(.btn--tertiary) {
			background: var(--button--color-variation--hover);
			border-color: var(--button--color-variation--hover);
			color: var(--color-surface);
		}

		&.btn--secondary,
		&.btn--tertiary {
			background: var(--color-surface--hover);
			border-color: var(--button--color-variation--hover);
			color: var(--button--color-variation--hover);
		}
	}

	.btn--sim-active {
		outline: transparent;
		box-shadow: var(--shadow-focus);

		&:not(.btn--secondary):not(.btn--tertiary) {
			background: var(--button--color-variation--hover);
			border-color: var(--button--color-variation--hover);
			color: var(--color-surface);
		}

		&.btn--secondary,
		&.btn--tertiary {
			background: var(--color-surface--hover);
			border-color: var(--button--color-variation--hover);
			color: var(--button--color-variation--hover);
		}
	}

	// =====================================================================
	// Loading — striped overlay, no pointer events.
	// =====================================================================

	@keyframes button-stripes {
		0% {
			background-position: 0 0;
		}

		100% {
			background-position: var(--space-larger) 0;
		}
	}

	.btn--loading {
		cursor: not-allowed;
		pointer-events: none;
		position: relative;

		&::after {
			content: '';
			position: absolute;
			inset: 0;
			border-radius: inherit;
			background-image: linear-gradient(
				45deg,
				rgb(255 255 255 / 0.15) 25%,
				transparent 25%,
				transparent 50%,
				rgb(255 255 255 / 0.15) 50%,
				rgb(255 255 255 / 0.15) 75%,
				transparent 75%,
				transparent
			);
			background-size: var(--space-larger) var(--space-larger);
			animation: button-stripes var(--timing-loading--extended) linear infinite;
		}

		&.btn--secondary::after,
		&.btn--tertiary::after {
			background-image: linear-gradient(
				45deg,
				rgb(0 0 0 / 0.12) 25%,
				transparent 25%,
				transparent 50%,
				rgb(0 0 0 / 0.12) 50%,
				rgb(0 0 0 / 0.12) 75%,
				transparent 75%,
				transparent
			);
		}
	}

	// =============================================================================
	// Demo page chrome (not part of the button styles)
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

	.demo-back {
		display: inline-block;
		margin-block-start: var(--space-large);
	}
</style>
