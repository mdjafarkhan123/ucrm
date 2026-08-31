<script lang="ts">
	import { createQuery, createInfiniteQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import FilterBar from '$lib/components/data-display/FilterBar.svelte';
	import FilterField from '$lib/components/data-display/FilterField.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		automationSettingsKey,
		fetchAutomationSettings,
		type AutomationLimit
	} from '$lib/settings/automation';
	import {
		automationRecipesKey,
		fetchAutomationRecipes,
		type RecipeListPage,
		type RecipeStatus,
		type RecipeSummary,
		type RecipeSource
	} from '$lib/settings/automation-recipes';
	import { triggerLabel } from '$lib/automation/catalog';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import robotOffIcon from '@tabler/icons/outline/robot-off.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import boltIcon from '@tabler/icons/outline/bolt.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import filePencilIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';

	const query = createQuery(() => ({
		queryKey: automationSettingsKey,
		queryFn: fetchAutomationSettings
	}));

	const canView = $derived(query.data?.status === 'ok');

	let search = $state('');
	let debouncedSearch = $state('');
	let status = $state<RecipeStatus | ''>('');
	let source = $state<RecipeSource | ''>('');

	$effect(() => {
		const value = search;
		const handle = setTimeout(() => (debouncedSearch = value), 300);
		return () => clearTimeout(handle);
	});

	const filters = $derived({ search: debouncedSearch, status, source });
	const hasActiveFilters = $derived(status !== '' || source !== '' || debouncedSearch !== '');

	// The list stays off until the viewer actually has read access, so a denied/suspended shell never fires
	// a doomed request. Enrollments and lifecycle actions arrive in 6D/6C-3; this slice reads only.
	const recipesQuery = createInfiniteQuery(() => ({
		queryKey: automationRecipesKey(filters),
		queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
			fetchAutomationRecipes(filters, pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: RecipeListPage) => lastPage.next_cursor ?? undefined,
		enabled: canView
	}));

	const recipes = $derived(recipesQuery.data?.pages.flatMap((page) => page.recipes) ?? []);
	// Counts ride the first page only; keep the first page's copy while paging.
	const counts = $derived(
		recipesQuery.data?.pages[0]?.counts ?? { active: 0, paused: 0, draft: 0 }
	);

	function clearFilters() {
		status = '';
		source = '';
	}

	// The one entitlement the strip is allowed to present — active-recipe headroom. The other six limits are
	// safety rules, not purchasable allowances, so the contract keeps them off this strip.
	function activeRecipesLabel(limit: AutomationLimit): string {
		if (limit.is_unlimited || limit.state === 'unlimited') return 'Unlimited active automations';
		if (limit.state === 'numeric' && limit.value !== null)
			return `${counts.active} of ${limit.value} active automations in use`;
		return 'Active automations not included';
	}

	const statusBadge: Record<
		RecipeStatus,
		{ tone: 'success' | 'warning' | 'informative' | 'inactive'; label: string }
	> = {
		active: { tone: 'success', label: 'Active' },
		paused: { tone: 'warning', label: 'Paused' },
		draft: { tone: 'informative', label: 'Draft' },
		archived: { tone: 'inactive', label: 'Archived' }
	};

	function lastActivity(value: string) {
		return new Date(value).toLocaleDateString(undefined, {
			year: 'numeric',
			month: 'short',
			day: 'numeric'
		});
	}

	const columns: DataTableColumn[] = [
		{ key: 'name', label: 'Name' },
		{ key: 'source', label: 'Source' },
		{ key: 'trigger', label: 'Trigger' },
		{ key: 'status', label: 'Status' },
		{ key: 'enrollments', label: 'Active', align: 'end' },
		{ key: 'activity', label: 'Last activity' }
	];
</script>

