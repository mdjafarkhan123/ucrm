<script lang="ts">
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
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

	type LifecycleStatus = 'active' | 'suspended';
	type Organization = {
		id: string;
		name: string;
		slug: string;
		lifecycle_status: LifecycleStatus;
		created_at: string;
		updated_at: string;
		organization_members: { user_id: string; role: string }[];
	};
	type OrganizationListResponse = { organizations: Organization[]; error?: string };

	const lifecycleOptions = [
		{ value: '', label: 'All lifecycle states' },
		{ value: 'active', label: 'Active' },
		{ value: 'suspended', label: 'Suspended' }
	];

	let search = $state('');
	let lifecycleFilter = $state('');

	const organizations = createQuery<OrganizationListResponse>(() => ({
		queryKey: ['jafar', 'organizations'],
		queryFn: async () => {
			const response = await fetch('/api/jafar/organizations');
			const result = (await response.json()) as OrganizationListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Organizations could not be loaded.');
			return result;
		}
	}));

	const organizationList = $derived(organizations.data?.organizations ?? []);
	const visibleOrganizations = $derived(
		organizationList.filter((organization) => {
			const matchesSearch = `${organization.name} ${organization.slug}`
				.toLowerCase()
				.includes(search.trim().toLowerCase());
			const matchesLifecycle =
				!lifecycleFilter || organization.lifecycle_status === lifecycleFilter;
			return matchesSearch && matchesLifecycle;
		})
	);
	const activeCount = $derived(
		organizationList.filter((organization) => organization.lifecycle_status === 'active').length
	);
	const suspendedCount = $derived(
		organizationList.filter((organization) => organization.lifecycle_status === 'suspended').length
	);
	const filtersApplied = $derived(Boolean(search || lifecycleFilter));

	function clearFilters() {
		search = '';
		lifecycleFilter = '';
	}

	function lifecycleLabel(lifecycle: LifecycleStatus) {
		return lifecycle === 'active' ? 'Active' : 'Suspended';
	}

	function lifecycleTone(lifecycle: LifecycleStatus): 'success' | 'critical' {
		return lifecycle === 'active' ? 'success' : 'critical';
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
			value={String(organizationList.length)}
			note="All organizations"
			icon={buildingIcon}
			variant="compact"
		/>
		<KpiCard
			label="Active"
			value={String(activeCount)}
			note="Contractor access allowed"
			icon={checkIcon}
			tone="success"
			variant="compact"
		/>
		<KpiCard
			label="Suspended"
			value={String(suspendedCount)}
			note="Contractor access blocked"
			icon={pauseIcon}
			tone="critical"
			variant="compact"
		/>
	</section>

	<section class="organization-directory__filters" aria-label="Organization filters">
		<div class="organization-directory__filter-field organization-directory__filter-field--search">
			<label for="organization-search">Search organizations</label>
			<SearchInput
				id="organization-search"
				bind:value={search}
				placeholder="Search by organization name"
				ariaLabel="Search organizations"
			/>
		</div>
		<div class="organization-directory__filter-field">
			<label for="organization-lifecycle">Lifecycle</label>
			<Select
				id="organization-lifecycle"
				bind:value={lifecycleFilter}
				options={lifecycleOptions}
				ariaLabel="Filter organizations by lifecycle"
			/>
		</div>
		<Button
			type="button"
			variant="secondary"
			variation="subtle"
			size="small"
			disabled={!filtersApplied}
			onclick={clearFilters}>Clear filters</Button
		>
	</section>

	<div class="organization-directory__list-meta" aria-live="polite">
		<span><strong>{visibleOrganizations.length}</strong> organizations shown</span>
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
		{:else if visibleOrganizations.length === 0}
			<div class="organization-directory__state">
				<EmptyState
					title={organizationList.length === 0
						? 'No organizations yet'
						: 'No matching organizations'}
					description={organizationList.length === 0
						? 'Organizations will appear here once they are provisioned.'
						: 'Try another organization name or lifecycle state.'}
				/>
			</div>
		{:else}
			<div class="organization-directory__table-wrap">
				<table>
					<thead>
						<tr>
							<th scope="col">Organization</th>
							<th scope="col">Lifecycle</th>
							<th scope="col">Team members</th>
							<th scope="col">Created</th>
							<th scope="col"><span class="organization-directory__sr-only">Open details</span></th>
						</tr>
					</thead>
					<tbody>
						{#each visibleOrganizations as organization (organization.id)}
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
								<td>{organization.organization_members.length}</td>
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
			<span>Open an organization to review its details.</span>
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
		grid-template-columns: repeat(3, minmax(0, 1fr));
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
		width: min(240px, 100%);
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
		min-width: 840px;
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
