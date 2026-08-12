<script lang="ts">
	import { resolve } from '$app/paths';
	import { createQuery } from '@tanstack/svelte-query';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-up-right.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import KpiCard from '$lib/components/data-display/KpiCard.svelte';

	type LifecycleStatus = 'pending_setup' | 'active' | 'suspended';
	type Organization = {
		id: string;
		name: string;
		slug: string;
		lifecycle_status: LifecycleStatus;
		created_at: string;
		organization_members: { user_id: string; role: string }[];
	};
	type OrganizationResponse = { organizations: Organization[]; error?: string };

	const organizations = createQuery<OrganizationResponse>(() => ({
		queryKey: ['jafar', 'organizations'],
		queryFn: async () => {
			const response = await fetch('/api/jafar/organizations');
			const result = (await response.json()) as OrganizationResponse;
			if (!response.ok) throw new Error(result.error ?? 'Organizations could not be loaded.');
			return result;
		}
	}));

	const organizationList = $derived(organizations.data?.organizations ?? []);
	const activeCount = $derived(
		organizationList.filter((organization) => organization.lifecycle_status === 'active').length
	);
	const pendingCount = $derived(
		organizationList.filter((organization) => organization.lifecycle_status === 'pending_setup')
			.length
	);
	const suspendedCount = $derived(
		organizationList.filter((organization) => organization.lifecycle_status === 'suspended').length
	);
	const attentionCount = $derived(pendingCount + suspendedCount);

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
	}

	function statusLabel(status: LifecycleStatus) {
		return status === 'pending_setup'
			? 'Pending setup'
			: status === 'active'
				? 'Active'
				: 'Suspended';
	}
</script>

