<script lang="ts">
	import { resolve } from '$app/paths';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	type ClosingOrganization = {
		id: string;
		organization_id: string;
		reason: string;
		started_at: string;
		deadline_at: string;
		organizations: { name: string; slug: string } | null;
	};
	type UnfinishedDeletion = {
		operation_id: string;
		trigger_kind: string;
		status: string;
		component_results: Record<string, string> | null;
		retry_count: number;
		initiated_at: string;
		created_at: string;
	};
	type CleanupResponse = {
		closing_organizations: ClosingOrganization[];
		unfinished_deletions: UnfinishedDeletion[];
		error?: string;
	};
	type ClosureImpact = {
		active_reply_aliases: number;
		queued_messages: number;
		recent_replies: number;
	};
	type ImpactResponse = { impact: ClosureImpact | null; error?: string };
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};

	class EarlyDeleteError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'This organization could not be permanently deleted.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const cleanupQuery = createQuery<CleanupResponse>(() => ({
		queryKey: ['jafar', 'settings', 'cleanup'],
		queryFn: async () => {
			const response = await fetch('/api/jafar/settings/cleanup');
			const result = (await response.json()) as CleanupResponse;
			if (!response.ok) throw new Error(result.error ?? 'The cleanup queue could not be loaded.');
			return result;
		}
	}));

	let deleteTarget = $state<ClosingOrganization | null>(null);
	let typedName = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<{
		organization_id: string;
		typed_organization_name: string;
	} | null>(null);
	let retryingId = $state<string | null>(null);

	async function loadImpact(organizationId: string) {
		const response = await fetch(
			`/api/jafar/settings/cleanup/preview?organization_id=${organizationId}`
		);
		const result = (await response.json()) as ImpactResponse;
		if (!response.ok) throw new Error(result.error ?? 'The deletion impact could not be loaded.');
		return result;
	}

	// The impact preview is revealed content — it never loads with the page. Hovering "Delete now"
	// prefetches it, and a click that beats the fetch shows a skeleton inside the dialog.
	const impactQuery = createQuery<ImpactResponse>(() => ({
		queryKey: ['jafar', 'settings', 'cleanup', 'impact', deleteTarget?.organization_id ?? 'none'],
		queryFn: () => loadImpact(deleteTarget!.organization_id),
		enabled: deleteTarget !== null,
		staleTime: 30_000
	}));

	function prefetchImpact(organizationId: string) {
		void queryClient.prefetchQuery({
			queryKey: ['jafar', 'settings', 'cleanup', 'impact', organizationId],
			queryFn: () => loadImpact(organizationId),
			staleTime: 30_000
		});
	}

	function openDelete(target: ClosingOrganization) {
		deleteTarget = target;
		typedName = '';
		fieldErrors = {};
		feedbackError = '';
	}

	const componentLabels: Record<string, string> = {
		auth_users: 'Login accounts',
		provider_resources: 'Email provider resources'
	};

	function failedComponents(results: Record<string, string> | null) {
		if (!results) return [];
		return Object.entries(results)
			.filter(([, state]) => state === 'failed')
			.map(([key]) => componentLabels[key] ?? key.replace(/_/g, ' '));
	}

	function triggerLabel(kind: string) {
		return kind === 'early_manual' ? 'Early manual delete' : 'Scheduled deletion';
	}

	function closeDelete() {
		if (!deleteMutation.isPending) deleteTarget = null;
	}

	function daysRemaining(deadlineAt: string) {
		const ms = new Date(deadlineAt).getTime() - Date.now();
		return Math.max(0, Math.ceil(ms / (24 * 60 * 60 * 1000)));
	}

	function formatDateTime(value: string) {
		return new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
	}

	const deleteMutation = createMutation<
		MutationResponse,
		EarlyDeleteError,
		{ organization_id: string; typed_organization_name: string }
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch('/api/jafar/settings/cleanup', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new EarlyDeleteError(result);
			return result;
		},
		onMutate: () => {
			fieldErrors = {};
			feedbackError = '';
		},
		onError: (error, input) => {
			if (error.stepUpRequired) {
				pendingStepUpInput = input;
				reconfirmOpen = true;
				return;
			}
			fieldErrors = error.fieldErrors;
			feedbackError = error.message;
		},
		onSuccess: () => {
			deleteTarget = null;
			pendingStepUpInput = null;
			toast.success('Organization permanently deleted.');
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'settings', 'cleanup'] });
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations'] });
		}
	}));

	function submitDelete(event: SubmitEvent) {
		event.preventDefault();
		if (!deleteTarget) return;
		const errors: Record<string, string> = {};
		if (typedName.trim() !== deleteTarget.organizations?.name) {
			errors.typed_organization_name = 'Type the organization name exactly to confirm.';
		}
		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return;
		deleteMutation.mutate({
			organization_id: deleteTarget.organization_id,
			typed_organization_name: typedName.trim()
		});
	}

	function confirmStepUp() {
		if (pendingStepUpInput) deleteMutation.mutate(pendingStepUpInput);
	}

	const retryMutation = createMutation<{ resolved: boolean }, Error, string>(() => ({
		mutationFn: async (operationId) => {
			const response = await fetch('/api/jafar/settings/cleanup/retry', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({ operation_id: operationId })
			});
			const result = (await response.json()) as { resolved?: boolean; error?: string };
			if (!response.ok) throw new Error(result.error ?? 'The cleanup could not be retried.');
			return { resolved: result.resolved === true };
		},
		onSettled: () => {
			retryingId = null;
		},
		onSuccess: (result) => {
			if (result.resolved) toast.success('Cleanup finished. This deletion is fully complete.');
			else
				toast.error(
					'Some cleanup steps still failed. They will keep retrying automatically each night.'
				);
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'settings', 'cleanup'] });
		},
		onError: (error) => toast.error(error.message)
	}));

	function retryCleanup(operationId: string) {
		retryingId = operationId;
		retryMutation.mutate(operationId);
	}
