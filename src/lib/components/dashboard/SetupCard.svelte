<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import { fetchSetupSummary, setupSummaryKey } from '$lib/setup/api';
	import { SETUP_CHECK_KEY } from '$lib/setup/check';
	import { PROJECT_STATE_LABEL } from '$lib/setup/project-state';
	import { formatReadyDate } from '$lib/setup/ready';
	import { deliveredCardShowing } from '$lib/setup/training';

	// The dashboard's setup strip for owners and administrators: how far setup has got, the next useful
	// thing to do, and where delivery stands. It never gates anything — the CRM around it is complete and
	// usable (docs/client-onboarding-delivery-behavior-contract.md §2).
	let { userId }: { userId: string | null } = $props();

	const query = createQuery(() => ({
		queryKey: setupSummaryKey(userId),
		queryFn: fetchSetupSummary
	}));

	const summary = $derived(query.data);
	// E6: once delivered, the card says so for 14 days and then leaves the dashboard; the handover pack stays
	// in Settings.
	const deliveredOn = $derived(
		summary?.project.state === 'delivered'
			? (summary.project.steps.find((step) => step.state === 'delivered')?.on ?? null)
			: null
	);
	const hidden = $derived(deliveredOn !== null && !deliveredCardShowing(deliveredOn));

	// The administrator's first visit opens the welcome once. The setup page records that it was shown, so
	// coming back to the dashboard afterwards stays on the dashboard.
	$effect(() => {
		if (summary && !summary.welcome_seen)
			void goto(resolve('/(app)/setup'), { replaceState: true });
	});
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if summary?.welcome_seen && deliveredOn && !hidden}
	<section class="setup-card" aria-labelledby="setup-card-heading">
		<span class="setup-card__tile" aria-hidden="true">{@html circleCheckIcon}</span>
		<div class="setup-card__text">
			<h2 id="setup-card-heading">Project delivered</h2>
			<p class="setup-card__next">
				Uplift delivered your project on {new Date(deliveredOn).toLocaleDateString(undefined, {
					dateStyle: 'long'
				})}. Your handover pack has who owns which account and guides for your team; it stays in
				Settings after this card goes.
			</p>
		</div>
		<Button variant="secondary" href={resolve('/(app)/setup/handover')}>
			{@html arrowRightIcon}
			Open the handover pack
		</Button>
	</section>
{:else if summary?.welcome_seen && !deliveredOn}
	<section class="setup-card" aria-labelledby="setup-card-heading">
		<span class="setup-card__tile" aria-hidden="true">{@html rocketIcon}</span>
		<div class="setup-card__text">
			<h2 id="setup-card-heading">Set up your Uplift system</h2>
			<p class="setup-card__next">
				{summary.progress.done} of {summary.progress.total} done.
				{#if summary.next}
					{summary.next.returned ? 'Uplift needs changes:' : 'Next:'}
					{summary.next.title}.
				{:else}
					Every task is done and sent.
				{/if}
			</p>
			<p class="setup-card__status">
				<!-- E1: the project's step, as the Setup page's tracker names it. -->
				Delivery step {summary.project.position} of {summary.project.total} ·
				<strong>{PROJECT_STATE_LABEL[summary.project.state]}.</strong>
				{#if summary.returned_count > 0}
					Uplift sent back {summary.returned_count === 1
						? 'one task'
						: `${summary.returned_count} tasks`}. Change what Uplift asked for and send your setup
					again; everything else stays as you sent it.
				{:else if summary.project.state === 'live'}
					Your system is live. Next is training — tell Uplift who is coming on the Setup page.
				{:else if summary.project.state === 'approved'}
					Approved for launch. Uplift is finishing the launch steps.
				{:else if summary.delivery.state === 'ready'}
					Your system will be ready for you to review between
					{formatReadyDate(summary.delivery.target_from)} and {formatReadyDate(
						summary.delivery.target_to,
						true
					)}.
				{:else if summary.delivery.state === 'sent'}
					Sent to Uplift on {new Date(summary.delivery.submitted_at).toLocaleDateString(undefined, {
						dateStyle: 'long'
					})}. Uplift is checking it; your 7–10 business-day build starts once Uplift has accepted
					it.
				{:else}
					Not sent to Uplift yet. Your 7–10 business-day build starts once Uplift has accepted your
					setup.
				{/if}
				<a href={resolve('/(app)/setup')}>See all setup tasks</a>
			</p>
		</div>
		{#if summary.progress.total > 0}
			<div
				class="setup-card__progress"
				role="img"
				aria-label="{summary.progress.done} of {summary.progress.total} setup tasks done"
			>
				{#each Array.from({ length: summary.progress.total }, (_, step) => step) as index (index)}
					<span
						class={['setup-card__step', index < summary.progress.done && 'setup-card__step--done']}
					></span>
				{/each}
			</div>
		{/if}
		{#if summary.next}
			<Button
				variant="secondary"
				href={resolve('/(app)/setup/[section]', { section: summary.next.key })}
			>
				{@html arrowRightIcon}
				{summary.next.returned
					? 'Make the change'
					: summary.next.key === SETUP_CHECK_KEY
						? summary.returned_count > 0
							? 'Send your changes'
							: 'Check and send'
						: summary.next.status === 'not_started'
							? 'Start setup'
							: 'Continue setup'}
			</Button>
		{/if}
	</section>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-card {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-base) var(--space-medium);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__tile {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 40px;
			height: 40px;
			border-radius: var(--radius-tile-large);
			color: var(--color-success);
			background: var(--color-success--surface);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}

		&__text {
			display: grid;
			min-width: 0;
			flex: 1;
			gap: 2px;

			h2 {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-large);
				font-weight: 600;
			}
		}
		&__next {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
		}
		&__status {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);

			strong {
				color: var(--color-heading);
				font-weight: 600;
			}
			a {
				border-radius: var(--radius-small);
				color: var(--color-interactive);
				font-weight: 600;
				white-space: nowrap;

				&:hover {
					text-decoration: underline;
				}
				&:focus-visible {
					outline: none;
					box-shadow: var(--shadow-focus);
				}
			}
		}

		&__progress {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-smaller);
		}
		&__step {
			width: 28px;
			height: 6px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);

			&--done {
				background: var(--color-success);
			}
		}
	}

	@media (max-width: 760px) {
		.setup-card {
			flex-wrap: wrap;

			&__text {
				flex-basis: calc(100% - 56px);
			}
		}
	}
</style>