<svelte:head><title>Platform overview · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="owner-overview">
	<header class="owner-overview__header">
		<div>
			<p class="owner-overview__eyebrow">Platform owner</p>
			<h1>Good morning, Jafar</h1>
			<p class="owner-overview__lede">
				Keep a clear view of contractor workspaces and the accounts that need review.
			</p>
		</div>
		<a class="owner-overview__primary-action" href={resolve('/jafar/organizations')}>
			<span>{@html buildingIcon}</span> View organizations
		</a>
	</header>

	<section class="owner-overview__stats" aria-label="Organization summary">
		<KpiCard
			label="Total organizations"
			value={String(organizationList.length)}
			note="All provisioned workspaces"
			icon={buildingIcon}
			tone="brand"
		/>
		<KpiCard
			label="Active"
			value={String(activeCount)}
			note="Access currently enabled"
			icon={checkIcon}
			tone="success"
		/>
		<KpiCard
			label="Needs attention"
			value={String(attentionCount)}
			note={`${pendingCount} pending setup · ${suspendedCount} suspended`}
			icon={alertIcon}
			tone="warning"
		/>
		<KpiCard
			label="Suspended"
			value={String(suspendedCount)}
			note="Records preserved while access is blocked"
			icon={pauseIcon}
			tone="critical"
		/>
	</section>

	<div class="owner-overview__grid">
		<section class="owner-overview__panel" aria-labelledby="attention-title">
			<header class="owner-overview__panel-header">
				<div>
					<p class="owner-overview__eyebrow">Owner queue</p>
					<h2 id="attention-title">Needs your attention</h2>
				</div>
				<span class="owner-overview__count">{attentionCount} open</span>
			</header>
			{#if organizations.isPending}
				<div class="owner-overview__empty">Loading organization attention…</div>
			{:else if organizations.isError}
				<div class="owner-overview__empty owner-overview__empty--error" role="alert">
					{organizations.error.message}
				</div>
			{:else if attentionCount === 0}
				<div class="owner-overview__empty">
					<span class="owner-overview__empty-icon">{@html checkIcon}</span>
					<strong>Everything is in good standing</strong>
					<span>No organization lifecycle action is waiting for review.</span>
				</div>
			{:else}
				<div class="owner-overview__attention-list">
					{#each organizationList.filter((organization) => organization.lifecycle_status !== 'active') as organization (organization.id)}
						<a
							class="owner-overview__attention-item"
							href={resolve(`/jafar/organizations?organization=${organization.id}`)}
						>
							<span
								class:owner-overview__attention-icon--warning={organization.lifecycle_status ===
									'pending_setup'}
								class:owner-overview__attention-icon--critical={organization.lifecycle_status ===
									'suspended'}
								class="owner-overview__attention-icon"
							>
								{@html organization.lifecycle_status === 'pending_setup' ? clockIcon : pauseIcon}
							</span>
							<span class="owner-overview__attention-content"
								><strong>{organization.name}</strong><small
									>{statusLabel(organization.lifecycle_status)} · created {formatDate(
										organization.created_at
									)}</small
								></span
							>
							<span class="owner-overview__attention-arrow">{@html arrowRightIcon}</span>
						</a>
					{/each}
				</div>
			{/if}
			<footer class="owner-overview__panel-footer">
				<a href={resolve('/jafar/organizations')}
					>Open organization directory <span>{@html arrowRightIcon}</span></a
				>
			</footer>
		</section>

		<section class="owner-overview__panel" aria-labelledby="recent-title">
			<header class="owner-overview__panel-header">
				<div>
					<p class="owner-overview__eyebrow">Workspace inventory</p>
					<h2 id="recent-title">Recently created</h2>
				</div>
				<a class="owner-overview__quiet-link" href={resolve('/jafar/organizations')}
					>View all <span>{@html arrowRightIcon}</span></a
				>
			</header>
			{#if organizations.isPending}
				<div class="owner-overview__empty">Loading organizations…</div>
			{:else if organizations.isError}
				<div class="owner-overview__empty owner-overview__empty--error" role="alert">
					{organizations.error.message}
				</div>
			{:else if organizationList.length === 0}
				<div class="owner-overview__empty">No organizations have been provisioned yet.</div>
			{:else}
				<div class="owner-overview__recent-list">
					{#each organizationList.slice(0, 4) as organization (organization.id)}
						<a
							class="owner-overview__recent-item"
							href={resolve(`/jafar/organizations?organization=${organization.id}`)}
						>
							<span class="owner-overview__recent-mark">{@html buildingIcon}</span>
							<span
								><strong>{organization.name}</strong><small
									>{organization.slug} · {formatDate(organization.created_at)}</small
								></span
							>
							<span
								class="owner-overview__status owner-overview__status--{organization.lifecycle_status ===
								'active'
									? 'success'
									: organization.lifecycle_status === 'suspended'
										? 'critical'
										: 'warning'}">{statusLabel(organization.lifecycle_status)}</span
							>
						</a>
					{/each}
				</div>
			{/if}
		</section>
	</div>
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.owner-overview {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}
	.owner-overview__header,
	.owner-overview__panel-header,
	.owner-overview__attention-item,
	.owner-overview__recent-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.owner-overview__header {
		align-items: flex-end;
	}
	.owner-overview__eyebrow {
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
	.owner-overview__lede {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
	}
	.owner-overview__primary-action,
	.owner-overview__quiet-link,
	.owner-overview__panel-footer a {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smaller);
		text-decoration: none;
	}
	.owner-overview__primary-action {
		min-height: 40px;
		padding: 0 var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-surface);
		background: var(--color-interactive);
		font-weight: 600;
	}
	.owner-overview__primary-action:hover {
		background: var(--color-interactive--hover);
	}
	.owner-overview__primary-action span,
	.owner-overview__primary-action :global(svg),
	.owner-overview__quiet-link span,
	.owner-overview__quiet-link :global(svg),
	.owner-overview__panel-footer span,
	.owner-overview__panel-footer :global(svg),
	.owner-overview__attention-arrow :global(svg) {
		display: block;
		width: 18px;
		height: 18px;
	}
	.owner-overview__stats {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.owner-overview__attention-item small,
	.owner-overview__recent-item small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-base);
	}
	.owner-overview__grid {
		display: grid;
		grid-template-columns: minmax(0, 1.35fr) minmax(380px, 1fr);
		gap: var(--space-base);
	}
	.owner-overview__panel {
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		box-shadow: var(--shadow-low);
	}
	.owner-overview__panel-header {
		padding: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.owner-overview__count {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.owner-overview__quiet-link,
	.owner-overview__panel-footer a {
		color: var(--color-interactive);
		font-weight: 600;
	}
	.owner-overview__quiet-link:hover,
	.owner-overview__panel-footer a:hover {
		color: var(--color-interactive--hover);
	}
	.owner-overview__attention-list,
	.owner-overview__recent-list {
		padding: var(--space-small) var(--space-large);
	}
	.owner-overview__attention-item,
	.owner-overview__recent-item {
		padding: var(--space-base) 0;
		color: var(--color-text);
		text-decoration: none;
	}
	.owner-overview__attention-item + .owner-overview__attention-item,
	.owner-overview__recent-item + .owner-overview__recent-item {
		border-top: var(--border-base) solid var(--color-border);
	}
	.owner-overview__attention-item:hover,
	.owner-overview__recent-item:hover {
		color: var(--color-heading);
	}
	.owner-overview__attention-content,
	.owner-overview__recent-item > span:nth-child(2) {
		flex: 1;
		min-width: 0;
	}
	.owner-overview__attention-content strong,
	.owner-overview__attention-content small,
	.owner-overview__recent-item strong,
	.owner-overview__recent-item small {
		display: block;
	}
	.owner-overview__attention-icon,
	.owner-overview__recent-mark,
	.owner-overview__empty-icon {
		display: grid;
		width: 32px;
		height: 32px;
		flex: 0 0 32px;
		place-items: center;
		border-radius: var(--radius-base);
	}
	.owner-overview__attention-icon :global(svg),
	.owner-overview__recent-mark :global(svg),
	.owner-overview__empty-icon :global(svg) {
		width: 18px;
		height: 18px;
	}
	.owner-overview__attention-icon--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.owner-overview__attention-icon--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.owner-overview__recent-mark {
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.owner-overview__attention-arrow {
		color: var(--color-icon--secondary);
	}
	.owner-overview__status {
		flex: 0 0 auto;
		padding: 6px 10px;
		border-radius: 12px;
		font-size: var(--typography--fontSize-small);
	}
	.owner-overview__status--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.owner-overview__status--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.owner-overview__status--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.owner-overview__empty {
		display: grid;
		min-height: 160px;
		place-items: center;
		gap: var(--space-small);
		padding: var(--space-large);
		color: var(--color-text--secondary);
		text-align: center;
	}
	.owner-overview__empty strong {
		color: var(--color-heading);
	}
	.owner-overview__empty-icon {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.owner-overview__empty--error {
		color: var(--color-critical);
	}
	.owner-overview__panel-footer {
		padding: var(--space-base) var(--space-large);
		border-top: var(--border-base) solid var(--color-border);
	}
	@media (max-width: 1100px) {
		.owner-overview__stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.owner-overview__grid {
			grid-template-columns: 1fr;
		}
	}
	@media (max-width: 639px) {
		.owner-overview__header {
			align-items: flex-start;
			flex-direction: column;
		}
		h1 {
			font-size: 28px;
		}
		.owner-overview__stats {
			grid-template-columns: 1fr;
		}
		.owner-overview__grid {
			grid-template-columns: 1fr;
		}
		.owner-overview__status {
			display: none;
		}
	}
</style>
