<script lang="ts">
	import { createQuery, createInfiniteQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SettingsPageHeader from '$lib/components/settings/SettingsPageHeader.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import RecordListCard from '$lib/components/data-display/RecordListCard.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import FilterChip from '$lib/components/ui/FilterChip.svelte';
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
	import { triggerLabel, triggerSubject, type CatalogSubject } from '$lib/automation/catalog';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import robotOffIcon from '@tabler/icons/outline/robot-off.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import boltIcon from '@tabler/icons/outline/bolt.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import filePencilIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import calendarEventIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import circleDashedIcon from '@tabler/icons/outline/circle-dashed.svg?raw';
	import stackIcon from '@tabler/icons/outline/stack-2.svg?raw';

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

	// The strip's meter: ten segments standing for the active-automation allowance, filled in proportion to
	// what is in use. Only drawn for a numeric allowance, since "unlimited" has no top to fill towards.
	function meterSegments(limit: AutomationLimit): number | null {
		if (limit.is_unlimited || limit.state !== 'numeric' || !limit.value) return null;
		return Math.min(10, Math.ceil((counts.active / limit.value) * 10));
	}

	// Each trigger carries the colour of the record it starts from, the way the rest of the app does.
	const subjectIcon: Record<CatalogSubject, { icon: string; tone: string }> = {
		website_inquiry: { icon: inboxIcon, tone: 'request' },
		appointment: { icon: calendarEventIcon, tone: 'job' },
		quote: { icon: fileTextIcon, tone: 'quote' },
		job: { icon: hammerIcon, tone: 'job' },
		invoice: { icon: receiptIcon, tone: 'invoice' }
	};

	function triggerSubjectIcon(key: string | null) {
		const subject = triggerSubject(key);
		return subject ? subjectIcon[subject] : null;
	}

	const statusBadge: Record<
		RecipeStatus,
		{ tone: 'success' | 'warning' | 'informative' | 'inactive'; label: string }
	> = {
		active: { tone: 'success', label: 'Active' },
		paused: { tone: 'warning', label: 'Paused' },
		draft: { tone: 'warning', label: 'Draft' },
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

<!-- eslint-disable svelte/no-at-html-tags -->

<svelte:head><title>Automation · Settings · Contractor CRM</title></svelte:head>

<PageContainer variant="open">
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
		{@const segments = meterSegments(access.limits.automation_active_recipes)}

		<div class="automation-settings">
			<SettingsPageHeader
				title="Automation"
				description="Set up automations that follow up with customers for you, without lifting a finger."
				icon={robotIcon}
				tone="warning"
			>
				{#snippet actions()}
					{#if access.can_manage}
						<Button variant="primary" href={resolve('/(app)/settings/automation/new')}>
							<span class="automation-settings__button-icon" aria-hidden="true"
								>{@html plusIcon}</span
							>
							New automation
						</Button>
					{/if}
				{/snippet}
			</SettingsPageHeader>

			{#if suspended || disabled}
				<p
					class="automation-settings__banner"
					class:automation-settings__banner--suspended={suspended}
					role="status"
				>
					<span class="automation-settings__banner-icon" aria-hidden="true"
						>{@html alertTriangleIcon}</span
					>
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
					{@html boltIcon}
				</span>
				<span class="automation-settings__strip-label"
					>{activeRecipesLabel(access.limits.automation_active_recipes)}</span
				>
				{#if segments !== null}
					<span class="automation-settings__meter" aria-hidden="true">
						{#each [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] as index (index)}
							<span class:automation-settings__meter-segment--on={index < segments}></span>
						{/each}
					</span>
				{/if}
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
					tone="warning"
					label="Needs attention"
					value="0"
					note="Nothing to review"
					icon={bellIcon}
				/>
			</div>

			<RecordListCard
				title="Your automations"
				padBody={recipesQuery.isPending || recipesQuery.isError || recipes.length === 0}
			>
				{#snippet headingIcon()}
					<span class="automation-settings__list-icon">{@html robotIcon}</span>
				{/snippet}
				{#snippet toolbar()}
					<div class="automation-settings__search">
						<SearchInput
							id="automation-search"
							bind:value={search}
							placeholder="Search automations"
							size="compact"
						/>
					</div>
					<FilterChip
						id="automation-status-filter"
						variant="toolbar"
						icon={circleDashedIcon}
						label="Status"
						value={status}
						options={[
							{ value: '', label: 'All statuses' },
							{ value: 'active', label: 'Active' },
							{ value: 'paused', label: 'Paused' },
							{ value: 'draft', label: 'Draft' },
							{ value: 'archived', label: 'Archived' }
						]}
						restValue=""
						onchange={(value) => (status = value as RecipeStatus | '')}
					/>
					<FilterChip
						id="automation-source-filter"
						variant="toolbar"
						icon={stackIcon}
						label="Source"
						value={source}
						options={[
							{ value: '', label: 'All sources' },
							{ value: 'preset', label: 'Preset' },
							{ value: 'custom', label: 'Custom' }
						]}
						restValue=""
						onchange={(value) => (source = value as RecipeSource | '')}
					/>
					{#if hasActiveFilters}
						<Button variant="tertiary" size="small" onclick={clearFilters}>Clear filters</Button>
					{/if}
				{/snippet}

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
					<DataTable
						variant="card"
						{columns}
						items={recipes}
						rowId={(recipe) => recipe.id}
						caption="Automations"
					>
						{#snippet row(recipe: RecipeSummary)}
							{@const trigger = triggerSubjectIcon(recipe.trigger_key)}
							<th scope="row">
								<a
									class="automation-table__name"
									href={resolve('/(app)/settings/automation/[id]', { id: recipe.id })}
								>
									{recipe.name}
								</a>
							</th>
							<td><Badge>{recipe.source === 'preset' ? 'Preset' : 'Custom'}</Badge></td>
							<td>
								<span class="automation-table__trigger">
									{#if trigger}
										<span
											class={`automation-table__trigger-icon automation-table__trigger-icon--${trigger.tone}`}
											aria-hidden="true">{@html trigger.icon}</span
										>
									{/if}
									{triggerLabel(recipe.trigger_key)}
								</span>
							</td>
							<td>
								<StatusBadge status={statusBadge[recipe.status].tone} size="compact"
									>{statusBadge[recipe.status].label}</StatusBadge
								>
							</td>
							<td class="automation-table__count">{recipe.active_enrollments}</td>
							<td>{lastActivity(recipe.last_activity_at)}</td>
						{/snippet}
						{#snippet footer()}
							<ListLoadMore
 count={recipes.length} recordName="recipes" recordColor="inactive"
								variant="card"
								hasNextPage={recipesQuery.hasNextPage}
								isFetchingNextPage={recipesQuery.isFetchingNextPage}
								onLoadMore={() => recipesQuery.fetchNextPage()}
							/>
						{/snippet}
					</DataTable>
				{/if}
			</RecordListCard>
		</div>
	{/if}
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

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

		&__button-icon {
			display: inline-flex;

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__strip {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: 16px 20px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-heading);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}
		&__strip-label {
			flex: 1;
		}
		&__strip-icon {
			display: grid;
			place-items: center;
			width: 36px;
			height: 36px;
			border-radius: 10px;
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
		}
		&__strip-icon :global(svg) {
			width: 18px;
			height: 18px;
		}
		&__meter {
			display: flex;
			gap: 6px;

			span {
				width: 24px;
				height: 6px;
				border-radius: 3px;
				background: var(--color-surface--background);
			}
			.automation-settings__meter-segment--on {
				background: var(--color-interactive);
			}
		}

		&__cards {
			display: grid;
			grid-template-columns: repeat(3, 1fr);
			gap: var(--space-base);
		}

		&__search {
			width: 260px;
			max-width: 100%;
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
	.automation-table__trigger {
		display: inline-flex;
		align-items: center;
		gap: 10px;
	}
	.automation-settings__list-icon {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
	.automation-table__trigger-icon {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
		&--request {
			color: var(--color-request);
		}
		&--quote {
			color: var(--color-quote);
		}
		&--job {
			color: var(--color-job);
		}
		&--invoice {
			color: var(--color-invoice);
		}
	}
	td.automation-table__count {
		text-align: end;
		font-variant-numeric: tabular-nums;
	}
</style>
