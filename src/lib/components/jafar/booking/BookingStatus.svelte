<script lang="ts">
	import type { Snippet } from 'svelte';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';

	// Jafar business management E1/E2: a public booking page's settled state -- booked, requested, moved, cancelled,
	// or a link that no longer works -- as a white top with the status tile, a heading and what happens next; then
	// the call's facts under a line, and a foot band with the change-or-cancel hint. Look: design skill `layout.md`
	// → Booking page → Settled states.

	type Props = {
		icon: string;
		tone?: 'success' | 'waiting' | 'neutral';
		title: string;
		children: Snippet;
		/** The call's facts (`BookingFacts`), under a line. */
		facts?: Snippet;
		/** The foot band's hint, after a mail icon. */
		hint?: Snippet;
		/** The foot band's action at the right, such as going back to the booking. */
		action?: Snippet;
	};

	let { icon, tone = 'neutral', title, children, facts, hint, action }: Props = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="booking-status">
	<div class="booking-status__top">
		<span class="booking-status__icon booking-status__icon--{tone}" aria-hidden="true"
			>{@html icon}</span
		>
		<h1 class="booking-status__title">{title}</h1>
		{@render children()}
	</div>
	{#if facts}
		<div class="booking-status__facts">{@render facts()}</div>
	{/if}
	{#if hint || action}
		<div class="booking-status__foot">
			{#if hint}
				<span class="booking-status__foot-icon" aria-hidden="true">{@html mailIcon}</span>
				<p>{@render hint()}</p>
			{/if}
			{#if action}<div class="booking-status__action">{@render action()}</div>{/if}
		</div>
	{/if}
</div>

<style lang="scss">
	.booking-status__top {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 14px;
		padding: 40px 40px 28px;
		text-align: center;

		:global(> p) {
			max-width: 440px;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-large);
			line-height: var(--typography--lineHeight-larger);
			overflow-wrap: anywhere;
		}

		@media (max-width: 640px) {
			padding: var(--space-larger) var(--space-base) var(--space-large);
		}
	}

	.booking-status__title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		letter-spacing: -0.5px;
	}

	.booking-status__icon {
		display: inline-grid;
		place-items: center;
		width: 56px;
		height: 56px;
		border: var(--border-base) solid var(--status-edge);
		border-radius: var(--radius-large);
		background: var(--status-surface);
		color: var(--status-ink);

		:global(svg) {
			width: 28px;
			height: 28px;
		}
	}

	.booking-status__icon--success {
		--status-surface: var(--color-success--surface);
		--status-edge: var(--color-success--surface-edge);
		--status-ink: var(--color-success);
	}

	.booking-status__icon--waiting {
		--status-surface: var(--color-warning--surface);
		--status-edge: var(--color-warning--surface-edge);
		--status-ink: var(--color-warning--onSurface);
	}

	.booking-status__icon--neutral {
		--status-surface: var(--color-inactive--surface);
		--status-edge: var(--color-inactive--surface-edge);
		--status-ink: var(--color-inactive);
	}

	.booking-status__facts {
		padding: var(--space-small) 28px;
		border-top: var(--border-base) solid var(--color-border);

		@media (max-width: 640px) {
			padding-inline: var(--space-base);
		}
	}

	.booking-status__foot {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 14px 28px;
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);

		p {
			flex: 1;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			line-height: var(--typography--lineHeight-larger);
		}

		@media (max-width: 640px) {
			padding-inline: var(--space-base);
		}
	}

	.booking-status__foot-icon {
		display: inline-flex;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.booking-status__action {
		margin-left: auto;
	}
</style>
