<script lang="ts">
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import settingsIcon from '@tabler/icons/outline/settings.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import circleXIcon from '@tabler/icons/outline/circle-x.svg?raw';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();

	type Tone = 'success' | 'info' | 'warning' | 'neutral';
	type StatusCopy = { icon: string; tone: Tone; eyebrow: string; title: string; text: string };

	// Each state says only what is true right now and what happens next (behavior contract §1).
	const copy = {
		reviewing: {
			icon: circleCheckIcon,
			tone: 'success',
			eyebrow: 'Application received',
			title: "Thanks, we've got your application",
			text: "We're checking your details. Next, we'll email you a secure payment link."
		},
		awaiting_payment: {
			icon: creditCardIcon,
			tone: 'info',
			eyebrow: 'Waiting for payment',
			title: 'Your payment link is in your inbox',
			text: "Pay using the secure link we emailed you. If you've already paid, we're checking it has reached us. You don't need to send proof."
		},
		setting_up: {
			icon: settingsIcon,
			tone: 'success',
			eyebrow: 'Payment confirmed',
			title: "We're setting up your account",
			text: "Your payment has reached us. We'll email your account administrator a link to set a password and sign in."
		},
		account_ready: {
			icon: mailIcon,
			tone: 'success',
			eyebrow: 'Account ready',
			title: 'Your account is ready',
			text: "We've emailed your account administrator a secure link to set a password and sign in. If it isn't in the inbox, check spam, or reply to any of our emails for a new one."
		},
		payment_problem: {
			icon: alertCircleIcon,
			tone: 'warning',
			eyebrow: 'Payment problem',
			title: "We couldn't keep your payment",
			text: "Your payment didn't complete on our side, so your account is on hold. We'll contact you by email about how to fix it."
		},
		closed: {
			icon: circleXIcon,
			tone: 'neutral',
			eyebrow: 'Application closed',
			title: 'This application is closed',
			text: 'If you think this is a mistake, or you would like to start again, reply to any of our emails.'
		}
	} satisfies Record<NonNullable<typeof data.status>, StatusCopy>;

	// A missing or unknown link still lands on a friendly page rather than an error.
	const fallback: StatusCopy = {
		icon: clockIcon,
		tone: 'neutral',
		eyebrow: 'Application received',
		title: "Thanks, we've got your application",
		text: "We'll review your details and follow up by email with next steps, including how to complete payment. There's nothing else to do right now."
	};

	const current = $derived(data.status ? copy[data.status] : fallback);
</script>

<svelte:head>
	<title>{current.eyebrow} · UpliftContractor</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="received">
	<section class="received__card" aria-labelledby="received-title">
		<!-- eslint-disable-next-line svelte/no-at-html-tags -- bundled Tabler icon -->
		<div class="received__mark received__mark--{current.tone}" aria-hidden="true">
			{@html current.icon}
		</div>
		<div class="received__eyebrow">{current.eyebrow}</div>
		<h1 id="received-title">{current.title}</h1>
		<p>{current.text}</p>
		{#if data.renderedBody}
			<!-- eslint-disable-next-line svelte/no-at-html-tags -- Jafar-authored template body, same trusted-content pattern as the message-templates preview -->
			<div class="received__body">{@html data.renderedBody}</div>
		{/if}
		{#if data.status}
			<p class="received__hint">Bookmark this page to check on your application any time.</p>
		{/if}
	</section>
</main>

<style lang="scss">
	.received {
		display: flex;
		min-height: 100vh;
		align-items: center;
		justify-content: center;
		padding: var(--space-large);
		background: var(--color-background);
	}
	.received__card {
		max-width: 560px;
		padding: var(--space-extravagant);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
		text-align: center;
	}
	.received__mark {
		display: grid;
		width: 56px;
		height: 56px;
		margin: 0 auto var(--space-base);
		place-items: center;
		border-radius: var(--radius-circle);

		:global(svg) {
			width: 28px;
			height: 28px;
		}
	}
	.received__mark--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.received__mark--info {
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.received__mark--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.received__mark--neutral {
		color: var(--color-text--secondary);
		background: var(--color-surface--background);
	}
	.received__eyebrow {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.received__card h1 {
		margin: var(--space-small) 0 var(--space-base);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-jumbo);
	}
	.received__card p {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.received__card .received__hint {
		margin: var(--space-base) 0 0;
		font-size: var(--typography--fontSize-small);
	}
	.received__body {
		margin-top: var(--space-base);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
		text-align: left;
	}
	@media (max-width: 560px) {
		.received__card {
			padding: var(--space-largest) var(--space-large);
		}
	}
</style>
