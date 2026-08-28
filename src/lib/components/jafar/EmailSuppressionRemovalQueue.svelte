<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';

	type PendingRequest = {
		id: string;
		suppression_id: string;
		organization_id: string;
		organization_name: string;
		recipient_email: string;
		suppression_reason: 'complaint' | 'hard_bounce';
		requested_by_email: string;
		request_reason: string;
		request_evidence: string;
		created_at: string;
		suppression_created_at: string | null;
	};
	type DecidedRequest = {
		id: string;
		organization_name: string;
		recipient_email: string;
		status: 'approved' | 'denied';
		decided_by_email: string;
		decided_at: string;
		decision_note: string | null;
	};
	type QueueResponse = {
		pending: PendingRequest[];
		pending_total: number;
		recently_decided: DecidedRequest[];
		error?: string;
	};

	const queueKey = ['jafar', 'communications', 'suppression-removals'] as const;
	const queryClient = useQueryClient();
	const toast = getToastManager();

	const queueQuery = createQuery<QueueResponse>(() => ({
		queryKey: queueKey,
		queryFn: async () => {
			const response = await fetch('/api/jafar/communications/suppression-removals');
			const result = (await response.json()) as QueueResponse;
			if (!response.ok) throw new Error(result.error ?? 'The removal queue could not be loaded.');
			return result;
		},
		staleTime: 30_000
	}));

	const pending = $derived(queueQuery.data?.pending ?? []);
	const decided = $derived(queueQuery.data?.recently_decided ?? []);
	const overCap = $derived((queueQuery.data?.pending_total ?? 0) > pending.length);

	let dialog = $state<{ request: PendingRequest; decision: 'approve' | 'deny' } | null>(null);
	let note = $state('');
	const noteValid = $derived(dialog?.decision === 'approve' || note.trim().length >= 1);

	function openDialog(request: PendingRequest, decision: 'approve' | 'deny') {
		dialog = { request, decision };
		note = '';
	}

	const decideMutation = createMutation<QueueResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!dialog) throw new Error('No request selected.');
			const response = await fetch(
				`/api/jafar/communications/suppression-removals/${dialog.request.id}`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({
						decision: dialog.decision,
						note: note.trim() || undefined
					})
				}
			);
			const result = (await response.json()) as QueueResponse & { error?: string };
			if (!response.ok)
				throw new Error(result.error ?? 'The removal request could not be updated.');
			return result;
		},
		onSuccess: (result) => {
			queryClient.setQueryData<QueueResponse>(queueKey, {
				pending: result.pending,
				pending_total: result.pending_total,
				recently_decided: result.recently_decided
			});
			const approved = dialog?.decision === 'approve';
			dialog = null;
			toast.success(
				approved ? 'Removal approved. The address is unblocked.' : 'Removal request denied.'
			);
		},
		onError: (error) => toast.error(error.message)
	}));

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}
</script>

