<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { fetchReadiness, readinessKey } from '$lib/readiness/api';

	// The dashboard's "Switched on for customers" card for owners and administrators (multi-industry
	// foundation B8). Paying and Setup open the workspace for private preparation; each real-world area
	// (messages, quotes and invoices, web requests, automations) opens when Uplift signs it off. The card
	// shows only while something is still closed, and names the specific tasks and who does them.
	let { userId }: { userId: string | null } = $props();

	const query = createQuery(() => ({ queryKey: readinessKey(userId), queryFn: fetchReadiness }));
	const closed = $derived((query.data?.areas ?? []).filter((area) => !area.open));
</script>

{#if closed.length > 0}
	<section class="readiness-card" aria-labelledby="readiness-card-heading">
		<header class="readiness-card__header">
			<span class="readiness-card__eyebrow">Uplift sign-off</span>
			<h2 id="readiness-card-heading">Not switched on for your customers yet</h2>
			<p>
				You can keep preparing. These open when Uplift signs them off, so nothing reaches your
				customers before it is ready.
			</p>
		</header>
		<ul class="readiness-card__areas">
			{#each closed as area (area.key)}
				<li class="readiness-card__area">
					<strong>{area.label}</strong>
					{#if area.state === 'held'}
						<p>{area.message ?? 'Uplift has put this on hold. Contact Uplift Support.'}</p>
					{:else if area.waiting_for.length > 0}
						<p>Waiting for {area.waiting_for.map((required) => required.label).join(' and ')}.</p>
					{:else if area.state === 'not_started'}
						<p>Uplift has not reviewed this yet.</p>
					{:else if area.tasks.length === 0}
						<p>Uplift is doing its final review.</p>
					{/if}
					{#if area.tasks.length > 0}
						<ul class="readiness-card__tasks">
							{#each area.tasks as task (task.key)}
								<li>
									<span
										class="readiness-card__owner"
										class:readiness-card__owner--you={task.owner === 'business'}
										>{task.owner === 'business' ? 'You' : 'Uplift'}</span
									>
									{task.task}
								</li>
							{/each}
						</ul>
					{/if}
				</li>
			{/each}
		</ul>
	</section>
{/if}

<style lang="scss">
	.readiness-card {
		margin-bottom: var(--space-large);
		padding: var(--space-base) var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__header {
			display: grid;
			gap: var(--space-smaller);
			margin-bottom: var(--space-base);

			h2 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
			}

			p {
				margin: 0;
				color: var(--color-text--secondary);
			}
		}

		&__eyebrow {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			letter-spacing: 0.08em;
			text-transform: uppercase;
		}

		&__areas,
		&__tasks {
			display: grid;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__area {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-slim) 0;
			border-top: var(--border-base) solid var(--color-border);

			strong {
				color: var(--color-heading);
			}

			p {
				margin: 0;
				color: var(--color-text--secondary);
			}
		}

		&__tasks {
			gap: var(--space-smaller);

			li {
				display: flex;
				align-items: baseline;
				gap: var(--space-small);
				color: var(--color-heading);
			}
		}

		&__owner {
			flex: none;
			min-width: 3.5rem;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;

			&--you {
				color: var(--color-interactive);
			}
		}
	}

	@media (max-width: 639px) {
		.readiness-card {
			padding: var(--space-base);
		}
	}
</style>
