<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import ComposerChannelMenu from '$lib/components/communications/ComposerChannelMenu.svelte';
	import {
		automationReviewReadinessKey,
		fetchAutomationReviewReadiness
	} from '$lib/settings/automation-authoring';
	import type { ReviewChannel } from '$lib/reviews/settings';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';

	// Google review Part 4B: the authoring card for one "Send a review request" step. Following HighLevel's
	// Review Request action, the step only picks the channel; the wording, style, first-send delay and reminders
	// come from Review settings, so this card points there instead of repeating them. It warns when the step
	// could not send today (no Google link, or the channel is not set up for automatic messages); the worker
	// re-checks all of it when the step runs and records a visible "not sent" request instead of guessing.
	let {
		channel,
		onChannelChange
	}: {
		channel: ReviewChannel;
		onChannelChange: (channel: ReviewChannel) => void;
	} = $props();

	const readinessQuery = createQuery(() => ({
		queryKey: automationReviewReadinessKey,
		queryFn: fetchAutomationReviewReadiness
	}));

	const readiness = $derived(readinessQuery.data);
	const channelReady = $derived(
		readiness ? (channel === 'sms' ? readiness.sms_ready : readiness.email_ready) : true
	);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="review-step">
	<div class="review-step__channel">
		<span class="review-step__label">Send by</span>
		<ComposerChannelMenu
			{channel}
			channels={['sms', 'email']}
			onSelect={(value) => onChannelChange(value === 'email' ? 'email' : 'sms')}
		/>
	</div>

	{#if readinessQuery.isPending}
		<div class="review-step__skeleton" aria-hidden="true"></div>
	{:else if readiness}
		{#if !readiness.has_google_link}
			<p class="review-step__notice review-step__notice--warning">
				<span class="review-step__notice-icon" aria-hidden="true">{@html alertTriangleIcon}</span>
				<span>
					Add your Google review link before turning this on. Until then, customers are not asked.
					<a class="review-step__link" href={resolve('/(app)/reviews/settings')}>
						Add it in Review settings
					</a>
				</span>
			</p>
		{/if}
		{#if !channelReady}
			<p class="review-step__notice review-step__notice--warning">
				<span class="review-step__notice-icon" aria-hidden="true">{@html alertTriangleIcon}</span>
				{#if channel === 'sms'}
					<span>
						Your texting number is not ready to send automatic messages yet.
						<a class="review-step__link" href={resolve('/(app)/settings/communications/sms')}>
							Set up texting
						</a>
					</span>
				{:else}
					<span>
						Your business email is not set up to send automatic messages yet.
						<a class="review-step__link" href={resolve('/(app)/settings/communications/email')}>
							Set up email
						</a>
					</span>
				{/if}
			</p>
		{/if}
	{:else if readinessQuery.isError}
		<p class="review-step__muted">
			We couldn’t check whether this can send right now. It is checked again when the step runs.
		</p>
	{/if}

	<p class="review-step__notice">
		<span class="review-step__notice-icon" aria-hidden="true">{@html infoIcon}</span>
		<span>
			The message, its style, when it goes out and any reminders come from
			<a class="review-step__link" href={resolve('/(app)/reviews/settings')}>Review settings</a>. It
			goes to the client’s main {channel === 'sms' ? 'mobile number' : 'email address'}, and is
			skipped if this automation already asked them in the last 6 months.
		</span>
	</p>
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.review-step {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__channel {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__skeleton {
			height: 40px;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			animation: review-step-pulse 1.2s ease-in-out infinite;
		}

		&__notice {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);

			&--warning {
				border-color: var(--color-warning);
				color: var(--color-text);
				background: var(--color-warning--surface);
			}
		}

		&__notice-icon {
			display: grid;
			place-items: center;
			flex: 0 0 auto;
			padding-top: 2px;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__notice--warning &__notice-icon {
			color: var(--color-warning--onSurface);
		}

		// The brand link colour does not read on the warning surface; the underline marks it instead.
		&__notice--warning &__link,
		&__notice--warning &__link:hover {
			color: inherit;
		}

		&__link {
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: underline;

			&:hover {
				color: var(--color-interactive--hover);
			}

			&:focus-visible {
				border-radius: var(--radius-small);
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}

	@keyframes review-step-pulse {
		50% {
			opacity: 0.5;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.review-step__skeleton {
			animation: none;
		}
	}
</style>