<Card class="suppression-queue">
	<div class="suppression-queue__head">
		<div>
			<h2>Spam-complaint removal requests</h2>
			<p>
				An organization admin cleared a hard bounce themselves. A spam complaint needs your decision
				before that address can be emailed again.
			</p>
		</div>
		<Badge status={pending.length > 0 ? 'warning' : 'success'} dot={false}>
			{pending.length} waiting
		</Badge>
	</div>

	{#if queueQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading removal requests" />
	{:else if queueQuery.isError}
		<ErrorState
			title="Removal requests could not be loaded"
			description={queueQuery.error instanceof Error ? queueQuery.error.message : 'Try again.'}
			retry={() => queueQuery.refetch()}
		/>
	{:else if pending.length === 0}
		<EmptyState
			title="No requests waiting"
			description="Complaint-suppression removal requests from contractors show up here."
		/>
	{:else}
		{#if overCap}
			<p class="suppression-queue__notice" role="status">
				Showing the {pending.length} oldest of {queueQuery.data?.pending_total} pending requests.
			</p>
		{/if}
		<ul class="suppression-queue__list">
			{#each pending as request (request.id)}
				<li class="suppression-queue__item">
					<div class="suppression-queue__item-head">
						<div>
							<strong>{request.recipient_email}</strong>
							<a href={resolve(`/jafar/organizations/${request.organization_id}`)}>
								{request.organization_name}
							</a>
						</div>
						<Badge status="critical" dot={false}>Spam complaint</Badge>
					</div>
					<dl class="suppression-queue__detail">
						<div>
							<dt>Requested by</dt>
							<dd>{request.requested_by_email} · {formatDate(request.created_at)}</dd>
						</div>
						<div>
							<dt>Reason given</dt>
							<dd>{request.request_reason}</dd>
						</div>
						<div>
							<dt>Evidence of verification</dt>
							<dd>{request.request_evidence}</dd>
						</div>
					</dl>
					<div class="suppression-queue__item-actions">
						<Button size="small" variation="work" onclick={() => openDialog(request, 'approve')}>
							Approve &amp; unblock
						</Button>
						<Button
							size="small"
							variant="secondary"
							variation="subtle"
							onclick={() => openDialog(request, 'deny')}
						>
							Deny
						</Button>
					</div>
				</li>
			{/each}
		</ul>
	{/if}

	{#if decided.length > 0}
		<details class="suppression-queue__history">
			<summary>Recently decided ({decided.length})</summary>
			<ul class="suppression-queue__list">
				{#each decided as request (request.id)}
					<li class="suppression-queue__item suppression-queue__item--compact">
						<div class="suppression-queue__item-head">
							<div>
								<strong>{request.recipient_email}</strong>
								<span>{request.organization_name}</span>
							</div>
							<Badge status={request.status === 'approved' ? 'success' : 'inactive'} dot={false}>
								{request.status === 'approved' ? 'Approved' : 'Denied'}
							</Badge>
						</div>
						<p class="suppression-queue__history-meta">
							{request.decided_by_email} · {formatDate(request.decided_at)}
							{#if request.decision_note}
								<span> — {request.decision_note}</span>
							{/if}
						</p>
					</li>
				{/each}
			</ul>
		</details>
	{/if}
</Card>

<ConfirmDialog
	open={dialog !== null}
	title={dialog?.decision === 'approve' ? 'Approve removal' : 'Deny removal'}
	tone={dialog?.decision === 'approve' ? 'success' : 'default'}
	confirmLabel={dialog?.decision === 'approve' ? 'Approve & unblock' : 'Deny request'}
	loading={decideMutation.isPending}
	confirmDisabled={!noteValid || decideMutation.isPending}
	onConfirm={() => {
		if (noteValid) decideMutation.mutate();
	}}
	onClose={() => {
		if (!decideMutation.isPending) dialog = null;
	}}
>
	{#if dialog}
		<p>
			{#if dialog.decision === 'approve'}
				<strong>{dialog.request.recipient_email}</strong> is unblocked for
				{dialog.request.organization_name}. Their email to this address can send again. This does
				not release any mail already cancelled while it was blocked.
			{:else}
				<strong>{dialog.request.recipient_email}</strong> stays blocked for
				{dialog.request.organization_name}. Add a note the requester will see.
			{/if}
		</p>
		<Textarea
			id="suppression-decision-note"
			label={dialog.decision === 'approve' ? 'Note (optional)' : 'Reason for denial'}
			bind:value={note}
			rows={3}
			maxlength={1000}
			required={dialog.decision === 'deny'}
		/>
	{/if}
</ConfirmDialog>

<style lang="scss">
	:global(.suppression-queue) {
		display: grid;
		gap: var(--space-base);
	}
	.suppression-queue__head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);

		h2 {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-largest);
			line-height: var(--typography--lineHeight-tightest);
		}
		p {
			margin: var(--space-small) 0 0;
			max-width: 62ch;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}
	}
	.suppression-queue__notice {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.suppression-queue__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.suppression-queue__item {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.suppression-queue__item--compact {
		gap: var(--space-smallest);
	}
	.suppression-queue__item-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);

		strong {
			display: block;
			color: var(--color-heading);
		}
		a,
		span {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		a {
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}
		}
	}
	.suppression-queue__detail {
		display: grid;
		gap: var(--space-small);
		margin: 0;

		> div {
			display: grid;
			gap: var(--space-smallest);
		}
		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			text-transform: uppercase;
			letter-spacing: var(--typography--letterSpacing-loose);
		}
		dd {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}
	}
	.suppression-queue__item-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.suppression-queue__history {
		border-top: var(--border-base) solid var(--color-border);
		padding-top: var(--space-base);

		summary {
			cursor: pointer;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}
		.suppression-queue__list {
			margin-top: var(--space-base);
		}
	}
	.suppression-queue__history-meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
		overflow-wrap: anywhere;
	}
	@media (max-width: 639px) {
		.suppression-queue__head,
		.suppression-queue__item-head {
			flex-direction: column;
		}
	}
</style>
