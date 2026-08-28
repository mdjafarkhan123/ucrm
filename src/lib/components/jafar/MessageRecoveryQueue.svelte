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

	type QueuedMessage = {
		delivery_intent_id: string;
		organization_id: string;
		organization_name: string;
		subject: string;
		recipient_email: string;
		send_kind: string;
		allowance_class: string;
		intent_status: string;
		outbox_status: string;
		attempt_count: number;
		available_at: string | null;
		failure_code: string | null;
		last_error: string | null;
		updated_at: string;
		created_at: string;
	};
	type QueueResponse = {
		messages: QueuedMessage[];
		held_total: number;
		waiting_total: number;
		error?: string;
	};
	type HistoryEvent = {
		id: string;
		event_kind: string;
		occurred_at: string;
		last_occurred_at: string | null;
		repeat_count: number;
		attempt_number: number | null;
		reason_code: string | null;
		reason_message: string | null;
		retry_at: string | null;
		actor_kind: string;
		actor_email: string | null;
		actor_name: string | null;
		related_intent_id: string | null;
		related_inbound_message_id: string | null;
	};
	type HistoryResponse = {
		message: { subject: string; recipient_email: string; organization_name: string };
		events: HistoryEvent[];
		error?: string;
	};

	const queueKey = ['jafar', 'communications', 'messages'] as const;
	const historyKey = (intentId: string) => [...queueKey, intentId] as const;
	const queryClient = useQueryClient();
	const toast = getToastManager();

	async function loadQueue() {
		const response = await fetch('/api/jafar/communications/messages');
		const result = (await response.json()) as QueueResponse;
		if (!response.ok) throw new Error(result.error ?? 'The recovery queue could not be loaded.');
		return result;
	}

	async function loadHistory(intentId: string) {
		const response = await fetch(`/api/jafar/communications/messages/${intentId}`);
		const result = (await response.json()) as HistoryResponse;
		if (!response.ok) throw new Error(result.error ?? 'The message history could not be loaded.');
		return result;
	}

	const queueQuery = createQuery<QueueResponse>(() => ({
		queryKey: queueKey,
		queryFn: loadQueue,
		staleTime: 30_000
	}));

	const messages = $derived(queueQuery.data?.messages ?? []);
	const heldTotal = $derived(queueQuery.data?.held_total ?? 0);
	const waitingTotal = $derived(queueQuery.data?.waiting_total ?? 0);
	const overCap = $derived(heldTotal + waitingTotal > messages.length);

	// The timeline is revealed content, so it never loads with the page: hovering the control starts it,
	// and a click that beats the fetch gets a skeleton.
	let openIntentId = $state<string | null>(null);

	const historyQuery = createQuery<HistoryResponse>(() => ({
		queryKey: historyKey(openIntentId ?? 'none'),
		queryFn: () => loadHistory(openIntentId as string),
		enabled: openIntentId !== null,
		staleTime: 30_000
	}));

	function prefetchHistory(intentId: string) {
		void queryClient.prefetchQuery({
			queryKey: historyKey(intentId),
			queryFn: () => loadHistory(intentId),
			staleTime: 30_000
		});
	}

	function toggleTimeline(intentId: string) {
		openIntentId = openIntentId === intentId ? null : intentId;
	}

	let dialog = $state<{ message: QueuedMessage; action: 'retry' | 'cancel' } | null>(null);
	let reason = $state('');
	const reasonValid = $derived(reason.trim().length >= 3);

	function openDialog(message: QueuedMessage, action: 'retry' | 'cancel') {
		dialog = { message, action };
		reason = '';
	}

	const actionMutation = createMutation<QueueResponse, Error, void>(() => ({
		mutationFn: async () => {
			if (!dialog) throw new Error('No message selected.');
			const response = await fetch(
				`/api/jafar/communications/messages/${dialog.message.delivery_intent_id}`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ action: dialog.action, reason: reason.trim() })
				}
			);
			const result = (await response.json()) as QueueResponse;
			if (!response.ok) throw new Error(result.error ?? 'The message could not be updated.');
			return result;
		},
		onSuccess: (result) => {
			queryClient.setQueryData<QueueResponse>(queueKey, {
				messages: result.messages,
				held_total: result.held_total,
				waiting_total: result.waiting_total
			});
			const acted = dialog;
			dialog = null;
			if (acted) {
				void queryClient.invalidateQueries({
					queryKey: historyKey(acted.message.delivery_intent_id)
				});
				toast.success(
					acted.action === 'retry'
						? 'The message is back in the queue. Every check runs again before it sends.'
						: 'The message is cancelled and its allowance is back.'
				);
			}
		},
		onError: (error) => toast.error(error.message)
	}));

	const eventLabels: Record<string, string> = {
		queued: 'Queued',
		claimed: 'Picked up to send',
		sent: 'Handed to the provider',
		send_failed: 'Send failed',
		deferred: 'Deferred',
		held: 'Held for review',
		cancelled: 'Cancelled',
		resent: 'Sent again',
		replied: 'Customer replied',
		delivered: 'Delivered',
		hard_bounce: 'Hard bounce',
		soft_bounce: 'Soft bounce',
		complaint: 'Marked as spam',
		administrative_intervention: 'Owner intervention'
	};

	function humanize(value: string) {
		return value.replace(/_/g, ' ').replace(/^./, (character) => character.toUpperCase());
	}

	function eventLabel(kind: string) {
		return eventLabels[kind] ?? humanize(kind);
	}

	function eventTone(kind: string) {
		if (kind === 'delivered' || kind === 'sent' || kind === 'replied') return 'success';
		if (kind === 'hard_bounce' || kind === 'complaint' || kind === 'send_failed') return 'critical';
		if (kind === 'deferred' || kind === 'held' || kind === 'soft_bounce') return 'warning';
		return 'inactive';
	}

	function statusTone(message: QueuedMessage) {
		return message.outbox_status === 'failed' ? 'critical' : 'warning';
	}

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	function actorLine(event: HistoryEvent) {
		const who = event.actor_name ?? event.actor_email;
		if (event.actor_kind === 'system') return 'System';
		if (event.actor_kind === 'provider') return 'Email provider';
		if (event.actor_kind === 'recipient') return who ?? 'Recipient';
		if (event.actor_kind === 'platform_owner') return `Platform owner${who ? ` · ${who}` : ''}`;
		return who ?? humanize(event.actor_kind);
	}
