<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { replaceState } from '$app/navigation';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Tabs, { type Tab } from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import CustomerGroupsPanel from '$lib/components/marketing/CustomerGroupsPanel.svelte';
	import {
		fetchMarketingReadiness,
		fetchCustomerGroups,
		marketingReadinessKey,
		marketingCustomerGroupsKey,
		type MarketingApiError
	} from '$lib/marketing/api';
	import type { MarketingReadinessReason } from '$lib/marketing/readiness';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// Marketing home. Overview answers "can I send Marketing email yet, and if not, what is the one thing to
	// fix?" Customer groups is the first saved-audience view; Campaigns and Templates arrive in later slices.
	const queryClient = useQueryClient();

	const readinessQuery = createQuery(() => ({
		queryKey: marketingReadinessKey,
		queryFn: fetchMarketingReadiness,
		staleTime: 60_000,
		// A refusal never changes on its own, so it is not retried.
		retry: (failures, error) => (error as MarketingApiError).status !== 403 && failures < 2
	}));

	// The open view lives in the URL the way Jobber's client tabs do, so it survives a reload and can be
	// linked to. Overview is the default and carries no parameter.
	const marketingTabs: Tab[] = [
		{ value: 'overview', label: 'Overview' },
		{
			value: 'customer-groups',
			label: 'Customer groups',
			onhover: () =>
				void queryClient.prefetchQuery({
					queryKey: marketingCustomerGroupsKey,
					queryFn: fetchCustomerGroups
				})
		}
	];
	const activeTab = $derived.by(() => {
		const asked = page.url.searchParams.get('tab');
		return marketingTabs.some((tab) => tab.value === asked) ? (asked as string) : 'overview';
	});
	function selectTab(next: string) {
		const url = new URL(page.url);
		if (next === 'overview') url.searchParams.delete('tab');
		else url.searchParams.set('tab', next);
		replaceState(url, page.state);
	}

	// Each fix names the screen that owns it; resolve() wants the full route id.
	function fixHref(target: NonNullable<MarketingReadinessReason['fix']>['href']) {
		if (target === '/clients') return resolve('/(app)/clients');
		if (target === '/settings/business-profile') return resolve('/(app)/settings/business-profile');
		return resolve('/(app)/settings/communications/email');
	}

	const refusal = $derived.by(() => {
		const error = readinessQuery.error as MarketingApiError | null;
		if (!error || error.status !== 403) return null;
		return error.reason === 'feature_unavailable' ? 'feature' : 'permission';
	});
</script>

<svelte:head><title>Marketing · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<div class="marketing">
		<PageHeader
			eyebrow="Growth"
			title="Marketing"
			description="Email the customers who have said yes, using the customers and jobs you already have."
		/>

		{#if refusal === 'feature'}
			<EmptyState
				title="Marketing is not part of your plan"
				description="Ask your account owner to add it, and you can email your past customers from here."
			/>
		{:else if refusal === 'permission'}
			<EmptyState
				title="You do not have access to Marketing"
				description="Ask an owner or admin to give you Marketing access."
			/>
		{:else}
			<Tabs tabs={marketingTabs} value={activeTab} onChange={selectTab} label="Marketing views">
				<TabPanel value="overview">
					{#if readinessQuery.isPending}
						<LoadingSkeleton variant="card" rows={3} label="Checking Marketing readiness" />
					{:else if readinessQuery.isError}
						<ErrorState
							title="Marketing could not be checked"
							description="Something went wrong on our side. Try again."
							retry={() => readinessQuery.refetch()}
						/>
					{:else}
						{@const readiness = readinessQuery.data}
						<SectionBlock
							title="Email readiness"
							hint={readiness.ready
								? 'Everything needed to send Marketing email is in place.'
								: 'Finish these before you can send Marketing email. Your drafts and history stay safe.'}
						>
							{#if readiness.ready}
								<p class="marketing__ready" role="status">
									<span class="marketing__badge marketing__badge--ok" aria-hidden="true">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html checkIcon}
									</span>
									You are ready to send Marketing email.
								</p>
							{:else}
								<ul class="marketing__reasons">
									{#each readiness.reasons as reason (reason.code)}
										<li class="marketing__reason">
											<span class="marketing__badge marketing__badge--warn" aria-hidden="true">
												<!-- eslint-disable-next-line svelte/no-at-html-tags -->
												{@html alertIcon}
											</span>
											<div class="marketing__reason-copy">
												<p class="marketing__reason-title">{reason.title}</p>
												<p class="marketing__reason-detail">{reason.detail}</p>
											</div>
											{#if reason.fix}
												<Button variant="secondary" size="small" href={fixHref(reason.fix.href)}>
													{reason.fix.label}
												</Button>
											{/if}
										</li>
									{/each}
								</ul>
							{/if}
						</SectionBlock>
					{/if}
				</TabPanel>
				<TabPanel value="customer-groups">
					<CustomerGroupsPanel />
				</TabPanel>
			</Tabs>
		{/if}
	</div>
</PageContainer>

<style lang="scss">
	.marketing {
		display: grid;
		gap: var(--space-large);
		align-content: start;
	}

	.marketing__ready {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		color: var(--color-text);
	}

	.marketing__reasons {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.marketing__reason {
		display: flex;
		align-items: center;
		gap: var(--space-base);
		flex-wrap: wrap;
	}

	.marketing__reason-copy {
		flex: 1 1 16rem;
		min-width: 0;
	}

	.marketing__reason-title {
		margin: 0;
		font-weight: 600;
		color: var(--color-heading);
	}

	.marketing__reason-detail {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.marketing__badge {
		display: inline-grid;
		place-items: center;
		flex: 0 0 auto;
		width: 2rem;
		height: 2rem;
		border-radius: var(--radius-circle);

		:global(svg) {
			width: 1.125rem;
			height: 1.125rem;
		}

		&--ok {
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
		}

		&--warn {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);
		}
	}
</style>
