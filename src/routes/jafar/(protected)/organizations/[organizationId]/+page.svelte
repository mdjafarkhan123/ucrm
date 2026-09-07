<script lang="ts">
	import type {
		CommercialState,
		PackagesCatalogResponse,
		TeamResponse,
		HistoryResponse,
		OperationListResponse,
		AccessResponse
	} from '$lib/components/jafar/organization/types';
	import Tabs, { type Tab } from '$lib/components/ui/Tabs.svelte';
	import { dev } from '$app/environment';
	import { replaceState } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { createQuery } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import {
		getOrganizationDetailPreview,
		organizationDetailScenarioLabel
	} from '$lib/jafar/organization-detail-preview';
	import { formatPrice } from '$lib/components/jafar/organization/format';
	import OverviewWorkspace from '$lib/components/jafar/organization/OverviewWorkspace.svelte';
	import AccessWorkspace from '$lib/components/jafar/organization/AccessWorkspace.svelte';
	import CommunicationsWorkspace from '$lib/components/jafar/organization/CommunicationsWorkspace.svelte';
	import TeamWorkspace from '$lib/components/jafar/organization/TeamWorkspace.svelte';
	import ActivityWorkspace from '$lib/components/jafar/organization/ActivityWorkspace.svelte';

	const scenario = $derived(page.url.searchParams.get('scenario'));
	const organizationId = $derived(page.params.organizationId);
	const preview = $derived(dev && scenario ? getOrganizationDetailPreview(scenario) : null);

	const organizationTabs: Tab[] = [
		{ value: 'overview', label: 'Overview' },
		{ value: 'access', label: 'Access & limits' },
		{ value: 'communications', label: 'Communications' },
		{ value: 'team', label: 'Team' },
		{ value: 'activity', label: 'Activity' }
	];
	let activeTab = $derived.by(() => {
		const requested = page.url.searchParams.get('tab');
		return organizationTabs.some((tab) => tab.value === requested)
			? (requested as string)
			: 'overview';
	});
	function selectTab(next: string) {
		activeTab = next;
		const url = new URL(page.url);
		if (next === 'overview') url.searchParams.delete('tab');
		else url.searchParams.set('tab', next);
		// This is the current page URL with one query parameter changed, not a route id.
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		replaceState(url, page.state);
	}

	const accessQuery = createQuery<AccessResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'access'],
		enabled: !preview && Boolean(organizationId),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/access`);
			const result = (await response.json()) as AccessResponse;
			if (!response.ok) throw new Error(result.error ?? 'Organization access could not be loaded.');
			return result;
		}
	}));
	const access = $derived(accessQuery.data?.access ?? null);
	const isLoading = $derived(!preview && accessQuery.isPending);
	const errorDescription = $derived(
		accessQuery.error instanceof Error
			? accessQuery.error.message
			: 'Organization access could not be loaded. Try again.'
	);
	const isInitialError = $derived(!preview && accessQuery.isError && !access);
	const isStaleData = $derived(!preview && accessQuery.isError && Boolean(access));

	const commercialQuery = createQuery<CommercialState>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'commercial'],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/commercial`);
			const result = (await response.json()) as CommercialState;
			if (!response.ok) throw new Error(result.error ?? 'Commercial access could not be loaded.');
			return result;
		}
	}));

	const teamQuery = createQuery<TeamResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'team'],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/team`);
			const result = (await response.json()) as TeamResponse;
			if (!response.ok) throw new Error(result.error ?? 'Team members could not be loaded.');
			return result;
		}
	}));

	const historyQuery = createQuery<HistoryResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'history'],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/history`);
			const result = (await response.json()) as HistoryResponse;
			if (!response.ok) throw new Error(result.error ?? 'History could not be loaded.');
			return result;
		}
	}));

	const applicationId = $derived(historyQuery.data?.applicationId ?? null);

	const organizationOperationsQuery = createQuery<OperationListResponse>(() => ({
		queryKey: ['jafar', 'operations', 'target', organizationId],
		enabled: !preview && Boolean(organizationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/operations?target_id=${organizationId}`);
			const result = (await response.json()) as OperationListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Operations could not be loaded.');
			return result;
		}
	}));

	const applicationOperationsQuery = createQuery<OperationListResponse>(() => ({
		queryKey: ['jafar', 'operations', 'target', applicationId],
		enabled: !preview && Boolean(applicationId) && Boolean(access),
		queryFn: async () => {
			const response = await fetch(`/api/jafar/operations?target_id=${applicationId}`);
			const result = (await response.json()) as OperationListResponse;
			if (!response.ok) throw new Error(result.error ?? 'Operations could not be loaded.');
			return result;
		}
	}));

	const attentionOperations = $derived(
		[
			...(organizationOperationsQuery.data?.operations ?? []),
			...(applicationOperationsQuery.data?.operations ?? [])
		].sort((a, b) => (a.updated_at < b.updated_at ? 1 : a.updated_at > b.updated_at ? -1 : 0))
	);

	const packagesCatalogQuery = createQuery<PackagesCatalogResponse>(() => ({
		queryKey: ['jafar', 'packages'],
		enabled: !preview && Boolean(access),
		queryFn: async () => {
			const response = await fetch('/api/jafar/packages');
			const result = (await response.json()) as PackagesCatalogResponse;
			if (!response.ok) throw new Error(result.error ?? 'Package definitions could not be loaded.');
			return result;
		}
	}));
	const publishedVersionOptions = $derived(
		(packagesCatalogQuery.data?.packages ?? []).flatMap((packageDefinition) =>
			packageDefinition.versions
				.filter((version) => version.status === 'published')
				.map((version) => ({
					value: version.id,
					label: `${packageDefinition.display_name} · v${version.version_number} — ${formatPrice(version.price_usd_cents, version.currency, version.billing_period)}`
				}))
		)
	);

	const pageTitle = $derived(
		isLoading
			? 'Loading organization · Organizations'
			: preview
				? `${preview.name} · Organizations`
				: access
					? `${access.organization.name} · Organizations`
					: 'Organization detail'
	);

	let actionError = $state('');
	let actionMessage = $state('');
</script>

<svelte:head><title>{pageTitle}</title></svelte:head>

{#if isLoading}
	<!-- eslint-disable svelte/no-at-html-tags -->
	<main class="organization-detail" aria-busy="true">
		<nav class="organization-detail__breadcrumb" aria-label="Breadcrumb">
			<a href={resolve('/jafar/organizations')}
				><span aria-hidden="true">{@html arrowLeftIcon}</span> Organizations</a
			>
			<span aria-hidden="true">/</span>
			<span>Loading organization</span>
		</nav>

		<header class="organization-detail__header">
			<div class="organization-detail__loading-heading">
				<p class="organization-detail__eyebrow">Organization control room</p>
				<LoadingSkeleton variant="heading" label="Loading organization name" />
				<LoadingSkeleton variant="text" label="Loading organization summary" />
			</div>
			<a class="organization-detail__back-link" href={resolve('/jafar/organizations')}
				>Back to directory</a
			>
		</header>

		<section class="organization-detail__section" aria-labelledby="loading-overview-title">
			<div class="organization-detail__section-heading">
				<p class="organization-detail__eyebrow">Overview</p>
				<h2 id="loading-overview-title">Loading organization details</h2>
				<p>The page structure remains available while organization information is retrieved.</p>
			</div>
			<div class="organization-detail__overview-grid">
				<LoadingSkeleton variant="card" label="Loading organization overview" />
				<LoadingSkeleton variant="card" label="Loading lifecycle details" />
				<LoadingSkeleton variant="card" label="Loading next safe action" />
			</div>
		</section>

		<section class="organization-detail__at-a-glance" aria-label="Loading status summary">
			<LoadingSkeleton variant="card" label="Loading commercial access summary" />
			<LoadingSkeleton variant="card" label="Loading free access summary" />
			<LoadingSkeleton variant="card" label="Loading package status summary" />
		</section>

		<section
			class="organization-detail__loading-sections"
			aria-label="Loading organization sections"
		>
			<LoadingSkeleton variant="card" label="Loading commercial access" />
			<LoadingSkeleton variant="card" label="Loading integrations" />
			<LoadingSkeleton variant="card" label="Loading team access" />
			<LoadingSkeleton variant="card" label="Loading history and recovery" />
		</section>
	</main>
	<!-- eslint-enable svelte/no-at-html-tags -->
{:else if isInitialError}
	<main class="organization-detail organization-detail--unavailable">
		<ErrorState
			title="Organization could not be loaded"
			description={errorDescription}
			retry={() => accessQuery.refetch()}
		>
			{#snippet action()}<a
					class="organization-detail__back-link"
					href={resolve('/jafar/organizations')}>Back to organizations</a
				>{/snippet}
		</ErrorState>
	</main>
{:else if preview || access}
	<!-- eslint-disable svelte/no-at-html-tags -->
	<main class="organization-detail">
		{#if isStaleData}
			<section class="organization-detail__stale-banner" role="status" aria-live="polite">
				<span class="organization-detail__stale-banner-icon" aria-hidden="true"
					>{@html alertIcon}</span
				>
				<div>
					<strong>Showing the last available organization information</strong>
					<p>The latest refresh failed, so this page may be out of date.</p>
				</div>
				<Button
					variant="secondary"
					variation="subtle"
					loading={accessQuery.isFetching}
					onclick={() => accessQuery.refetch()}
					>{accessQuery.isFetching ? 'Refreshing' : 'Try again'}</Button
				>
			</section>
		{/if}

		<nav class="organization-detail__breadcrumb" aria-label="Breadcrumb">
			<a href={resolve('/jafar/organizations')}
				><span aria-hidden="true">{@html arrowLeftIcon}</span> Organizations</a
			>
			<span aria-hidden="true">/</span>
			<span>{preview?.name ?? access?.organization.name}</span>
		</nav>

		<header class="organization-detail__header">
			<div>
				<p class="organization-detail__eyebrow">Organization control room</p>
				<div class="organization-detail__heading-row">
					<h1>{preview?.name ?? access?.organization.name}</h1>
					<Badge
						status={preview?.lifecycleTone ??
							(access?.organization.lifecycle_status === 'active'
								? 'success'
								: access?.organization.lifecycle_status === 'suspended' ||
									  access?.organization.lifecycle_status === 'pending_closure' ||
									  access?.organization.lifecycle_status === 'closed'
									? 'critical'
									: 'warning')}
						>{preview?.lifecycle ??
							(access?.organization.lifecycle_status === 'pending_setup'
								? 'Needs review'
								: access?.organization.lifecycle_status === 'pending_closure'
									? 'Closing'
									: access?.organization.lifecycle_status === 'closed'
										? 'Closed'
										: access?.organization.lifecycle_status)}</Badge
					>
				</div>
				<p class="organization-detail__description">
					{preview?.slug ?? access?.organization.slug}{#if preview}
						· Development scenario: {organizationDetailScenarioLabel(preview.scenario)}{/if}
				</p>
			</div>
			<a class="organization-detail__back-link" href={resolve('/jafar/organizations')}
				>Back to directory</a
			>
		</header>

		{#if actionMessage}<p
				class="organization-detail__feedback organization-detail__feedback--success"
				role="status"
			>
				{actionMessage}
			</p>{/if}
		{#if actionError}<p
				class="organization-detail__feedback organization-detail__feedback--error"
				role="alert"
			>
				{actionError}
			</p>{/if}

		{#if preview}
			<section
				class="organization-detail__preview-notice"
				role="status"
				aria-label="Development preview"
			>
				<span aria-hidden="true">{@html shieldIcon}</span>
				<p>
					<strong>Development-only preview.</strong> This scenario is local to this screen, cannot change
					records, and is hidden from production.
				</p>
			</section>

			{#if preview?.warning}
				<section
					class="organization-detail__warning organization-detail__warning--{preview.warning.tone}"
					role="alert"
				>
					<span aria-hidden="true">{@html alertIcon}</span>
					<div>
						<strong>{preview.warning.title}</strong>
						<p>{preview.warning.detail}</p>
					</div>
				</section>
			{/if}
		{/if}
		<Tabs
			tabs={organizationTabs}
			value={activeTab}
			onChange={selectTab}
			label="Organization workspaces"
		>
			<OverviewWorkspace
				{access}
				{preview}
				{packagesCatalogQuery}
				{teamQuery}
				{commercialQuery}
				{historyQuery}
				{organizationOperationsQuery}
				{applicationOperationsQuery}
				{attentionOperations}
				{selectTab}
			/>

			<AccessWorkspace
				{access}
				{preview}
				{packagesCatalogQuery}
				{commercialQuery}
				{publishedVersionOptions}
				{organizationId}
				bind:actionError
				bind:actionMessage
			/>

			<CommunicationsWorkspace {access} {preview} />

			<TeamWorkspace {access} {preview} {teamQuery} />

			<ActivityWorkspace
				{access}
				{preview}
				{commercialQuery}
				{teamQuery}
				{historyQuery}
				{organizationOperationsQuery}
				{applicationOperationsQuery}
				{attentionOperations}
				{applicationId}
			/>
		</Tabs>
	</main>
	<!-- eslint-enable svelte/no-at-html-tags -->
{/if}

<style lang="scss">
	.organization-detail {
		display: grid;
		gap: var(--space-base);
		min-width: 0;
	}
	.organization-detail > :global(.tabs) {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	.organization-detail > :global(.tabs) > :global(.tabs__list) {
		padding: var(--space-small) var(--space-large) 0;
		background: var(--color-surface--background--subtle);
	}
	.organization-detail > :global(.tabs) > :global(.tab-panel:not([hidden])) {
		gap: var(--space-larger);
		padding: var(--space-large);
	}
	.organization-detail--unavailable {
		max-width: 640px;
		margin: var(--space-largest) auto;
	}
	.organization-detail__stale-banner {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.organization-detail__stale-banner-icon {
		display: inline-flex;
		flex: 0 0 auto;
	}
	.organization-detail__stale-banner-icon :global(svg) {
		width: var(--typography--fontSize-largest);
		height: var(--typography--fontSize-largest);
	}
	.organization-detail__stale-banner div {
		flex: 1;
	}
	.organization-detail__stale-banner strong {
		display: block;
		color: inherit;
	}
	.organization-detail__stale-banner p {
		margin: var(--space-smaller) 0 0;
		color: inherit;
	}
	.organization-detail__feedback {
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__feedback--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.organization-detail__feedback--error {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.organization-detail__breadcrumb {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__breadcrumb a,
	.organization-detail__back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		color: var(--color-interactive);
		font-weight: 600;
		text-decoration: underline;
		text-underline-offset: var(--space-smaller);
	}
	.organization-detail__breadcrumb a:hover,
	.organization-detail__back-link:hover {
		color: var(--color-interactive--hover);
	}
	.organization-detail__breadcrumb a:focus-visible,
	.organization-detail__back-link:focus-visible {
		outline: none;
		box-shadow: var(--shadow-focus);
	}
	.organization-detail__breadcrumb :global(svg) {
		width: 16px;
		height: 16px;
	}
	.organization-detail__header {
		position: relative;
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-large);
		overflow: hidden;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);
	}
	.organization-detail__header::before {
		position: absolute;
		top: 0;
		bottom: 0;
		left: 0;
		width: var(--space-smaller);
		background: var(--color-brand);
		content: '';
	}
	.organization-detail__loading-heading {
		display: grid;
		gap: var(--space-small);
		width: min(560px, 60vw);
	}
	.organization-detail__loading-heading :global(.skeleton--heading) {
		width: min(360px, 80%);
	}
	.organization-detail__loading-heading :global(.skeleton--text) {
		width: min(520px, 100%);
	}
	.organization-detail__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1,
	h2,
	p {
		margin: 0;
	}
	h1 {
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	.organization-detail__heading-row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-base);
	}
	.organization-detail__description,
	.organization-detail__section-heading > p:last-child {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
	}
	.organization-detail__back-link {
		min-height: 36px;
		padding: var(--space-small) var(--space-slim);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
		white-space: nowrap;
	}
	.organization-detail__preview-notice,
	.organization-detail__warning {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
	}
	.organization-detail__preview-notice {
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.organization-detail__preview-notice > span,
	.organization-detail__warning > span {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
		width: var(--space-large);
		height: var(--space-large);
		border-radius: var(--radius-circle);
		color: var(--color-surface);
		background: var(--color-informative);
	}
	.organization-detail__preview-notice :global(svg),
	.organization-detail__warning :global(svg) {
		width: 16px;
		height: 16px;
	}
	.organization-detail__warning {
		color: var(--warning-text);
		background: var(--warning-surface);
	}
	.organization-detail__warning--warning {
		--warning-text: var(--color-warning--onSurface);
		--warning-surface: var(--color-warning--surface);
	}
	.organization-detail__warning--critical {
		--warning-text: var(--color-critical--onSurface);
		--warning-surface: var(--color-critical--surface);
	}
	.organization-detail__warning--informative {
		--warning-text: var(--color-informative--onSurface);
		--warning-surface: var(--color-informative--surface);
	}
	.organization-detail__warning--warning > span {
		background: var(--color-warning);
	}
	.organization-detail__warning--critical > span {
		background: var(--color-critical);
	}
	.organization-detail__warning--informative > span {
		background: var(--color-informative);
	}
	.organization-detail__warning p {
		margin-top: var(--space-smaller);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__section {
		display: grid;
		grid-template-columns: minmax(0, 1fr);
		gap: var(--space-base);
		min-width: 0;
	}
	.organization-detail__section > * {
		min-width: 0;
	}
	.organization-detail__overview-grid {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__at-a-glance {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__at-a-glance :global(.skeleton--card) {
		height: 104px;
	}
	.organization-detail__loading-sections {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__loading-sections :global(.skeleton--card) {
		height: 220px;
	}
	.organization-detail__at-a-glance div {
		min-width: 0;
	}
	.organization-detail__at-a-glance p {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__at-a-glance strong {
		display: block;
	}
	.organization-detail__at-a-glance strong {
		margin: var(--space-smallest) 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	@media (max-width: 1100px) {
		.organization-detail__overview-grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 767px) {
		.organization-detail__header {
			flex-direction: column;
		}
		.organization-detail__at-a-glance {
			grid-template-columns: 1fr;
		}
		.organization-detail__loading-heading {
			width: 100%;
		}
	}
	@media (max-width: 639px) {
		h1 {
			font-size: 28px;
		}
		.organization-detail__overview-grid {
			grid-template-columns: 1fr;
		}
		.organization-detail__loading-sections {
			grid-template-columns: 1fr;
		}
		.organization-detail__back-link {
			min-height: auto;
		}
	}
</style>