</script>

<Card class="message-recovery">
	<div class="message-recovery__head">
		<div>
			<h2>Messages that stopped moving</h2>
			<p>
				Mail that failed or is waiting on a problem, newest first. Open one to read its whole story,
				then send it on its way again or stop it for good. A retry hands the message back to the
				sender — it never skips a check.
			</p>
		</div>
		<Badge
			status={heldTotal > 0 ? 'critical' : waitingTotal > 0 ? 'warning' : 'success'}
			dot={false}
		>
			{heldTotal} held · {waitingTotal} waiting
		</Badge>
	</div>

	{#if queueQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading stuck messages" />
	{:else if queueQuery.isError}
		<ErrorState
			title="The recovery queue could not be loaded"
			description={queueQuery.error instanceof Error ? queueQuery.error.message : 'Try again.'}
			retry={() => queueQuery.refetch()}
		/>
	{:else if messages.length === 0}
		<EmptyState
			title="Everything is moving"
			description="Messages that fail or stall show up here with their full history."
		/>
	{:else}
		{#if overCap}
			<p class="message-recovery__notice" role="status">
				Showing the {messages.length} most recent of {heldTotal + waitingTotal} messages needing attention.
			</p>
		{/if}
		<ul class="message-recovery__list">
			{#each messages as message (message.delivery_intent_id)}
				{@const open = openIntentId === message.delivery_intent_id}
				<li class="message-recovery__item">
					<div class="message-recovery__item-head">
						<div>
							<strong>{message.subject}</strong>
							<span>{message.recipient_email}</span>
							<a href={resolve(`/jafar/organizations/${message.organization_id}`)}>
								{message.organization_name}
							</a>
						</div>
						<Badge status={statusTone(message)} dot={false}>
							{message.outbox_status === 'failed' ? 'Held' : 'Waiting'}
						</Badge>
					</div>
					<dl class="message-recovery__detail">
						<div>
							<dt>What went wrong</dt>
							<dd>{message.last_error ?? message.failure_code ?? 'No detail recorded.'}</dd>
						</div>
						<div>
							<dt>Attempts</dt>
							<dd>{message.attempt_count} · last activity {formatDate(message.updated_at)}</dd>
						</div>
						<div>
							<dt>Kind</dt>
							<dd>{humanize(message.send_kind)} · {humanize(message.allowance_class)}</dd>
						</div>
					</dl>
					<div class="message-recovery__item-actions">
						<Button
							size="small"
							variant="secondary"
							variation="subtle"
							onhover={() => prefetchHistory(message.delivery_intent_id)}
							onclick={() => toggleTimeline(message.delivery_intent_id)}
						>
							{open ? 'Hide history' : 'View history'}
						</Button>
						<Button size="small" variation="work" onclick={() => openDialog(message, 'retry')}>
							Retry
						</Button>
						<Button
							size="small"
							variant="secondary"
							variation="destructive"
							onclick={() => openDialog(message, 'cancel')}
						>
							Cancel message
						</Button>
					</div>

					{#if open}
						<div class="message-recovery__timeline">
							{#if historyQuery.isPending}
								<LoadingSkeleton variant="table" rows={4} label="Loading message history" />
							{:else if historyQuery.isError}
								<ErrorState
									title="This history could not be loaded"
									description={historyQuery.error instanceof Error
										? historyQuery.error.message
										: 'Try again.'}
									retry={() => historyQuery.refetch()}
								/>
							{:else if historyQuery.data}
								<ol class="message-recovery__events">
									{#each historyQuery.data.events as event (event.id)}
										<li class="message-recovery__event">
											<Badge status={eventTone(event.event_kind)} dot={false}>
												{eventLabel(event.event_kind)}
											</Badge>
											<div class="message-recovery__event-body">
												<p class="message-recovery__event-when">
													{formatDate(event.occurred_at)} · {actorLine(event)}
													{#if event.repeat_count > 1}
														<span>
															— repeated {event.repeat_count} times, last
															{formatDate(event.last_occurred_at ?? event.occurred_at)}
														</span>
													{/if}
												</p>
												{#if event.reason_message || event.reason_code}
													<p class="message-recovery__event-reason">
														{event.reason_message ?? humanize(event.reason_code ?? '')}
													</p>
												{/if}
												{#if event.retry_at}
													<p class="message-recovery__event-when">
														Next try {formatDate(event.retry_at)}
													</p>
												{/if}
											</div>
										</li>
									{/each}
								</ol>
							{/if}
						</div>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</Card>

<ConfirmDialog
	open={dialog !== null}
	title={dialog?.action === 'retry' ? 'Send this message again' : 'Cancel this message'}
	tone={dialog?.action === 'retry' ? 'success' : 'critical'}
	confirmLabel={dialog?.action === 'retry' ? 'Put it back in the queue' : 'Cancel the message'}
	destructive={dialog?.action === 'cancel'}
	loading={actionMutation.isPending}
	confirmDisabled={!reasonValid || actionMutation.isPending}
	onConfirm={() => {
		if (reasonValid) actionMutation.mutate();
	}}
	onClose={() => {
		if (!actionMutation.isPending) dialog = null;
	}}
>
	{#if dialog}
		<p>
			{#if dialog.action === 'retry'}
				<strong>{dialog.message.subject}</strong> goes back in the queue for
				{dialog.message.organization_name}. The sender re-checks suppression, pauses, warm-up,
				capacity and allowance before it goes out — this does not force a send.
			{:else}
				<strong>{dialog.message.subject}</strong> will never be sent to
				{dialog.message.recipient_email}. Any allowance it was holding goes back to
				{dialog.message.organization_name}.
			{/if}
		</p>
		<Textarea
			id="message-recovery-reason"
			label="Reason (kept in the owner audit log)"
			bind:value={reason}
			rows={3}
			maxlength={1000}
			required
		/>
	{/if}
</ConfirmDialog>

<style lang="scss">
	:global(.message-recovery) {
		display: grid;
		gap: var(--space-base);
	}
	.message-recovery__head {
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
	.message-recovery__notice {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.message-recovery__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.message-recovery__item {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.message-recovery__item-head {
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
			display: block;
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
	.message-recovery__detail {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
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
	.message-recovery__item-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.message-recovery__timeline {
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.message-recovery__events {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.message-recovery__event {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
	}
	.message-recovery__event-body {
		display: grid;
		gap: var(--space-smallest);
		min-width: 0;
	}
	.message-recovery__event-when {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}
	.message-recovery__event-reason {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}
	@media (max-width: 900px) {
		.message-recovery__detail {
			grid-template-columns: 1fr;
		}
	}
	@media (max-width: 639px) {
		.message-recovery__head,
		.message-recovery__item-head {
			flex-direction: column;
		}
	}
</style>
