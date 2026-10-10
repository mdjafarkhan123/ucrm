<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { page } from '$app/state';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ReadinessDecisionDialog from './ReadinessDecisionDialog.svelte';
	import { canUseJafarPath } from '$lib/jafar/team-access';
	import { organizationReadinessQuery } from '$lib/jafar/organization-experience-queries';
	import { jafarOrganizationReadinessKey } from '$lib/jafar/query-keys';
	import type { ReadinessAreaSummary, ReadinessTabResponse } from '$lib/experience/types';
	import { formatDateTime } from './format';

	// Multi-industry foundation B8 (plan "Access, readiness and launch"): for each real-world area, whether
	// Uplift has signed it off, what is still open and who owns it, and every earlier decision. Paying and
	// Setup never open these on their own; a business that existed before sign-offs shows "Carried over".
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const readinessQuery = createQuery(() => organizationReadinessQuery(organizationId));
	const areas = $derived(readinessQuery.data?.areas ?? []);
	const canDecide = $derived(
		canUseJafarPath(
			{ role: page.data.owner.role, access: page.data.owner.access },
			`/api/jafar/organizations/${organizationId}/readiness`,
			'POST'
		)
	);

	let reviewing = $state<ReadinessAreaSummary | null>(null);
	let idempotencyKey = $state('');
	let actionError = $state('');

	function openDialog(area: ReadinessAreaSummary) {
		idempotencyKey = crypto.randomUUID();
		actionError = '';
		reviewing = area;
	}

	const decide = createMutation(() => ({
		mutationFn: async (input: {
			status: 'ready' | 'not_ready' | 'held';
			checks: { key: string; state: 'open' | 'done' | 'not_applicable' }[];
			reason: string;
			business_message: string | null;
		}) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/readiness`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					...input,
					area_key: reviewing?.key,
					expected_previous_decision_id: reviewing?.current?.id ?? null,
					idempotency_key: idempotencyKey
				})
			});
			const result = (await response.json()) as ReadinessTabResponse & {
				field_errors?: Record<string, string>;
			};
			if (!response.ok) {
				throw new Error(
					Object.values(result.field_errors ?? {})[0] ??
						result.error ??
						'The decision could not be recorded. Try again.'
				);
			}
			return result;
		},
		onSuccess: (result) => {
			queryClient.setQueryData(jafarOrganizationReadinessKey(organizationId), result);
			reviewing = null;
		},
		onError: (error) => {
			actionError = error.message;
		},
		onSettled: () => {
			void queryClient.invalidateQueries({
				queryKey: jafarOrganizationReadinessKey(organizationId)
			});
		}
	}));

	function badgeFor(area: ReadinessAreaSummary): {
		status: 'success' | 'warning' | 'critical' | 'inactive';
		text: string;
	} {
		const view = area.business_view;
		if (view.open) {
			return {
				status: 'success',
				text: area.current?.source === 'carried_over' ? 'Open · carried over' : 'Open'
			};
		}
		if (view.state === 'held') return { status: 'critical', text: 'On hold' };
		if (view.state === 'not_started') return { status: 'inactive', text: 'Not reviewed' };
		return { status: 'warning', text: 'Waiting' };
	}

	const STATE_LABELS = { open: 'To do', done: 'Done', not_applicable: 'Not needed' } as const;
	const STATUS_LABELS = { ready: 'Opened', not_ready: 'Not ready', held: 'On hold' } as const;
</script>

<SectionBlock title="Ready for customers" icon={shieldCheckIcon}>
	{#if readinessQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading readiness" />
	{:else if readinessQuery.isError && !readinessQuery.data}
		<ErrorState
			title="Readiness could not be loaded"
			description={readinessQuery.error.message}
			retry={() => readinessQuery.refetch()}
		/>
	{:else}
		<p class="readiness__lead">
			Paying and Setup let a business prepare privately. Each area below stays closed until Uplift
			signs it off; a closed area tells the business exactly what is left and who does it.
		</p>
		<ul class="readiness__areas">
			{#each areas as area (area.key)}
				{@const badge = badgeFor(area)}
				<li class="readiness__area">
					<div class="readiness__top">
						<h3>{area.label}</h3>
						<Badge status={badge.status}>{badge.text}</Badge>
						{#if canDecide}
							<Button
								class="readiness__review"
								variant="secondary"
								variation="subtle"
								size="small"
								onclick={() => openDialog(area)}>Review</Button
							>
						{/if}
					</div>
					<p class="readiness__sentence">{area.business_view.sentence}</p>
					{#if area.current && area.current.source === 'review'}
						<p class="readiness__meta">
							{STATUS_LABELS[area.current.status]} · {formatDateTime(area.current.decided_at)} · {area
								.current.actor_email}
						</p>
						<ul class="readiness__checks">
							{#each area.checks as check (check.key)}
								{@const state =
									area.current.checks.find((entry) => entry.key === check.key)?.state ?? 'open'}
								<li class:readiness__check--done={state !== 'open'}>
									<span>{STATE_LABELS[state]}</span>
									{check.task}
								</li>
							{/each}
						</ul>
					{:else if area.current}
						<p class="readiness__meta">
							This business was already working before sign-offs existed. Nothing was reviewed.
						</p>
					{/if}
					{#if area.history.length > 1}
						<details class="readiness__history">
							<summary>History ({area.history.length})</summary>
							<ol>
								{#each area.history as entry (entry.id)}
									<li>
										<strong>{STATUS_LABELS[entry.status]}</strong> ·
										{formatDateTime(entry.decided_at)} · {entry.actor_email}
										<p>{entry.reason}</p>
									</li>
								{/each}
							</ol>
						</details>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</SectionBlock>

{#if reviewing}
	<ReadinessDecisionDialog
		area={reviewing}
		pending={decide.isPending}
		error={actionError}
		onSubmit={(input) => decide.mutate(input)}
		onClose={() => (reviewing = null)}
	/>
{/if}

<style lang="scss">
	.readiness {
		&__lead,
		&__sentence,
		&__meta {
			margin: 0;
		}

		&__lead {
			color: var(--color-text--secondary);
		}

		&__areas {
			display: grid;
			margin: var(--space-base) 0 0;
			padding: 0;
			list-style: none;
		}

		&__area {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-base) 0;
			border-bottom: var(--border-base) solid var(--color-border);

			&:first-child {
				padding-top: 0;
			}

			&:last-child {
				padding-bottom: 0;
				border-bottom: 0;
			}
		}

		&__top {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
			}

			:global(.readiness__review) {
				margin-left: auto;
			}
		}

		&__sentence {
			color: var(--color-heading);
			overflow-wrap: anywhere;
		}

		&__meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__checks {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;
			padding: 0;
			list-style: none;

			li {
				display: flex;
				gap: var(--space-small);
				color: var(--color-heading);
			}

			span {
				flex: none;
				min-width: 5rem;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}

		&__check--done {
			color: var(--color-text--secondary);
		}

		&__history {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			summary {
				cursor: pointer;
			}

			ol {
				display: grid;
				gap: var(--space-small);
				margin: var(--space-small) 0 0;
				padding-left: var(--space-base);
			}

			p {
				margin: 0;
			}
		}
	}
</style>