<svelte:head><title>Automation · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="fill">
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Automation' }]}
	/>

	{#if query.isPending}
		<LoadingSkeleton variant="card" rows={2} />
	{:else if query.isError}
		<ErrorState description="Automation could not be loaded." retry={() => query.refetch()} />
	{:else if query.data.status === 'denied'}
		{#if query.data.reason === 'not_included'}
			<EmptyState
				icon={robotOffIcon}
				title="Automation isn’t part of your plan"
				description="Automation isn’t included in your current plan. Talk to us if you’d like to add it."
			/>
		{:else}
			<EmptyState
				icon={lockIcon}
				title="You don’t have access to Automation"
				description="Ask an owner or administrator if you need to work with automations."
			/>
		{/if}
	{:else}
		{@const access = query.data.access}
		{@const suspended = access.authority_state === 'security_suspended'}
		{@const disabled = access.authority_state === 'operationally_disabled'}

		<div class="automation-settings">
			<PageHeader
				eyebrow="Automations"
				title="Automation"
				description="Set up automations that follow up with customers for you, without lifting a finger."
			>
				{#snippet actions()}
					{#if access.can_manage}
						<Button variant="primary" href={resolve('/(app)/settings/automation/new')}
							>New automation</Button
						>
					{/if}
				{/snippet}
			</PageHeader>

			{#if suspended || disabled}
				<p
					class="automation-settings__banner"
					class:automation-settings__banner--suspended={suspended}
					role="status"
				>
					<!-- eslint-disable svelte/no-at-html-tags -->
					<span class="automation-settings__banner-icon" aria-hidden="true"
						>{@html alertTriangleIcon}</span
					>
					<!-- eslint-enable svelte/no-at-html-tags -->
					<span>
						{#if suspended}
							Automation is suspended for your business. You can still read your automations, but
							nothing runs and nothing can be changed.
						{:else}
							Automation is temporarily unavailable for your business. You can still read your
							automations, but nothing runs right now.
						{/if}
						{#if access.authority_reason}<br /><span class="automation-settings__banner-reason"
								>Reason: {access.authority_reason}</span
							>{/if}
					</span>
				</p>
			{/if}

			<div class="automation-settings__strip">
				<span class="automation-settings__strip-icon" aria-hidden="true">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html boltIcon}
				</span>
				<span>{activeRecipesLabel(access.limits.automation_active_recipes)}</span>
			</div>

			<div class="automation-settings__cards">
				<KpiCard
					variant="compact"
					tone="success"
					label="Active"
					value={String(counts.active)}
					note="Running now"
					icon={circleCheckIcon}
				/>
				<KpiCard
					variant="compact"
					tone="informative"
					label="Paused & drafts"
					value={String(counts.paused + counts.draft)}
					note="Not running yet"
					icon={filePencilIcon}
				/>
				<KpiCard
					variant="compact"
					tone="default"
					label="Needs attention"
					value="0"
					note="Nothing to review"
					icon={bellIcon}
				/>
			</div>

			<SectionBlock title="Your automations" icon={robotIcon} level={2}>
				<div class="automation-settings__toolbar">
					<div class="automation-settings__search">
						<SearchInput
							id="automation-search"
							bind:value={search}
							placeholder="Search automations"
						/>
					</div>
					<FilterBar onClear={hasActiveFilters ? clearFilters : undefined}>
						<FilterField id="automation-status-filter" label="Status">
							<Select
								id="automation-status-filter"
								value={status}
								onchange={(value) => (status = value as RecipeStatus | '')}
								options={[
									{ value: '', label: 'All statuses' },
									{ value: 'active', label: 'Active' },
									{ value: 'paused', label: 'Paused' },
									{ value: 'draft', label: 'Draft' },
									{ value: 'archived', label: 'Archived' }
								]}
							/>
						</FilterField>
						<FilterField id="automation-source-filter" label="Source">
							<Select
								id="automation-source-filter"
								value={source}
								onchange={(value) => (source = value as RecipeSource | '')}
								options={[
									{ value: '', label: 'All sources' },
									{ value: 'preset', label: 'Preset' },
									{ value: 'custom', label: 'Custom' }
								]}
							/>
						</FilterField>
					</FilterBar>
				</div>

				{#if recipesQuery.isPending}
					<LoadingSkeleton variant="table" label="Loading automations" rows={4} />
				{:else if recipesQuery.isError}
					<ErrorState
						description="Automations could not be loaded. Refresh and try again."
						retry={() => recipesQuery.refetch()}
					/>
				{:else if recipes.length === 0}
					<EmptyState
						icon={robotIcon}
						title={hasActiveFilters ? 'No matching automations' : 'No automations yet'}
						description={hasActiveFilters
							? 'Try a different search term or clear your filters.'
							: 'Start from a ready-made follow-up, or build your own from scratch. You can change anything before it goes live.'}
					>
						{#snippet action()}
							{#if !hasActiveFilters && access.can_manage}
								<div class="automation-settings__empty-actions">
									<Button variant="primary" href={resolve('/(app)/settings/automation/new')}
										>Browse presets</Button
									>
									<Button
										variant="secondary"
										href={`${resolve('/(app)/settings/automation/new')}?mode=scratch`}
										>Build from scratch</Button
									>
								</div>
							{/if}
						{/snippet}
					</EmptyState>
				{:else}
					<DataTable {columns} items={recipes} rowId={(recipe) => recipe.id} caption="Automations">
						{#snippet row(recipe: RecipeSummary)}
							<th scope="row">
								<a
									class="automation-table__name"
									href={resolve('/(app)/settings/automation/[id]', { id: recipe.id })}
								>
									{recipe.name}
								</a>
							</th>
							<td><Badge>{recipe.source === 'preset' ? 'Preset' : 'Custom'}</Badge></td>
							<td>{triggerLabel(recipe.trigger_key)}</td>
							<td>
								<StatusBadge status={statusBadge[recipe.status].tone}
									>{statusBadge[recipe.status].label}</StatusBadge
								>
							</td>
							<td class="automation-table__count">{recipe.active_enrollments}</td>
							<td>{lastActivity(recipe.last_activity_at)}</td>
						{/snippet}
						{#snippet footer()}
							<ListLoadMore
								hasNextPage={recipesQuery.hasNextPage}
								isFetchingNextPage={recipesQuery.isFetchingNextPage}
								onLoadMore={() => recipesQuery.fetchNextPage()}
							/>
						{/snippet}
					</DataTable>
				{/if}
			</SectionBlock>
		</div>
	{/if}
</PageContainer>

<style lang="scss">
	.automation-settings {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__banner {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
		}
		&__banner--suspended {
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}
		&__banner-icon {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			margin-top: var(--space-smallest);
		}
		&__banner-icon :global(svg) {
			width: 18px;
			height: 18px;
		}
		&__banner-reason {
			font-size: var(--typography--fontSize-small);
		}

		&__strip {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		&__strip-icon {
			display: grid;
			place-items: center;
			color: var(--color-interactive);
		}
		&__strip-icon :global(svg) {
			width: 18px;
			height: 18px;
		}

		&__cards {
			display: grid;
			grid-template-columns: repeat(3, 1fr);
			gap: var(--space-base);
		}

		&__toolbar {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
			margin-bottom: var(--space-base);
		}
		&__search {
			flex: 1 1 240px;
		}

		&__empty-actions {
			display: flex;
			flex-wrap: wrap;
			justify-content: center;
			gap: var(--space-small);
		}

		@media (max-width: 720px) {
			&__cards {
				grid-template-columns: 1fr;
			}
		}
	}

	.automation-table__name {
		color: var(--color-heading);
		font-weight: 600;
		text-decoration: none;

		&:hover,
		&:focus-visible {
			color: var(--color-interactive);
			text-decoration: underline;
		}
	}
	.automation-table__count {
		text-align: end;
		font-variant-numeric: tabular-nums;
	}
</style>
