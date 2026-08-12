<script lang="ts">
	import { resolve } from '$app/paths';

	let modalOpen = $state(false);

	let size = $state<'default' | 'small' | 'large'>('default');
</script>

<svelte:head>
	<title>Card & modal demo</title>
</svelte:head>

<h1>Cards &amp; modals</h1>
<p class="demo-intro">
	Cards follow .agents/skills/design/cards.md. Modals follow modals.md — open one to see overlay,
	focus trap, and actions layout.
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

<section class="demo-section">
	<h2>Modal</h2>
	<div class="demo-row">
		<button
			class="btn btn--work btn--primary"
			type="button"
			onclick={() => {
				size = 'default';
				modalOpen = true;
			}}>Open modal</button
		>
		<button
			class="btn btn--work btn--secondary"
			type="button"
			onclick={() => {
				size = 'small';
				modalOpen = true;
			}}>Small modal</button
		>
		<button
			class="btn btn--work btn--secondary"
			type="button"
			onclick={() => {
				size = 'large';
				modalOpen = true;
			}}>Large modal</button
		>
	</div>
</section>

{#if modalOpen}
	<div
		class="modal-backdrop"
		role="presentation"
		onclick={(e) => {
			if (e.target === e.currentTarget) modalOpen = false;
		}}
		onkeydown={(e) => {
			if (e.key === 'Escape') modalOpen = false;
		}}
	>
		<div class="modal modal--{size}" role="dialog" aria-modal="true" aria-labelledby="modal-title">
			<header class="modal__header">
				<h2 class="modal__title" id="modal-title">Schedule job</h2>
				<button
					class="btn btn--subtle btn--tertiary modal__close"
					type="button"
					aria-label="Close"
					onclick={() => (modalOpen = false)}
				>
					&times;
				</button>
			</header>
			<div class="modal__body">
				<p>
					Book the technician and confirm the visit window. The client will receive an invitation
					with the scheduled time and arrival notes.
				</p>
			</div>
			<footer class="modal__actions">
				<button class="btn btn--work btn--primary" type="button" onclick={() => (modalOpen = false)}
					>Schedule Visit</button
				>
				<button
					class="btn btn--work btn--secondary"
					type="button"
					onclick={() => (modalOpen = false)}>Go Back</button
				>
			</footer>
		</div>
	</div>
{/if}

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
	// MODAL — demo of .agents/skills/design/modals.md
	// =============================================================================

	.modal-backdrop {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--color-overlay);
		opacity: 1;
		animation: modal-backdrop-in var(--timing-slower) ease;
	}

	.modal {
		display: flex;
		flex-direction: column;
		box-sizing: border-box;
		width: 100%;
		max-width: var(--modal--width, 600px);
		max-height: calc(100dvh - 2 * var(--space-base));
		margin: auto;
		padding: var(--modal--padding, var(--space-base));
		overflow: hidden;
		background: var(--color-surface);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		box-shadow: var(--shadow-base);

		@media (min-width: 640px) {
			padding: var(--space-large);
		}
	}

	.modal--small {
		--modal--width: 400px;
	}

	.modal--large {
		--modal--width: 940px;
	}

	.modal__header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--modal--padding, var(--space-base));

		@media (min-width: 640px) {
			padding: var(--space-large);
		}
	}

	.modal__title {
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-larger);
		font-weight: 600;
		color: var(--color-heading);
	}

	.modal__close {
		margin: -6px;
		padding: var(--space-smaller);
	}

	.modal__body {
		display: flex;
		flex-direction: column;
		padding: var(--space-small);
		overflow-y: auto;
		max-height: inherit;
		font-family: var(--typography--fontFamily-normal);
		font-size: var(--typography--fontSize-large);
		color: var(--color-text);
	}

	.modal__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		padding: var(--modal--padding, var(--space-base));
		padding-top: 0;
		margin-block-start: var(--space-base);

		@media (min-width: 640px) {
			padding: var(--space-large);
			padding-top: 0;
		}
	}

	@keyframes modal-backdrop-in {
		from {
			opacity: 0;
		}

		to {
			opacity: 1;
		}
	}

	// =============================================================================
	// Demo page chrome (not part of the component styles)
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

	.demo-row {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
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