</script>

<svelte:head><title>Cleanup · Settings · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="cleanup-queue">
	<nav class="cleanup-queue__breadcrumb" aria-label="Breadcrumb">
		<a href={resolve('/jafar/settings')}
			><span aria-hidden="true">{@html arrowLeftIcon}</span> Settings</a
		>
		<span aria-hidden="true">/</span>
		<span>Cleanup</span>
	</nav>

	<header class="cleanup-queue__header">
		<p class="cleanup-queue__eyebrow">Organization cleanup</p>
		<h1>Closing organizations</h1>
		<p class="cleanup-queue__description">
			Every organization currently in its 30-day recovery window. Each one restores automatically if
			nobody acts, or deletes for good at its deadline. Deleting one early here skips the rest of
			that wait and cannot be undone.
		</p>
	</header>

	{#if feedbackError}<p class="cleanup-queue__feedback" role="alert">{feedbackError}</p>{/if}

	<Card class="cleanup-queue__card">
		{#if cleanupQuery.isPending}
			<LoadingSkeleton variant="table" label="Loading the cleanup queue" />
		{:else if cleanupQuery.isError}
			<ErrorState
				title="The cleanup queue could not be loaded"
				description={cleanupQuery.error instanceof Error
					? cleanupQuery.error.message
					: 'The cleanup queue could not be loaded. Try again.'}
				retry={() => cleanupQuery.refetch()}
			/>
		{:else if (cleanupQuery.data?.closing_organizations.length ?? 0) === 0}
			<p class="cleanup-queue__muted">No organization is currently closing.</p>
		{:else}
			<div class="cleanup-queue__table-wrap">
				<table>
					<caption>Closing organizations</caption>
					<thead>
						<tr>
							<th scope="col">Organization</th>
							<th scope="col">Reason</th>
							<th scope="col">Deletes at</th>
							<th scope="col">Remaining</th>
							<th scope="col"><span class="cleanup-queue__sr-only">Delete now</span></th>
						</tr>
					</thead>
					<tbody>
						{#each cleanupQuery.data?.closing_organizations ?? [] as record (record.id)}
							<tr>
								<td>
									<a
										href={resolve('/jafar/(protected)/organizations/[organizationId]', {
											organizationId: record.organization_id
										})}>{record.organizations?.name ?? 'Unknown organization'}</a
									>
								</td>
								<td>{record.reason}</td>
								<td>{formatDateTime(record.deadline_at)}</td>
								<td
									><Badge status="critical"
										>{daysRemaining(record.deadline_at)} day{daysRemaining(record.deadline_at) === 1
											? ''
											: 's'}</Badge
									></td
								>
								<td>
									<Button
										size="small"
										variant="secondary"
										variation="destructive"
										onhover={() => prefetchImpact(record.organization_id)}
										onclick={() => openDelete(record)}>Delete now</Button
									>
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</Card>

	{#if (cleanupQuery.data?.unfinished_deletions.length ?? 0) > 0}
		<section class="cleanup-queue__section" aria-labelledby="unfinished-heading">
			<div class="cleanup-queue__section-head">
				<h2 id="unfinished-heading">Unfinished deletions</h2>
				<p>
					These organizations were deleted, but a step outside our database — removing login
					accounts or email-provider resources — did not finish. Each retries automatically every
					night; retry here to push it again now.
				</p>
			</div>
			<Card class="cleanup-queue__card">
				<ul class="cleanup-queue__deletions">
					{#each cleanupQuery.data?.unfinished_deletions ?? [] as receipt (receipt.operation_id)}
						<li class="cleanup-queue__deletion">
							<div class="cleanup-queue__deletion-body">
								<div class="cleanup-queue__deletion-head">
									<strong>{triggerLabel(receipt.trigger_kind)}</strong>
									<Badge status="critical">Cleanup failed</Badge>
								</div>
								<p class="cleanup-queue__deletion-meta">
									Deleted {formatDateTime(receipt.created_at)}
									{#if receipt.retry_count > 0}· retried {receipt.retry_count}
										time{receipt.retry_count === 1 ? '' : 's'}{/if}
								</p>
								{#if failedComponents(receipt.component_results).length > 0}
									<p class="cleanup-queue__deletion-meta">
										Still to remove: {failedComponents(receipt.component_results).join(', ')}
									</p>
								{/if}
							</div>
							<Button
								size="small"
								variation="work"
								loading={retryMutation.isPending && retryingId === receipt.operation_id}
								disabled={retryMutation.isPending}
								onclick={() => retryCleanup(receipt.operation_id)}>Retry cleanup</Button
							>
						</li>
					{/each}
				</ul>
			</Card>
		</section>
	{/if}
</main>
<!-- eslint-enable svelte/no-at-html-tags -->

<Dialog open={deleteTarget !== null} title="Permanently delete organization" onClose={closeDelete}>
	<form class="cleanup-queue__form" onsubmit={submitDelete}>
		<p>
			<strong>This skips the remaining recovery time and deletes everything right now.</strong> All
			customers, jobs, invoices, files, and login access for
			{deleteTarget?.organizations?.name ?? 'this organization'} are removed for good. There is no undo.
		</p>

		<div class="cleanup-queue__impact" aria-live="polite">
			<p class="cleanup-queue__impact-title">Live communications this ends immediately</p>
			{#if impactQuery.isPending}
				<LoadingSkeleton variant="text" label="Loading deletion impact" />
			{:else if impactQuery.isError}
				<p class="cleanup-queue__impact-error">
					The impact could not be loaded. You can still delete, but review carefully.
				</p>
			{:else if impactQuery.data?.impact}
				{@const impact = impactQuery.data.impact}
				<ul class="cleanup-queue__impact-list">
					<li><strong>{impact.active_reply_aliases}</strong> active reply aliases stop routing</li>
					<li><strong>{impact.queued_messages}</strong> queued messages are dropped unsent</li>
					<li>
						<strong>{impact.recent_replies}</strong> replies received since closing are erased
					</li>
				</ul>
			{/if}
		</div>

		<Input
			id="cleanup-typed-name"
			label={`Type "${deleteTarget?.organizations?.name ?? ''}" to confirm`}
			bind:value={typedName}
			invalid={Boolean(fieldErrors.typed_organization_name)}
			errorMessage={fieldErrors.typed_organization_name}
		/>
		<div class="cleanup-queue__dialog-actions">
			<Button type="submit" variation="destructive" loading={deleteMutation.isPending}
				>Permanently delete</Button
			>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDelete}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm permanent deletion"
	description="Permanently deleting an organization requires a recent password reconfirmation."
	confirmLabel="Permanently delete"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.cleanup-queue {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}
	.cleanup-queue__breadcrumb {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.cleanup-queue__breadcrumb a {
		display: inline-flex;
		align-items: center;
		gap: var(--space-smallest);
		color: var(--color-interactive);
		text-decoration: none;
	}
	.cleanup-queue__breadcrumb a:hover {
		text-decoration: underline;
	}
	.cleanup-queue__breadcrumb :global(svg) {
		width: 16px;
		height: 16px;
	}
	.cleanup-queue__header {
		padding-bottom: var(--space-large);
		border-bottom: var(--border-base) solid var(--color-border);
	}
	.cleanup-queue__eyebrow {
		margin: 0 0 var(--space-small);
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: var(--typography--letterSpacing-loose);
		text-transform: uppercase;
	}
	h1 {
		margin: 0;
		color: var(--color-heading);
		font-family: var(--typography--fontFamily-display);
		font-size: var(--typography--fontSize-jumbo);
		font-weight: 900;
		line-height: var(--typography--lineHeight-minuscule);
	}
	.cleanup-queue__description {
		max-width: 65ch;
		margin: var(--space-small) 0 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.cleanup-queue__feedback {
		margin: 0;
		padding: var(--space-small) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-critical--onSurface);
		background: var(--color-critical--surface);
	}
	.cleanup-queue__muted {
		margin: 0;
		color: var(--color-text--secondary);
	}
	.cleanup-queue__table-wrap {
		overflow-x: auto;
	}
	.cleanup-queue__table-wrap table {
		width: 100%;
		border-collapse: collapse;
	}
	.cleanup-queue__table-wrap caption {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
	}
	.cleanup-queue__table-wrap th,
	.cleanup-queue__table-wrap td {
		padding: var(--space-small) var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);
		text-align: left;
		vertical-align: middle;
	}
	.cleanup-queue__table-wrap th {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}
	.cleanup-queue__sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
	}
	.cleanup-queue__form {
		display: grid;
		gap: var(--space-base);
	}
	.cleanup-queue__form > p {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.cleanup-queue__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.cleanup-queue__section {
		display: grid;
		gap: var(--space-base);
	}
	.cleanup-queue__section-head h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	.cleanup-queue__section-head p {
		max-width: 65ch;
		margin: var(--space-small) 0 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
	}
	.cleanup-queue__deletions {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.cleanup-queue__deletion {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.cleanup-queue__deletion-body {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}
	.cleanup-queue__deletion-head {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.cleanup-queue__deletion-head strong {
		color: var(--color-heading);
	}
	.cleanup-queue__deletion-meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.cleanup-queue__impact {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-critical--surface);
	}
	.cleanup-queue__impact-title {
		margin: 0;
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-smaller);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: var(--typography--letterSpacing-loose);
	}
	.cleanup-queue__impact-list {
		display: grid;
		gap: var(--space-smallest);
		margin: 0;
		padding-left: var(--space-base);
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
	}
	.cleanup-queue__impact-list strong {
		font-variant-numeric: tabular-nums;
	}
	.cleanup-queue__impact-error {
		margin: 0;
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
	}
	@media (max-width: 639px) {
		.cleanup-queue__deletion {
			flex-direction: column;
		}
	}
</style>
