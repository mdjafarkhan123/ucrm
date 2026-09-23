<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		declareCampaignCreditRequest,
		fetchCampaignAttributionCandidates,
		fetchCampaignResults
	} from '$lib/marketing/api';
	import {
		marketingCampaignAttributionCandidatesKey,
		marketingCampaignRecipientsKey,
		marketingCampaignResultsKey,
		type MarketingCampaignCreditedWork,
		type MarketingWindowAttributionCandidate
	} from '$lib/marketing/campaign-content';
	import chartIcon from '@tabler/icons/outline/chart-bar.svg?raw';
	import clickIcon from '@tabler/icons/outline/click.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import mailOffIcon from '@tabler/icons/outline/mail-off.svg?raw';

	// The Results tab (blueprint §12-13): four questions -- what was submitted, what was delivered/engaged,
	// what work followed with what revenue, and (browsed separately below) uncredited work this campaign's
	// own last-touch window currently explains.
	// `active` is only true once the parent page's Results tab is actually showing. bits-ui keeps every
	// TabPanel mounted (CSS-hidden), so both queries stay off via `enabled` until then (CLAUDE.md rule 9) --
	// the parent's Tabs `onhover` prefetches the same keys, so the click that follows finds them warm.
	let { campaignId, active = false }: { campaignId: string; active?: boolean } = $props();

	const queryClient = useQueryClient();

	const resultsQuery = createQuery(() => ({
		queryKey: marketingCampaignResultsKey(campaignId),
		queryFn: () => fetchCampaignResults(campaignId),
		enabled: active
	}));
	const candidatesQuery = createQuery(() => ({
		queryKey: marketingCampaignAttributionCandidatesKey(campaignId),
		queryFn: () => fetchCampaignAttributionCandidates(campaignId),
		enabled: active
	}));

	const moneyFormatters: Record<string, Intl.NumberFormat> = {};
	function formatMoney(amountMinor: number, currency: string) {
		let formatter = moneyFormatters[currency];
		if (!formatter) {
			formatter = new Intl.NumberFormat('en-US', { style: 'currency', currency });
			moneyFormatters[currency] = formatter;
		}
		return formatter.format(amountMinor / 100);
	}

	function percent(part: number, whole: number) {
		if (whole <= 0) return '—';
		return `${Math.round((part / whole) * 100)}%`;
	}

	const dateFormat = new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' });

	const creditedColumns: DataTableColumn[] = [
		{ key: 'client', label: 'Customer' },
		{ key: 'work', label: 'Request / Job' },
		{ key: 'source', label: 'Source' },
		{ key: 'credited_at', label: 'Credited' },
		{ key: 'revenue', label: 'Revenue', align: 'end' }
	];

	function workHref(
		item: MarketingCampaignCreditedWork | MarketingWindowAttributionCandidate
	): string | null {
		if (item.request_id) return resolve('/(app)/requests/[id=uuid]', { id: item.request_id });
		if (item.job_id) return resolve('/(app)/jobs/[id=uuid]', { id: item.job_id });
		return null;
	}

	let declaring = $state<string | null>(null);
	let declareError = $state('');

	async function declare(candidate: MarketingWindowAttributionCandidate) {
		if (declaring) return;
		declaring = candidate.request_id ?? candidate.job_id ?? '';
		declareError = '';
		try {
			await declareCampaignCreditRequest(
				campaignId,
				candidate.request_id ? { requestId: candidate.request_id } : { jobId: candidate.job_id! }
			);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: marketingCampaignResultsKey(campaignId) }),
				queryClient.invalidateQueries({
					queryKey: marketingCampaignAttributionCandidatesKey(campaignId)
				}),
				queryClient.invalidateQueries({
					queryKey: marketingCampaignRecipientsKey(campaignId, { statusFilter: '', search: '' }),
					exact: false
				})
			]);
		} catch (cause) {
			declareError = cause instanceof Error ? cause.message : 'That work could not be credited.';
		} finally {
			declaring = null;
		}
	}
</script>

