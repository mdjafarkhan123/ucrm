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
	type CleanupResponse = { closing_organizations: ClosingOrganization[]; error?: string };
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
	let pendingStepUpInput = $state<{ organization_id: string; typed_organization_name: string } | null>(
		null
	);

	function openDelete(target: ClosingOrganization) {
		deleteTarget = target;
		typedName = '';
		fieldErrors = {};
		feedbackError = '';
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
			Every organization currently in its 30-day recovery window. Each one restores automatically
			if nobody acts, or deletes for good at its deadline. Deleting one early here skips the rest
			of that wait and cannot be undone.
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
									<a href={`${resolve('/jafar/organizations')}/${record.organization_id}`}
										>{record.organizations?.name ?? 'Unknown organization'}</a
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
</main>
<!-- eslint-enable svelte/no-at-html-tags -->

<Dialog
	open={deleteTarget !== null}
	title="Permanently delete organization"
	onClose={closeDelete}
>
	<form class="cleanup-queue__form" onsubmit={submitDelete}>
		<p>
			<strong>This skips the remaining recovery time and deletes everything right now.</strong> All
			customers, jobs, invoices, files, and login access for
			{deleteTarget?.organizations?.name ?? 'this organization'} are removed for good. There is no
			undo.
		</p>
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
</style>
