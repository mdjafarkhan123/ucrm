<script lang="ts">
	import type {
		EffectiveAccess,
		CommercialState,
		TeamResponse,
		HistoryResponse,
		OperationListResponse,
		OperationAttempt
	} from '$lib/components/jafar/organization/types';
	import type { CreateQueryResult } from '@tanstack/svelte-query';
	import type { OrganizationDetailPreview } from '$lib/jafar/organization-detail-preview';
	import { resolve } from '$app/paths';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import { AlertDialog } from 'bits-ui';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ClosureActions from '$lib/components/jafar/ClosureActions.svelte';
	import LegacyReconcileActions from '$lib/components/jafar/LegacyReconcileActions.svelte';
	import LifecycleActions from '$lib/components/jafar/LifecycleActions.svelte';
	import { formatDateTime } from './format';
	let {
		access,
		preview,
		commercialQuery,
		teamQuery,
		historyQuery,
		organizationOperationsQuery,
		applicationOperationsQuery,
		attentionOperations,
		applicationId
	}: {
		access: EffectiveAccess | null;
		preview: OrganizationDetailPreview | null;
		commercialQuery: CreateQueryResult<CommercialState, Error>;
		teamQuery: CreateQueryResult<TeamResponse, Error>;
		historyQuery: CreateQueryResult<HistoryResponse, Error>;
		organizationOperationsQuery: CreateQueryResult<OperationListResponse, Error>;
		applicationOperationsQuery: CreateQueryResult<OperationListResponse, Error>;
		attentionOperations: OperationAttempt[];
		applicationId: string | null;
	} = $props();

	const HISTORY_EVENT_LABELS: Record<string, string> = {
		'organization.lifecycle_changed': 'Status changed',
		'package.updated': 'Package changed',
		'package.legacy_assigned': 'Legacy package assigned',
		'feature_override.updated': 'Feature override changed',
		'feature_override.inherited': 'Feature override cleared',
		'limit_override.updated': 'Seat limit override changed',
		'limit_override.inherited': 'Seat limit override cleared',
		'free_access.grant': 'Free access granted',
		'free_access.extend': 'Free access extended',
		'free_access.convert_to_forever': 'Free access converted to forever',
		'free_access.end': 'Free access ended',
		'commercial.initial_payment_confirmed': 'Initial payment confirmed',
		'commercial.renewal_confirmed': 'Renewal recorded',
		'commercial.payment_correction_recorded': 'Payment correction recorded',
		'commercial.refund_recorded': 'Refund recorded',
		'commercial.payment_reversal_recorded': 'Payment reversal recorded',
		'commercial.organization_suspended': 'Organization suspended',
		'commercial.organization_reactivated': 'Organization reactivated',
		'commercial.package_version_changed': 'Package version changed',
		'commercial.feature_exception_changed': 'Feature exception changed',
		'commercial.limit_exception_changed': 'Limit exception changed',
		'commercial.pending_setup_resolved': 'Legacy organization reviewed',
		'onboarding_application.provisioned': 'Organization provisioned from application',
		'onboarding_application.reviewed': 'Application marked reviewed',
		'onboarding_application.corrected': 'Application corrected',
		'onboarding_application.payment_confirmed': 'Application payment confirmed',
		'onboarding_application.payment_reversed': 'Application payment reversed',
		'onboarding_application.package_corrected': 'Application package corrected',
		'onboarding_application.duplicate_acknowledged': 'Marked not a duplicate',
		'onboarding_application.not_proceeding': 'Application marked not proceeding',
		'organization_member.profile_corrected': 'Team member profile corrected',
		'organization_member.administrator_email_recovered': 'Administrator email recovered'
	};

	const OPERATION_TYPE_LABELS: Record<string, string> = {
		setup_email_delivery: 'Setup email delivery',
		outbox_email_delivery: 'Queued email delivery',
		onboarding_application_provisioning: 'Organization provisioning'
	};
	const OPERATION_STATUS_LABELS: Record<string, string> = {
		pending: 'Pending',
		retrying: 'Retrying',
		acknowledged: 'Acknowledged'
	};

	let confirmationOpen = $state(false);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<TabPanel value="activity">
	<div class="organization-workspace">
		{#if preview}
			<section class="organization-detail__section" aria-labelledby="history-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">History and recovery</p>
					<h2 id="history-title">Owner-private activity</h2>
					<p>
						History remains sanitized: it never includes passwords, credentials, setup links, or raw
						provider evidence.
					</p>
				</div>
				<div class="organization-detail__history-grid">
					<Card class="organization-detail__history-card">
						<div class="organization-detail__history-heading">
							<span class="organization-detail__card-icon">{@html historyIcon}</span>
							<div>
								<h3>Recent history</h3>
								<p>Representative development records</p>
							</div>
						</div>
						<ul class="organization-detail__history-list">
							{#each preview?.history ?? [] as item (`${item.at}-${item.title}`)}<li>
									<span
										class="organization-detail__history-dot organization-detail__history-dot--{item.tone}"
										aria-hidden="true"
									></span>
									<div>
										<strong>{item.title}</strong>
										<p>{item.detail}</p>
									</div>
									<time>{item.at}</time>
								</li>{/each}
						</ul>
					</Card>
					<Card class="organization-detail__recovery-card">
						<div
							class="organization-detail__card-icon organization-detail__card-icon--{preview
								?.recovery.tone}"
						>
							{@html clockIcon}
						</div>
						<div>
							<p class="organization-detail__card-label">Recovery state</p>
							<h3>{preview?.recovery.state}</h3>
							<p>{preview?.recovery.detail}</p>
						</div>
						<AlertDialog.Root bind:open={confirmationOpen}>
							<AlertDialog.Trigger>
								{#snippet child({ props })}<Button {...props} variant="secondary" variation="subtle"
										>Preview confirmation</Button
									>{/snippet}
							</AlertDialog.Trigger>
							<AlertDialog.Portal>
								<AlertDialog.Overlay class="organization-detail__dialog-overlay" />
								<AlertDialog.Content class="organization-detail__dialog-content">
									<AlertDialog.Title level={2}>Review a recovery action</AlertDialog.Title>
									<AlertDialog.Description
										>This is a development-only confirmation preview. It cannot retry, acknowledge,
										or change any organization record.</AlertDialog.Description
									>
									<dl class="organization-detail__dialog-summary">
										<div>
											<dt>Organization</dt>
											<dd>{preview?.name}</dd>
										</div>
										<div>
											<dt>Current state</dt>
											<dd>{preview?.recovery.state}</dd>
										</div>
										<div>
											<dt>Future live safeguard</dt>
											<dd>Reason and a secure audit record</dd>
										</div>
									</dl>
									<div class="organization-detail__dialog-actions">
										<AlertDialog.Action
											>{#snippet child({ props })}<Button {...props}>I understand</Button
												>{/snippet}</AlertDialog.Action
										><AlertDialog.Cancel
											>{#snippet child({ props })}<Button
													{...props}
													variant="secondary"
													variation="subtle">Close</Button
												>{/snippet}</AlertDialog.Cancel
										>
									</div>
								</AlertDialog.Content>
							</AlertDialog.Portal>
						</AlertDialog.Root>
					</Card>
				</div>
			</section>
		{:else if access}
			<section class="organization-detail__section" aria-labelledby="lifecycle-controls-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Organization controls</p>
					<h2 id="lifecycle-controls-title">Lifecycle administration</h2>
					<p>
						Suspend, restore, or close the organization only after reviewing its current access and
						recovery state.
					</p>
				</div>
				<Card class="organization-detail__lifecycle-controls">
					<div>
						<p class="organization-detail__card-label">Current lifecycle</p>
						<h3>{access.organization.lifecycle_status}</h3>
					</div>
					<div class="organization-detail__status-line">
						{#if access.organization.lifecycle_status === 'pending_setup'}
							<LegacyReconcileActions organizationId={access.organization.id} />
						{:else}
							{#if access.organization.lifecycle_status !== 'pending_closure' && access.organization.lifecycle_status !== 'closed'}
								<LifecycleActions
									organizationId={access.organization.id}
									lifecycleStatus={access.organization.lifecycle_status}
								/>
							{/if}
							<ClosureActions
								organizationId={access.organization.id}
								organizationName={access.organization.name}
								lifecycleStatus={access.organization.lifecycle_status}
								closure={commercialQuery.data?.closure ?? null}
							/>
						{/if}
					</div>
				</Card>
			</section>

			<section class="organization-detail__section" aria-labelledby="attention-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">Needs attention</p>
					<h2 id="attention-title">Open recovery items</h2>
					<p>Background work that has not succeeded yet for this organization.</p>
				</div>
				<Card class="organization-detail__history-card">
					{#if organizationOperationsQuery.isPending || (applicationId && applicationOperationsQuery.isPending)}
						<LoadingSkeleton variant="table" label="Loading open recovery items" />
					{:else if organizationOperationsQuery.isError || (applicationId && applicationOperationsQuery.isError)}
						<ErrorState
							title="Open recovery items could not be loaded"
							description={organizationOperationsQuery.error instanceof Error
								? organizationOperationsQuery.error.message
								: applicationOperationsQuery.error instanceof Error
									? applicationOperationsQuery.error.message
									: 'Open recovery items could not be loaded. Try again.'}
							retry={() => {
								organizationOperationsQuery.refetch();
								applicationOperationsQuery.refetch();
							}}
						/>
					{:else if attentionOperations.length === 0}
						<p class="organization-detail__muted">No open issues.</p>
					{:else}
						<div class="organization-detail__table-wrap">
							<table>
								<caption>Open recovery items</caption>
								<thead>
									<tr>
										<th scope="col">Type</th>
										<th scope="col">Status</th>
										<th scope="col">Attempts</th>
										<th scope="col">Updated</th>
										<th scope="col"><span class="organization-detail__sr-only">Open</span></th>
									</tr>
								</thead>
								<tbody>
									{#each attentionOperations as operation (operation.id)}
										<tr>
											<td
												>{OPERATION_TYPE_LABELS[operation.operation_type] ??
													operation.operation_type}</td
											>
											<td
												><Badge status="warning"
													>{OPERATION_STATUS_LABELS[operation.status] ?? operation.status}</Badge
												></td
											>
											<td>{operation.attempt_count}</td>
											<td>{formatDateTime(operation.updated_at)}</td>
											<td>
												<!-- The pathname is resolved; only the operation query is appended. -->
												<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
												<a href={`${resolve('/jafar/operations')}?operation=${operation.id}`}
													>View in Operations</a
												>
											</td>
										</tr>
									{/each}
								</tbody>
							</table>
						</div>
					{/if}
				</Card>
			</section>

			<section class="organization-detail__section" aria-labelledby="history-title">
				<div class="organization-detail__section-heading">
					<p class="organization-detail__eyebrow">History and recovery</p>
					<h2 id="history-title">Owner-private activity</h2>
					<p>Every commercial and status change made from this screen, most recent first.</p>
				</div>
				<Card class="organization-detail__history-card">
					{#if historyQuery.isPending}
						<LoadingSkeleton variant="table" label="Loading activity history" />
					{:else if historyQuery.isError}
						<ErrorState
							title="Activity history could not be loaded"
							description={historyQuery.error instanceof Error
								? historyQuery.error.message
								: 'Activity history could not be loaded. Try again.'}
							retry={() => historyQuery.refetch()}
						/>
					{:else}
						<div class="organization-detail__table-wrap">
							<table>
								<caption>Activity history</caption>
								<thead>
									<tr>
										<th scope="col">Change</th>
										<th scope="col">By</th>
										<th scope="col">When</th>
									</tr>
								</thead>
								<tbody>
									{#each historyQuery.data?.events ?? [] as historyEvent (historyEvent.id)}
										<tr>
											<td
												>{HISTORY_EVENT_LABELS[historyEvent.event_type] ??
													historyEvent.event_type}</td
											>
											<td>{historyEvent.actor_email ?? 'Not recorded'}</td>
											<td>{formatDateTime(historyEvent.occurred_at)}</td>
										</tr>
									{:else}
										<tr><td colspan="3">No activity has been recorded yet.</td></tr>
									{/each}
								</tbody>
							</table>
						</div>
					{/if}
				</Card>
			</section>
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
	.organization-workspace :global(.organization-detail__lifecycle-controls) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-large);
		border-color: var(--color-critical);
	}
	.organization-workspace
		:global(.organization-detail__lifecycle-controls .organization-detail__status-line) {
		flex: 0 1 520px;
	}
	.organization-detail__card-icon {
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
	.organization-detail__history-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__recovery-card) {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-workspace :global(.organization-detail__recovery-card p:last-child) {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__history-heading h3 {
		font-size: var(--typography--fontSize-large);
	}
	.organization-detail__history-heading p {
		max-width: 78ch;
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__history-heading {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
	}
	.organization-detail__table-wrap {
		overflow-x: auto;
	}
	.organization-workspace table {
		width: 100%;
		border-collapse: collapse;
		color: var(--color-text);
		text-align: left;
	}
	.organization-workspace caption {
		padding-bottom: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: left;
	}
	.organization-workspace th,
	.organization-workspace td {
		padding: var(--space-slim) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-base);
		vertical-align: top;
	}
	.organization-workspace th {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
	}
	.organization-workspace td:first-child {
		color: var(--color-heading);
		font-weight: 700;
	}
	.organization-workspace :global(.organization-detail__history-card) {
		display: grid;
		align-content: start;
		gap: var(--space-base);
	}
	.organization-detail__muted {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		margin: 0;
	}
	.organization-detail__sr-only {
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
	.organization-detail__history-list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.organization-detail__history-list li {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) auto;
		align-items: start;
		gap: var(--space-small);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.organization-detail__history-dot {
		width: var(--space-small);
		height: var(--space-small);
		margin-top: var(--space-smaller);
		border-radius: var(--radius-circle);
		background: var(--history-color);
	}
	.organization-detail__history-dot--success {
		--history-color: var(--color-success);
	}
	.organization-detail__history-dot--warning {
		--history-color: var(--color-warning);
	}
	.organization-detail__history-dot--critical {
		--history-color: var(--color-critical);
	}
	.organization-detail__history-dot--informative {
		--history-color: var(--color-informative);
	}
	.organization-detail__history-dot--inactive {
		--history-color: var(--color-inactive);
	}
	.organization-detail__history-list strong {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__history-list p {
		margin-top: var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.organization-detail__history-list time {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		white-space: nowrap;
	}
	.organization-workspace :global(.organization-detail__recovery-card > .button) {
		width: fit-content;
		margin-top: auto;
	}
	:global(.organization-detail__dialog-overlay) {
		position: fixed;
		inset: 0;
		z-index: var(--elevation-modal);
		background: var(--color-overlay);
	}
	:global(.organization-detail__dialog-content) {
		position: fixed;
		top: 50%;
		left: 50%;
		z-index: var(--elevation-modal);
		display: grid;
		gap: var(--space-base);
		width: min(calc(100vw - var(--space-large) * 2), 480px);
		max-height: calc(100dvh - var(--space-large) * 2);
		overflow: auto;
		padding: var(--space-large);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		color: var(--color-text);
		background: var(--color-surface);
		box-shadow: var(--shadow-high);
		transform: translate(-50%, -50%);
	}
	:global(.organization-detail__dialog-content [data-slot='alert-dialog-title']) {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-weight: 700;
		line-height: var(--typography--lineHeight-tightest);
	}
	:global(.organization-detail__dialog-content [data-slot='alert-dialog-description']) {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.organization-detail__dialog-summary {
		grid-template-columns: 1fr;
		gap: var(--space-base);
		padding-top: var(--space-base);
	}
	.organization-detail__dialog-summary dd {
		font-size: var(--typography--fontSize-base);
	}
	.organization-detail__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 767px) {
		.organization-workspace :global(.organization-detail__lifecycle-controls) {
			align-items: stretch;
			flex-direction: column;
		}
		.organization-workspace
			:global(.organization-detail__lifecycle-controls .organization-detail__status-line) {
			flex-basis: auto;
		}
	}
	@media (max-width: 639px) {
		.organization-detail__history-grid {
			grid-template-columns: 1fr;
		}
		.organization-detail__history-list li {
			grid-template-columns: auto minmax(0, 1fr);
		}
		.organization-detail__history-list time {
			grid-column: 2;
		}
	}
</style>
