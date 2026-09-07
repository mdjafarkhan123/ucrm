<script lang="ts">
	import type {
		EffectiveAccess,
		CommercialState,
		PackagesCatalogResponse,
		TeamResponse,
		HistoryResponse,
		OperationListResponse,
		OperationAttempt
	} from '$lib/components/jafar/organization/types';
	import type { CreateQueryResult } from '@tanstack/svelte-query';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import buildingIcon from '@tabler/icons/outline/building.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import shieldIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import OverviewAttention from './OverviewAttention.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import { organizationDetailScenarioLabel } from '$lib/jafar/organization-detail-preview';
	import { formatCalendarDate, formatDateTime } from './format';
	let {
		access,
		preview,
		packagesCatalogQuery,
		teamQuery,
		commercialQuery,
		historyQuery,
		organizationOperationsQuery,
		applicationOperationsQuery,
		attentionOperations,
		selectTab
	}: {
		access: EffectiveAccess | null;
		preview: OrganizationDetailPreview | null;
		packagesCatalogQuery: CreateQueryResult<PackagesCatalogResponse, Error>;
		teamQuery: CreateQueryResult<TeamResponse, Error>;
		commercialQuery: CreateQueryResult<CommercialState, Error>;
		historyQuery: CreateQueryResult<HistoryResponse, Error>;
		organizationOperationsQuery: CreateQueryResult<OperationListResponse, Error>;
		applicationOperationsQuery: CreateQueryResult<OperationListResponse, Error>;
		attentionOperations: OperationAttempt[];
		selectTab: (tab: string) => void;
	} = $props();
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="overview">
	<div class="organization-workspace">
		{#if preview}
			<section class="organization-detail__section" aria-labelledby="overview-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Overview</p>
					<h2 id="overview-title">What needs attention</h2>
					<p>
						Review organization identity, lifecycle, administrator readiness, and the next safe
						action.
					</p>
				</div>

				<div class="organization-detail__overview-grid">
					<Card class="organization-detail__identity-card">
						<div class="organization-detail__card-icon">{@html buildingIcon}</div>
						<div>
							<p class="organization-detail__card-label">Organization</p>
							<h3>{preview?.name}</h3>
							<p>{preview?.slug}</p>
						</div>
						<dl>
							<div>
								<dt>Preview record</dt>
								<dd>{preview?.id}</dd>
							</div>
							<div>
								<dt>Scenario</dt>
								<dd>{organizationDetailScenarioLabel(preview?.scenario ?? 'active')}</dd>
							</div>
						</dl>
					</Card>

					<Card class="organization-detail__lifecycle-card">
						<div
							class="organization-detail__card-icon organization-detail__card-icon--{preview?.lifecycleTone}"
						>
							{@html preview?.lifecycleTone === 'success'
								? checkIcon
								: preview?.lifecycleTone === 'critical'
									? lockIcon
									: clockIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Lifecycle</p>
							<h3>{preview?.lifecycle}</h3>
							<p>
								{preview?.lifecycle === 'Suspended'
									? 'New contractor actions are paused while records stay preserved.'
									: 'Commercial access is currently allowed.'}
							</p>
						</div>
						<div class="organization-detail__status-line">
							<Badge status={preview?.setup.tone}>{preview?.setup.state}</Badge><span
								>{preview?.setup.detail}</span
							>
						</div>
					</Card>

					<Card class="organization-detail__next-card">
						<div class="organization-detail__card-icon organization-detail__card-icon--informative">
							{@html alertIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Next safe action</p>
							<h3>
								{preview?.warning ? 'Review before changing access' : 'No owner action required'}
							</h3>
							<p>
								{preview?.warning
									? preview.warning.detail
									: 'Commercial access, administrator readiness, and recovery state are all clear in this scenario.'}
							</p>
						</div>
						<span class="organization-detail__safe-label">No live actions yet</span>
					</Card>
				</div>
			</section>

			<section
				class="organization-detail__at-a-glance"
				aria-label="Organization status at a glance"
			>
				<article>
					<span class="organization-detail__mini-icon">{@html calendarIcon}</span>
					<div>
						<p>Commercial access</p>
						<strong>{preview?.commercial.paidThrough}</strong><small
							>{preview?.commercial.grace}</small
						>
					</div>
				</article>
				<article>
					<span class="organization-detail__mini-icon">{@html usersIcon}</span>
					<div>
						<p>Administrator setup</p>
						<strong>{preview?.setup.state}</strong><small
							>{preview?.team[0].name} is the primary administrator</small
						>
					</div>
				</article>
				<article>
					<span class="organization-detail__mini-icon">{@html shieldIcon}</span>
					<div>
						<p>Recovery</p>
						<strong>{preview?.recovery.state}</strong><small>{preview?.recovery.detail}</small>
					</div>
				</article>
			</section>
		{:else if access}
			<section class="organization-detail__section" aria-labelledby="overview-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Overview</p>
					<h2 id="overview-title">What needs attention</h2>
					<p>Review organization identity, lifecycle, and the next safe action.</p>
				</div>

				<div class="organization-detail__overview-grid">
					<Card class="organization-detail__identity-card">
						<div class="organization-detail__card-icon">{@html buildingIcon}</div>
						<div>
							<p class="organization-detail__card-label">Organization</p>
							<h3>{access.organization.name}</h3>
							<p>{access.organization.slug}</p>
						</div>
						<dl>
							<div>
								<dt>Organization ID</dt>
								<dd>{access.organization.id}</dd>
							</div>
							<div>
								<dt>Package</dt>
								<dd>{access.package.display_name}</dd>
							</div>
						</dl>
					</Card>

					<Card class="organization-detail__lifecycle-card">
						<div
							class="organization-detail__card-icon organization-detail__card-icon--{access
								.organization.lifecycle_status === 'active'
								? 'success'
								: access.organization.lifecycle_status === 'pending_setup'
									? 'warning'
									: 'critical'}"
						>
							{@html access.organization.lifecycle_status === 'active'
								? checkIcon
								: access.organization.lifecycle_status === 'pending_setup'
									? alertIcon
									: access.organization.lifecycle_status === 'pending_closure'
										? clockIcon
										: lockIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Lifecycle</p>
							<h3>
								{access.organization.lifecycle_status === 'pending_setup'
									? 'Needs review'
									: access.organization.lifecycle_status === 'pending_closure'
										? 'Closing'
										: access.organization.lifecycle_status === 'closed'
											? 'Closed'
											: access.organization.lifecycle_status}
							</h3>
							<p>
								{access.organization.lifecycle_status === 'suspended'
									? 'New contractor actions are paused while records stay preserved.'
									: access.organization.lifecycle_status === 'pending_setup'
										? 'This legacy organization predates paid onboarding and needs a one-time review.'
										: access.organization.lifecycle_status === 'pending_closure'
											? 'Contractor access is blocked. Restore before the deadline or it deletes automatically.'
											: access.organization.lifecycle_status === 'closed'
												? 'This organization has been permanently deleted.'
												: 'Commercial access is currently allowed.'}
							</p>
						</div>
					</Card>

					<Card class="organization-detail__next-card">
						<div class="organization-detail__card-icon organization-detail__card-icon--informative">
							{@html alertIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Next safe action</p>
							{#if access.organization.lifecycle_status === 'pending_setup'}
								<h3>One-time legacy review</h3>
								<p>Open Activity for the one-time review checklist and lifecycle controls.</p>
							{:else if access.organization.lifecycle_status === 'pending_closure'}
								<h3>Closing organization</h3>
								<p>
									Restore before the deadline shown above, or let the countdown finish and delete
									everything.
								</p>
							{:else if access.organization.lifecycle_status === 'closed'}
								<h3>Organization deleted</h3>
								<p>All records for this organization have been permanently removed.</p>
							{:else if access.organization.lifecycle_status === 'suspended'}
								<h3>Review before reactivating</h3>
								<p>Confirm the reason for suspension no longer applies before reactivating.</p>
							{:else if teamQuery.isError || historyQuery.isError || organizationOperationsQuery.isError || applicationOperationsQuery.isError}
								<h3>Some health information is unavailable</h3>
								<p>Review the status checks below before changing access.</p>
							{:else if teamQuery.data && !teamQuery.data.has_administrator}
								<h3>Administrator access needs attention</h3>
								<p>Open Team to review administrator readiness.</p>
							{:else if attentionOperations.length > 0}
								<h3>Open recovery work</h3>
								<p>Review the recovery items in Activity before changing access.</p>
							{:else if packagesCatalogQuery.isPending || teamQuery.isPending || historyQuery.isPending || organizationOperationsQuery.isPending || (historyQuery.data?.applicationId && applicationOperationsQuery.isPending)}
								<h3>Loading package versions</h3>
								<p>Published package versions are loading before the next commercial action.</p>
							{:else if access.billing.is_overdue && !access.billing.is_in_grace}
								<h3>Paid-through date is past grace</h3>
								<p>Review commercial eligibility before any further lifecycle change.</p>
							{:else if access.billing.is_in_grace}
								<h3>In grace period</h3>
								<p>Grace ends {formatDateTime(access.billing.grace_ends_at)}.</p>
							{:else}
								<h3>Commercial access is clear</h3>
								<p>Review team and provider health below for any remaining owner action.</p>
							{/if}
						</div>
					</Card>
				</div>
			</section>

			<section
				class="organization-detail__at-a-glance"
				aria-label="Organization status at a glance"
			>
				<article>
					<span class="organization-detail__mini-icon">{@html calendarIcon}</span>
					<div>
						<p>Commercial access</p>
						<strong>{formatCalendarDate(access.billing.paid_through_date)}</strong>
						<small
							>{access.billing.is_in_grace
								? `In grace until ${formatDateTime(access.billing.grace_ends_at)}`
								: access.billing.is_overdue
									? 'Past grace'
									: 'Not in grace'}</small
						>
					</div>
				</article>
				<article>
					<span class="organization-detail__mini-icon">{@html shieldIcon}</span>
					<div>
						<p>Free access</p>
						{#if access.free_access.active}
							<strong
								>{access.free_access.active.access_until_date === null
									? 'Free forever'
									: `Free until ${formatCalendarDate(access.free_access.active.access_until_date)}`}</strong
							>
							{#if access.free_access.future}
								<small>Another grant is scheduled</small>
							{:else}
								<small>Managed in Access & limits</small>
							{/if}
						{:else if access.free_access.future}
							<strong>Paid access</strong>
							<small
								>Free access starts {formatCalendarDate(access.free_access.future.starts_at)}</small
							>
						{:else}
							<strong>Paid access</strong>
							<small>Managed in Access & limits</small>
						{/if}
					</div>
				</article>
				<article>
					<span class="organization-detail__mini-icon">{@html usersIcon}</span>
					<div>
						<p>Package status</p>
						<strong>{access.package.status}</strong>
						<small
							>{access.package.version_number
								? `Version ${access.package.version_number}`
								: 'Legacy assignment'}</small
						>
					</div>
				</article>
			</section>
			<OverviewAttention
				{access}
				{teamQuery}
				{historyQuery}
				{organizationOperationsQuery}
				{applicationOperationsQuery}
				{attentionOperations}
				{selectTab}
			/>
			{#if access.organization.lifecycle_status === 'pending_closure'}
				<p>
					Closure deadline: {commercialQuery.isPending
						? 'Loading…'
						: commercialQuery.isError
							? 'Could not be loaded. Open Activity to retry.'
							: formatDateTime(commercialQuery.data?.closure?.deadline_at ?? null)}
				</p>
			{/if}
		{/if}
	</div>
</TabPanel>

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	.organization-workspace {
		display: grid;
		gap: var(--space-larger);
		min-width: 0;
	}
	.organization-detail__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h2,
	h3,
	p {
		margin: 0;
	}
	h2 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-larger);
		line-height: var(--typography--lineHeight-tight);
	}
	.organization-detail__section-heading > p:last-child {
		max-width: 65ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-large);
		line-height: var(--typography--lineHeight-large);
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
	.organization-workspace :global(.organization-detail__identity-card),
	.organization-workspace :global(.organization-detail__lifecycle-card),
	.organization-workspace :global(.organization-detail__next-card) {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-detail__card-icon,
	.organization-detail__mini-icon {
		display: grid;
		place-items: center;
		border-radius: var(--radius-base);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
	}
	.organization-detail__card-icon {
		width: 36px;
		height: 36px;
	}
	.organization-detail__card-icon :global(svg) {
		width: 20px;
		height: 20px;
	}
	.organization-detail__card-icon--success {
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
	}
	.organization-detail__card-icon--warning {
		color: var(--color-warning--onSurface);
		background: var(--color-warning--surface);
	}
	.organization-detail__card-icon--critical {
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.organization-detail__card-icon--inactive {
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
	}
	.organization-detail__card-label {
		margin-bottom: var(--space-smallest);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	.organization-workspace :global(.organization-detail__identity-card p:last-child),
	.organization-workspace :global(.organization-detail__lifecycle-card p:last-child),
	.organization-workspace :global(.organization-detail__next-card p:last-child) {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-workspace dl {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-small);
		margin: 0;
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-workspace dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-workspace dd {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		overflow-wrap: anywhere;
	}
	.organization-detail__status-line {
		display: grid;
		gap: var(--space-small);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail__status-line > span {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.organization-detail__safe-label {
		width: fit-content;
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-large);
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__at-a-glance {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-detail__at-a-glance :global(.skeleton--card) {
		height: 104px;
	}
	.organization-detail__at-a-glance article {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}
	.organization-detail__mini-icon {
		flex: 0 0 32px;
		width: 32px;
		height: 32px;
	}
	.organization-detail__mini-icon :global(svg) {
		width: 18px;
		height: 18px;
	}
	.organization-detail__at-a-glance div {
		min-width: 0;
	}
	.organization-detail__at-a-glance p,
	.organization-detail__at-a-glance small {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.organization-detail__at-a-glance strong,
	.organization-detail__at-a-glance small {
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
		.organization-detail__at-a-glance {
			grid-template-columns: 1fr;
		}
	}
	@media (max-width: 639px) {
		.organization-detail__overview-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
