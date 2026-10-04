<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Button from '$lib/components/ui/Button.svelte';
	import { fetchSetupSummary, setupSummaryKey } from '$lib/setup/api';
	import { SETUP_CHECK_KEY } from '$lib/setup/check';

	// The dashboard's setup card for owners and administrators: how far setup has got, the next useful
	// thing to do, and where delivery stands. It never gates anything — the CRM around it is complete and
	// usable (docs/client-onboarding-delivery-behavior-contract.md §2).
	let { userId }: { userId: string | null } = $props();

	const query = createQuery(() => ({
		queryKey: setupSummaryKey(userId),
		queryFn: fetchSetupSummary
	}));

	const summary = $derived(query.data);
	const percent = $derived(
		summary?.progress.total ? Math.round((summary.progress.done / summary.progress.total) * 100) : 0
	);

	// The administrator's first visit opens the welcome once. The setup page records that it was shown, so
	// coming back to the dashboard afterwards stays on the dashboard.
	$effect(() => {
		if (summary && !summary.welcome_seen)
			void goto(resolve('/(app)/setup'), { replaceState: true });
	});
</script>

{#if summary?.welcome_seen}
	<section class="setup-card" aria-labelledby="setup-card-heading">
		<header class="setup-card__header">
			<div>
				<span class="setup-card__eyebrow">Setup</span>
				<h2 id="setup-card-heading">Set up your Uplift system</h2>
			</div>
			<span class="setup-card__count"
				>{summary.progress.done} of {summary.progress.total}
				{summary.progress.total === 1 ? 'task' : 'tasks'} done</span
			>
		</header>

		<div class="setup-card__bar" role="presentation">
			<div class="setup-card__bar-fill" style:width="{percent}%"></div>
		</div>

		<div class="setup-card__next">
			{#if summary.next}
				<div class="setup-card__text">
					<span class="setup-card__label"
						>{summary.next.returned ? 'Uplift needs changes' : 'Next'}</span
					>
					<strong>{summary.next.title}</strong>
				</div>
				<Button size="small" href={resolve('/(app)/setup/[section]', { section: summary.next.key })}
					>{summary.next.returned
						? 'Make the change'
						: summary.next.key === SETUP_CHECK_KEY
							? summary.returned_count > 0
								? 'Send your changes'
								: 'Check and send'
							: summary.next.status === 'not_started'
								? 'Start'
								: 'Continue'}</Button
				>
			{:else}
				<div class="setup-card__text">
					<span class="setup-card__label">Next</span>
					<strong>Every task is done and sent</strong>
				</div>
			{/if}
		</div>

		<p class="setup-card__status">
			<span class="setup-card__label">Delivery</span>
			{#if summary.returned_count > 0}
				Uplift sent back {summary.returned_count === 1
					? 'one task'
					: `${summary.returned_count} tasks`}. Change what Uplift asked for and send your setup
				again; everything else stays as you sent it.
			{:else if summary.delivery.state === 'sent'}
				Sent to Uplift on {new Date(summary.delivery.submitted_at).toLocaleDateString(undefined, {
					dateStyle: 'long'
				})}. Uplift is checking it; your 7–10 business-day build starts once Uplift has accepted it.
			{:else}
				Not sent to Uplift yet. Your 7–10 business-day build starts once Uplift has accepted your
				setup.
			{/if}
			<a href={resolve('/(app)/setup')}>See all setup tasks</a>
		</p>
	</section>
{/if}

<style lang="scss">
	.setup-card {
		margin-bottom: var(--space-large);
		padding: var(--space-base) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			margin-bottom: var(--space-slim);
		}

		&__eyebrow,
		&__label {
			display: block;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			letter-spacing: 0.08em;
			text-transform: uppercase;
		}

		&__eyebrow {
			margin-bottom: var(--space-smaller);
		}

		h2 {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
		}

		&__count {
			flex: none;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__bar {
			width: 100%;
			height: 6px;
			margin-bottom: var(--space-base);
			border-radius: var(--radius-large);
			background: var(--color-surface--background--subtle);
			overflow: hidden;
		}

		&__bar-fill {
			height: 100%;
			border-radius: var(--radius-large);
			background: var(--color-interactive);
			transition: width var(--timing-quick) ease;
		}

		&__next {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			padding: var(--space-slim) 0;
			border-top: var(--border-base) solid var(--color-border);
		}

		&__text {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
			}
		}

		&__status {
			padding-top: var(--space-slim);
			border-top: var(--border-base) solid var(--color-border);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);

			a {
				color: var(--color-interactive);
				font-weight: 600;
				white-space: nowrap;

				&:hover {
					text-decoration: underline;
				}
			}
		}

		&__status &__label {
			margin-bottom: var(--space-smallest);
		}
	}

	@media (max-width: 560px) {
		.setup-card {
			padding: var(--space-base);

			&__header {
				align-items: flex-start;
				flex-direction: column;
				gap: var(--space-smaller);
			}
		}
	}
</style>
