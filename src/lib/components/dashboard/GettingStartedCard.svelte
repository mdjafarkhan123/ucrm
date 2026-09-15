<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

	// Owner/admin-only nudge on the dashboard. Every item reflects real backend state -- see
	// src/lib/server/onboarding/checklist.ts -- so the card can never claim a step is done when it is not.
	// It disappears once every step is complete, the same way Stripe/HubSpot's setup checklists do: no
	// dismiss button to build or a "hidden" flag to store.
	let { onAddClient }: { onAddClient: () => void } = $props();

	type ChecklistItem = {
		key: 'business_profile' | 'price_book' | 'first_client' | 'invite_team';
		label: string;
		description: string;
		complete: boolean;
	};
	type ChecklistResponse = { items: ChecklistItem[]; all_complete: boolean };

	const query = createQuery<ChecklistResponse>(() => ({
		queryKey: ['onboarding', 'checklist'],
		queryFn: fetchChecklist
	}));

	async function fetchChecklist(): Promise<ChecklistResponse> {
		const response = await fetch('/api/onboarding/checklist');
		if (!response.ok) throw new Error('checklist unavailable');
		return response.json();
	}

	const items = $derived(query.data?.items ?? []);
	const doneCount = $derived(items.filter((item) => item.complete).length);
	const progressPercent = $derived(items.length ? Math.round((doneCount / items.length) * 100) : 0);
</script>

{#if query.isSuccess && !query.data.all_complete}
	<section class="getting-started" aria-labelledby="getting-started-heading">
		<header class="getting-started__header">
			<div>
				<span class="getting-started__eyebrow">Setup</span>
				<h2 id="getting-started-heading">Getting started</h2>
			</div>
			<span class="getting-started__count">{doneCount} of {items.length} done</span>
		</header>
		<div class="getting-started__bar" role="presentation">
			<div class="getting-started__bar-fill" style:width="{progressPercent}%"></div>
		</div>
		<ul class="getting-started__list">
			{#each items as item (item.key)}
				<li class="getting-started__item" class:getting-started__item--done={item.complete}>
					<span class="getting-started__check" aria-hidden="true">
						{#if item.complete}
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							{@html checkIcon}
						{/if}
					</span>
					<div class="getting-started__text">
						<strong>{item.label}</strong>
						<span>{item.description}</span>
					</div>
					{#if !item.complete}
						{#if item.key === 'first_client'}
							<button class="getting-started__action" type="button" onclick={onAddClient}
								>Add now</button
							>
						{:else if item.key === 'business_profile'}
							<a class="getting-started__action" href={resolve('/(app)/settings/business-profile')}
								>Go</a
							>
						{:else if item.key === 'price_book'}
							<a class="getting-started__action" href={resolve('/(app)/settings/price-book')}>Go</a>
						{:else}
							<a class="getting-started__action" href={resolve('/(app)/settings/team')}>Go</a>
						{/if}
					{/if}
				</li>
			{/each}
		</ul>
	</section>
{/if}

<style lang="scss">
	.getting-started {
		margin-bottom: var(--space-large);
		padding: var(--space-base) var(--space-large);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			margin-bottom: var(--space-slim);
		}

		&__eyebrow {
			display: block;
			margin-bottom: 4px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			letter-spacing: 0.08em;
			text-transform: uppercase;
		}

		h2 {
			color: var(--color-heading);
			font-size: 20px;
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

		&__list {
			display: grid;
			gap: var(--space-slim);
			list-style: none;
		}

		&__item {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) 0;
			border-top: 1px solid var(--color-border);

			&:first-child {
				border-top: 0;
			}
		}

		&__item--done &__text strong {
			color: var(--color-text--secondary);
			text-decoration: line-through;
		}

		&__check {
			display: grid;
			flex: none;
			place-items: center;
			width: 24px;
			height: 24px;
			border: 1px solid var(--color-border);
			border-radius: var(--radius-circle);
			background: var(--color-surface--background--subtle);

			:global(svg) {
				width: 14px;
				height: 14px;
			}

			.getting-started__item--done & {
				border-color: transparent;
				color: var(--color-success--onSurface);
				background: var(--color-success--surface);
			}
		}

		&__text {
			display: flex;
			flex: 1;
			flex-direction: column;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__action {
			flex: none;
			padding: 6px 12px;
			border: 1px solid var(--color-border);
			border-radius: var(--radius-small);
			color: var(--color-heading);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			transition: background var(--timing-quick) ease;

			&:hover {
				background: var(--color-surface--hover);
			}
		}
	}

	@media (max-width: 560px) {
		.getting-started__item {
			flex-wrap: wrap;
		}
		.getting-started__action {
			margin-left: 32px;
		}
	}
</style>
