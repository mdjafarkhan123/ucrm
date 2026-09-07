<script lang="ts">
	import { createQuery, type CreateQueryResult } from '@tanstack/svelte-query';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import type {
		EffectiveAccess,
		TeamResponse,
		HistoryResponse,
		OperationListResponse,
		OperationAttempt
	} from './types';

	let {
		access,
		teamQuery,
		historyQuery,
		organizationOperationsQuery,
		applicationOperationsQuery,
		attentionOperations,
		selectTab
	}: {
		access: EffectiveAccess;
		teamQuery: CreateQueryResult<TeamResponse, Error>;
		historyQuery: CreateQueryResult<HistoryResponse, Error>;
		organizationOperationsQuery: CreateQueryResult<OperationListResponse, Error>;
		applicationOperationsQuery: CreateQueryResult<OperationListResponse, Error>;
		attentionOperations: OperationAttempt[];
		selectTab: (tab: string) => void;
	} = $props();

	// These are the existing Communications cache entries and full API responses.
	// Overview reads only health signals; the detailed controls stay in their workspace.
	const pauseQuery = createQuery(() => ({
		queryKey: ['jafar', 'organizations', access.organization.id, 'email-sending-pause'],
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${access.organization.id}/communications/sending-pause`
			);
			if (!response.ok) throw new Error('Email sending status could not be loaded.');
			return (await response.json()) as {
				platform_paused: boolean;
				organization_pause: { id: string } | null;
			};
		},
		staleTime: 15_000
	}));
	const reputationQuery = createQuery(() => ({
		queryKey: ['jafar', 'organizations', access.organization.id, 'email-reputation'],
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${access.organization.id}/communications/reputation`
			);
			if (!response.ok) throw new Error('Email reputation could not be loaded.');
			return (await response.json()) as {
				reputation: {
					reputation_pause: { id: string } | null;
					state: { worst_status: 'ok' | 'warn' | 'pause' } | null;
				};
			};
		},
		staleTime: 30_000
	}));
	const domainsQuery = createQuery(() => ({
		queryKey: ['jafar', 'organizations', access.organization.id, 'email-domains'],
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${access.organization.id}/communications/domains`
			);
			if (!response.ok) throw new Error('Email domains could not be loaded.');
			return (await response.json()) as {
				domains?: { lifecycle_state: string; provider_cleanup_error: string | null }[];
			};
		},
		staleTime: 30_000
	}));
	const providersPending = $derived(
		pauseQuery.isPending || reputationQuery.isPending || domainsQuery.isPending
	);
	const providersError = $derived(
		pauseQuery.isError || reputationQuery.isError || domainsQuery.isError
	);
	const providersAttention = $derived(
		Boolean(
			pauseQuery.data?.platform_paused ||
			pauseQuery.data?.organization_pause ||
			reputationQuery.data?.reputation.reputation_pause ||
			['warn', 'pause'].includes(reputationQuery.data?.reputation.state?.worst_status ?? '') ||
			domainsQuery.data?.domains?.some(
				(domain) =>
					domain.provider_cleanup_error ||
					['failed', 'needs_attention'].includes(domain.lifecycle_state)
			)
		)
	);
	const recoveryPending = $derived(
		historyQuery.isPending ||
			organizationOperationsQuery.isPending ||
			(historyQuery.data?.applicationId && applicationOperationsQuery.isPending)
	);
	const recoveryError = $derived(
		historyQuery.isError ||
			organizationOperationsQuery.isError ||
			(historyQuery.data?.applicationId && applicationOperationsQuery.isError)
	);
</script>

<SectionBlock title="Health and open issues">
	<div class="overview-attention" aria-live="polite">
		<div class="overview-attention__row">
			<div>
				<h3>Administrator access</h3>
				<p>
					{teamQuery.isPending
						? 'Checking administrator readiness…'
						: teamQuery.isError
							? 'Administrator readiness could not be loaded.'
							: teamQuery.data?.has_administrator
								? 'An owner or administrator is available.'
								: 'No owner or administrator is available. Review recovery with the contractor.'}
				</p>
			</div>
			<Button variant="secondary" onclick={() => selectTab('team')}>Review team</Button>
		</div>
		<div class="overview-attention__row">
			<div>
				<h3>Provider readiness</h3>
				<p>
					{providersPending
						? 'Checking email sending, reputation, and domains…'
						: providersError
							? 'Some provider checks could not be loaded. Open Communications to retry.'
							: providersAttention
								? 'Email sending or domain health needs attention. Review Communications before sending.'
								: 'No email pause, reputation warning, or domain failure reported.'}
				</p>
			</div>
			<Button variant="secondary" onclick={() => selectTab('communications')}
				>Review communications</Button
			>
		</div>
		<div class="overview-attention__row">
			<div>
				<h3>Recovery work</h3>
				<p>
					{recoveryPending
						? 'Checking open recovery work…'
						: recoveryError
							? 'Some recovery checks could not be loaded. Open Activity to retry.'
							: attentionOperations.length
								? `${attentionOperations.length} open recovery item${attentionOperations.length === 1 ? '' : 's'} need review.`
								: 'No open recovery items.'}
				</p>
			</div>
			<Button variant="secondary" onclick={() => selectTab('activity')}>Review activity</Button>
		</div>
	</div>
</SectionBlock>

<style lang="scss">
	.overview-attention {
		display: grid;
		gap: var(--space-base);
	}
	.overview-attention__row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.overview-attention__row + .overview-attention__row {
		border-top: var(--border-base) solid var(--color-border);
		padding-top: var(--space-base);
	}
	.overview-attention__row > div {
		min-width: 0;
	}
	h3 {
		margin: 0;
		font-size: var(--typography--fontSize-large);
		color: var(--color-heading);
	}
	p {
		margin: var(--space-small) 0 0;
		color: var(--color-text--secondary);
	}
	@media (max-width: 767px) {
		.overview-attention__row {
			flex-direction: column;
			align-items: flex-start;
		}
	}
</style>
