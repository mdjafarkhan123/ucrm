<script lang="ts">
	import { resolve } from '$app/paths';
	import { createInfiniteQuery } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SearchInput from '$lib/components/ui/SearchInput.svelte';
	import Select from '$lib/components/ui/Select.svelte';

	type LifecycleStatus = 'active' | 'suspended' | 'pending_setup' | 'pending_closure' | 'closed';
	type AttentionReason =
		| 'access_overdue'
		| 'expiring_soon'
		| 'administrator_missing'
		| 'administrator_ownership_unclear'
		| 'setup_or_recovery_failed'
		| 'legacy_review';
	type Organization = {
		id: string;
		name: string;
		slug: string;
		lifecycle_status: LifecycleStatus;
		created_at: string;
		updated_at: string;
		member_count: number;
		attention_reasons: AttentionReason[];
	};
	type DirectoryTotals = {
		all: number;
		active: number;
		suspended: number;
		pending_setup: number;
		matching: number;
		attention: Record<AttentionReason, number>;
	};
	type DirectoryPage = {
		organizations: Organization[];
		next_cursor: string | null;
		totals: DirectoryTotals;
		error?: string;
	};

	// Urgency order matches the database function's own ordering, so a badge list here reads the
	// same way the attention-reason filter counts do.
	const attentionMeta: Record<AttentionReason, { label: string; tone: 'critical' | 'warning' }> = {
		access_overdue: { label: 'Access overdue', tone: 'critical' },
		administrator_missing: { label: 'No administrator', tone: 'critical' },
		administrator_ownership_unclear: { label: 'Multiple owners', tone: 'warning' },
		setup_or_recovery_failed: { label: 'Setup or recovery issue', tone: 'critical' },
		expiring_soon: { label: 'Expiring soon', tone: 'warning' },
		legacy_review: { label: 'Needs review', tone: 'warning' }
	};
	const attentionReasonOrder = Object.keys(attentionMeta) as AttentionReason[];

	const emptyTotals: DirectoryTotals = {
		all: 0,
		active: 0,
		suspended: 0,
		pending_setup: 0,
		matching: 0,
		attention: {
			access_overdue: 0,
			expiring_soon: 0,
			administrator_missing: 0,
			administrator_ownership_unclear: 0,
			setup_or_recovery_failed: 0,
			legacy_review: 0
		}
	};

	let searchInput = $state('');
	let debouncedSearch = $state('');
	let attentionFilter = $state<'' | AttentionReason>('');

	$effect(() => {
		const value = searchInput;
		const timeout = setTimeout(() => {
			debouncedSearch = value;
		}, 300);
		return () => clearTimeout(timeout);
	});

	const organizations = createInfiniteQuery<DirectoryPage>(() => ({
		queryKey: ['jafar', 'organizations', debouncedSearch.trim(), attentionFilter],
		queryFn: async ({ pageParam }) => {
			const params = new URLSearchParams();
			if (debouncedSearch.trim()) params.set('search', debouncedSearch.trim());
			if (attentionFilter) params.set('attention_reason', attentionFilter);
			if (typeof pageParam === 'string') params.set('cursor', pageParam);
			const response = await fetch(`/api/jafar/organizations?${params.toString()}`);
			const result = (await response.json()) as DirectoryPage;
			if (!response.ok) throw new Error(result.error ?? 'Organizations could not be loaded.');
			return result;
		},
		initialPageParam: null as string | null,
		getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined
	}));

	const pages = $derived(organizations.data?.pages ?? []);
	const organizationList = $derived(pages.flatMap((page) => page.organizations));
	const totals = $derived(pages[0]?.totals ?? emptyTotals);

	const attentionOptions = $derived([
		{ value: '', label: 'All organizations' },
		...attentionReasonOrder.map((reason) => ({
			value: reason,
			label: `${attentionMeta[reason].label} (${totals.attention[reason]})`
		}))
	]);

	const filtersApplied = $derived(Boolean(searchInput || attentionFilter));

	function clearFilters() {
		searchInput = '';
		attentionFilter = '';
	}

	function lifecycleLabel(lifecycle: LifecycleStatus) {
		if (lifecycle === 'active') return 'Active';
		if (lifecycle === 'pending_setup') return 'Needs review';
		if (lifecycle === 'pending_closure') return 'Closing';
		if (lifecycle === 'closed') return 'Closed';
		return 'Suspended';
	}

	function lifecycleTone(lifecycle: LifecycleStatus): 'success' | 'critical' | 'warning' {
		if (lifecycle === 'active') return 'success';
		if (lifecycle === 'pending_setup') return 'warning';
		return 'critical';
	}

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
	}