<div class="results-panel">
	{#if resultsQuery.isPending}
		<LoadingSkeleton variant="card" rows={4} label="Loading results" />
	{:else if resultsQuery.isError}
		<ErrorState description="Results could not be loaded." retry={() => resultsQuery.refetch()} />
	{:else}
		{@const results = resultsQuery.data}
		<div class="results-panel__stats">
			<KpiCard
				label="Open rate"
				value={percent(results.opened_count, results.delivered_count)}
				note={`${results.opened_count} of ${results.delivered_count} delivered opened it`}
				icon={chartIcon}
				variant="compact"
			/>
			<KpiCard
				label="Click rate"
				value={percent(results.clicked_count, results.delivered_count)}
				note={`${results.clicked_count} of ${results.delivered_count} delivered clicked`}
				icon={clickIcon}
				variant="compact"
			/>
			<KpiCard
				label="Revenue"
				value={formatMoney(results.revenue_minor, results.currency_code)}
				note={`From ${results.credited_work.length} credited Request${results.credited_work.length === 1 ? '' : 's'}/Job${results.credited_work.length === 1 ? '' : 's'}`}
				icon={cashIcon}
				variant="compact"
				tone="success"
			/>
			<KpiCard
				label="Unsubscribe rate"
				value={percent(results.unsubscribed_count, results.delivered_count)}
				note={`${results.unsubscribed_count} of ${results.delivered_count} delivered unsubscribed`}
				icon={mailOffIcon}
				variant="compact"
			/>
		</div>

		<SectionBlock
			title="What followed"
			hint="Matched {results.matched_count} · eligible {results.eligible_count} · submitted {results.submitted_count} · delivered {results.delivered_count} · bounced {results.bounced_count} · complained {results.complained_count}."
		>
			{#if results.credited_work.length === 0}
				<EmptyState
					icon={cashIcon}
					title="Nothing credited yet"
					description="No Request or Job has been directly credited to this campaign so far."
				/>
			{:else}
				<DataTable
					columns={creditedColumns}
					items={results.credited_work}
					rowId={(item) => item.credit_id}
					caption="Credited work"
				>
					{#snippet row(item: MarketingCampaignCreditedWork)}
						{@const href = workHref(item)}
						<th scope="row">{item.client_name}</th>
						<td
							>{#if href}<a {href}>{item.work_title ?? 'Untitled'}</a>{:else}{item.work_title ??
									'—'}{/if}</td
						>
						<td>{item.source === 'tracked' ? 'Direct' : 'Declared'}</td>
						<td>{dateFormat.format(new Date(item.credited_at))}</td>
						<td class="align-end">{formatMoney(item.revenue_minor, results.currency_code)}</td>
					{/snippet}
				</DataTable>
			{/if}
		</SectionBlock>

		<SectionBlock
			title="Possible matches"
			hint="Customers this campaign delivered to who created a Request, or booked a Job with no Request, within 30 days -- not yet credited to any campaign."
		>
			{#if candidatesQuery.isPending}
				<LoadingSkeleton variant="table" rows={3} label="Loading possible matches" />
			{:else if candidatesQuery.isError}
				<ErrorState
					description="Possible matches could not be loaded."
					retry={() => candidatesQuery.refetch()}
				/>
			{:else if (candidatesQuery.data ?? []).length === 0}
				<EmptyState
					title="No possible matches"
					description="Nothing waiting for review right now."
				/>
			{:else}
				{#if declareError}<p class="results-panel__error" role="alert">{declareError}</p>{/if}
				<ul class="results-panel__candidates">
					{#each candidatesQuery.data ?? [] as candidate (candidate.request_id ?? candidate.job_id)}
						{@const href = workHref(candidate)}
						<li>
							<div class="results-panel__candidate-info">
								<span class="results-panel__candidate-name">{candidate.client_name}</span>
								<span class="results-panel__candidate-work">
									{#if href}<a {href}
											>{candidate.work_title ??
												(candidate.work_kind === 'request' ? 'Request' : 'Job')}</a
										>{:else}{candidate.work_title}{/if}
								</span>
								<span class="results-panel__candidate-meta">
									Delivered {dateFormat.format(new Date(candidate.delivered_at))} · created
									{dateFormat.format(new Date(candidate.work_created_at))}
								</span>
							</div>
							<Button
								size="small"
								variant="secondary"
								loading={declaring === (candidate.request_id ?? candidate.job_id)}
								onclick={() => void declare(candidate)}
							>
								Credit this campaign
							</Button>
						</li>
					{/each}
				</ul>
			{/if}
		</SectionBlock>
	{/if}
</div>

<style lang="scss">
	.results-panel {
		display: grid;
		gap: var(--space-large);
	}

	.results-panel__stats {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		gap: var(--space-base);
	}

	.results-panel__error {
		margin: 0 0 var(--space-base);
		color: var(--color-critical--onSurface);
	}

	.results-panel__candidates {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;

		li {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
			flex-wrap: wrap;
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}
	}

	.results-panel__candidate-info {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.results-panel__candidate-name {
		font-weight: 700;
		color: var(--color-heading);
	}

	.results-panel__candidate-meta {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}
</style>