</script>

<svelte:head><title>Organizations · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="organization-directory">
	<header class="organization-directory__header">
		<div>
			<p class="organization-directory__eyebrow">Platform owner</p>
			<h1>Organizations</h1>
			<p class="organization-directory__description">
				Review every contractor organization on the platform.
			</p>
		</div>
	</header>

	<section class="organization-directory__summary" aria-label="Organization summary">
		<KpiCard
			label="Organizations"
			value={String(totals.all)}
			note="All organizations"
			icon={buildingIcon}
			variant="compact"
		/>
		<KpiCard
			label="Active"
			value={String(totals.active)}
			note="Contractor access allowed"
			icon={checkIcon}
			tone="success"
			variant="compact"
		/>
		<KpiCard
			label="Suspended"
			value={String(totals.suspended)}
			note="Contractor access blocked"
			icon={pauseIcon}
			tone="critical"
			variant="compact"
		/>
		<KpiCard
			label="Needs review"
			value={String(totals.pending_setup)}
			note="Legacy organizations pending one-time review"
			icon={alertIcon}
			tone="warning"
			variant="compact"
		/>
	</section>

	<section class="organization-directory__filters" aria-label="Organization filters">
		<div class="organization-directory__filter-field organization-directory__filter-field--search">
			<label for="organization-search">Search organizations</label>
			<SearchInput
				id="organization-search"
				bind:value={searchInput}
				placeholder="Search by name, slug, or administrator email"
				ariaLabel="Search organizations"
			/>
		</div>
		<div class="organization-directory__filter-field">
			<label for="organization-attention">Needs attention</label>
			<Select
				id="organization-attention"
				bind:value={attentionFilter}
				options={attentionOptions}
				ariaLabel="Filter organizations by attention reason"
			/>
		</div>
		<Button
			type="button"
			variant="secondary"
			variation="destructive"
			disabled={!filtersApplied}
			onclick={clearFilters}>Clear filters</Button
		>
	</section>

	<div class="organization-directory__list-meta" aria-live="polite">
		<span><strong>{organizationList.length}</strong> of {totals.matching} organizations shown</span>
	</div>

	<section class="organization-directory__table-panel" aria-labelledby="organization-list-title">
		<h2 id="organization-list-title" class="organization-directory__sr-only">
			Organization directory
		</h2>
		{#if organizations.isPending}
			<div class="organization-directory__state">
				<LoadingSkeleton variant="table" rows={5} label="Loading organizations" />
			</div>
		{:else if organizations.isError}
			<div class="organization-directory__state">
				<ErrorState
					title="Organizations could not be loaded"
					description={organizations.error.message}
					retry={() => organizations.refetch()}
				/>
			</div>
		{:else if organizationList.length === 0}
			<div class="organization-directory__state">
				<EmptyState
					title={totals.all === 0 ? 'No organizations yet' : 'No matching organizations'}
					description={totals.all === 0
						? 'Organizations will appear here once they are provisioned.'
						: 'Try another search term or attention filter.'}
				/>
			</div>
		{:else}
			<div class="organization-directory__table-wrap">
				<table>
					<thead>
						<tr>
							<th scope="col">Organization</th>
							<th scope="col">Lifecycle</th>
							<th scope="col">Attention</th>
							<th scope="col">Team members</th>
							<th scope="col">Created</th>
							<th scope="col"><span class="organization-directory__sr-only">Open details</span></th>
						</tr>
					</thead>
					<tbody>
						{#each organizationList as organization (organization.id)}
							<tr>
								<th scope="row">
									<strong>{organization.name}</strong>
									<small>{organization.slug}</small>
								</th>
								<td
									><Badge status={lifecycleTone(organization.lifecycle_status)}
										>{lifecycleLabel(organization.lifecycle_status)}</Badge
									></td
								>
								<td>
									{#if organization.attention_reasons.length === 0}
										<span class="organization-directory__no-attention">&mdash;</span>
									{:else}
										<div class="organization-directory__attention-badges">
											{#each organization.attention_reasons as reason (reason)}
												<Badge status={attentionMeta[reason].tone} size="small"
													>{attentionMeta[reason].label}</Badge
												>
											{/each}
										</div>
									{/if}
								</td>
								<td>{organization.member_count}</td>
								<td>{formatDate(organization.created_at)}</td>
								<td>
									<a
										class="organization-directory__row-action"
										href={resolve(`/jafar/organizations/${organization.id}`)}
										aria-label={`Open ${organization.name}`}
									>
										<span aria-hidden="true">{@html arrowRightIcon}</span>
									</a>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
		<footer class="organization-directory__table-footer">
			{#if organizations.hasNextPage}
				<Button
					type="button"
					variant="secondary"
					disabled={organizations.isFetchingNextPage}
					onclick={() => organizations.fetchNextPage()}
				>
					{organizations.isFetchingNextPage ? 'Loading more…' : 'Load more'}
				</Button>
			{:else}
				<span>Open an organization to review its details.</span>
			{/if}
		</footer>
	</section>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.organization-directory {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.organization-directory h1,
	.organization-directory h2,
	.organization-directory p {
		margin: 0;
	}

	.organization-directory h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}

	.organization-directory__header,
	.organization-directory__list-meta,
	.organization-directory__table-footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.organization-directory__header {
		align-items: flex-start;
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}

	.organization-directory__eyebrow {
		margin-bottom: var(--space-small) !important;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}

	.organization-directory__description {
		max-width: 65ch;
		margin-top: var(--space-small) !important;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}

	.organization-directory__summary {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}

	.organization-directory__filters {
		display: flex;
		align-items: flex-end;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.organization-directory__filter-field {
		display: grid;
		width: min(260px, 100%);
		gap: var(--space-small);

		label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}
	}

	.organization-directory__filter-field--search {
		width: min(420px, 100%);
		flex: 1 1 320px;
	}

	.organization-directory__filters :global(.button) {
		margin-left: auto;
	}

	.organization-directory__list-meta,
	.organization-directory__table-footer {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.organization-directory__list-meta {
		padding: 0 var(--space-small);
	}

	.organization-directory__list-meta strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}

	.organization-directory__table-panel {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}

	.organization-directory__table-wrap {
		overflow-x: auto;
	}

	.organization-directory table {
		width: 100%;
		min-width: 960px;
		border-collapse: collapse;
		color: var(--color-text);
		font-size: var(--typography--fontSize-base);
	}

	.organization-directory th,
	.organization-directory td {
		padding: var(--space-base) var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}

	.organization-directory thead {
		background: var(--color-surface--background--subtle);
	}

	.organization-directory thead th {
		color: var(--color-text--secondary);
		font-weight: 700;
		white-space: nowrap;
	}

	.organization-directory tbody th {
		color: var(--color-heading);
		font-weight: 700;
	}

	.organization-directory tbody th strong,
	.organization-directory tbody th small {
		display: block;
	}

	.organization-directory tbody th small {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 400;
	}

	.organization-directory tbody tr {
		transition: background-color var(--timing-quick);

		&:hover {
			background: var(--color-surface--hover);
		}

		&:last-child th,
		&:last-child td {
			border-bottom: 0;
		}
	}

	.organization-directory__attention-badges {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);
		max-width: 260px;
	}

	.organization-directory__no-attention {
		color: var(--color-text--secondary);
	}

	.organization-directory__row-action {
		display: grid;
		width: 32px;
		height: 32px;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-interactive);
		text-decoration: none;

		&:hover {
			color: var(--color-interactive--hover);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		span,
		span :global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	.organization-directory__state {
		padding: var(--space-large);
	}

	.organization-directory__table-footer {
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}

	.organization-directory__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 900px) {
		.organization-directory__summary {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 767px) {
		.organization-directory__header,
		.organization-directory__filters,
		.organization-directory__list-meta,
		.organization-directory__table-footer {
			align-items: stretch;
			flex-direction: column;
		}

		.organization-directory__filters :global(.button) {
			margin-left: 0;
		}
	}

	@media (max-width: 639px) {
		.organization-directory h1 {
			font-size: 28px;
		}

		.organization-directory__summary {
			grid-template-columns: 1fr;
		}
	}
</style>
