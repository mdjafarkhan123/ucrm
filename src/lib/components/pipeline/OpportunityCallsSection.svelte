<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { getLocalTimeZone, today } from '@internationalized/date';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		createTask,
		fetchOpportunityCalls,
		invalidatePipeline,
		logCall,
		opportunityCallsKey
	} from '$lib/pipeline/api';
	import {
		CALL_OUTCOMES,
		CALL_OUTCOME_LABELS,
		offersTryAgain,
		type CallLog,
		type CallOutcome
	} from '$lib/pipeline/calls';
	import type { BoardFormatting } from '$lib/pipeline/money';
	import { assignableTeamKey, fetchAssignableTeam } from '$lib/team/api';

	// The Brief's Calls block: what happened on the calls a person chose to log, newest first, and the bar that
	// logs one. The bar opens when Call is tapped or "Log call" is pressed and never blocks anything -- a person
	// may ignore it. Nothing is recorded until an outcome is chosen, and none is chosen for them.
	//
	// Only "Connected" and "Left voicemail" restart the card's inactivity clock (Jafar, 2026-10-02): those
	// reached the customer. The database decides that in the same write, and `onLogged` tells the Brief so its
	// own copy of the card stops warning at once.
	let {
		opportunityId,
		clientName,
		formatting,
		canEdit,
		logOpen = $bindable(false),
		currentUserId,
		onLogged
	}: {
		opportunityId: string;
		clientName: string;
		formatting: BoardFormatting | null;
		canEdit: boolean;
		logOpen?: boolean;
		currentUserId: string | undefined;
		onLogged: (restartedProgress: boolean) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const callsQuery = createQuery(() => ({
		queryKey: opportunityCallsKey(opportunityId),
		queryFn: () => fetchOpportunityCalls(opportunityId)
	}));
	const calls = $derived(callsQuery.data ?? []);

	// Names come from the team list the owner control already holds, so showing who logged a call almost
	// never costs its own request.
	const teamQuery = createQuery(() => ({
		queryKey: assignableTeamKey,
		queryFn: fetchAssignableTeam,
		staleTime: 300_000
	}));
	function loggedBy(call: CallLog) {
		if (!call.logged_by) return null;
		const member = teamQuery.data?.find((person) => person.id === call.logged_by);
		return member?.full_name ?? null;
	}

	function when(call: CallLog) {
		return new Date(call.created_at).toLocaleString(formatting?.locale, {
			timeZone: formatting?.timezone,
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}

	function badgeStatus(outcome: CallOutcome) {
		if (outcome === 'connected') return 'success' as const;
		if (outcome === 'left_voicemail') return 'informative' as const;
		if (outcome === 'wrong_number') return 'critical' as const;
		return 'inactive' as const;
	}

	let note = $state('');
	let noteOpen = $state(false);
	// After a call that did not get through: offer one tap to try again tomorrow.
	let tryAgainOffer = $state(false);

	function closeBar() {
		logOpen = false;
		noteOpen = false;
		note = '';
	}

	const logMutation = createMutation(() => ({
		mutationFn: (outcome: CallOutcome) =>
			logCall(opportunityId, { outcome, note: note.trim() || null }),
		onSuccess: (result, outcome) => {
			queryClient.invalidateQueries({ queryKey: opportunityCallsKey(opportunityId) });
			// A restarted clock changes the card's warning on the board behind the Brief.
			if (result.restarted_progress) invalidatePipeline(queryClient);
			onLogged(result.restarted_progress);
			toast.success('Call logged');
			closeBar();
			tryAgainOffer = canEdit && offersTryAgain(outcome);
		},
		onError: (error: Error) => toast.error('Could not log the call', error.message)
	}));

	// Tomorrow, on the organization's own calendar. The Task goes to the person who called, so it shows on
	// their own Schedule; assigning it to themselves sends no alert.
	const tryAgainMutation = createMutation(() => ({
		mutationFn: () =>
			createTask(opportunityId, {
				title: `Call ${clientName} again`,
				instructions: null,
				assignee_user_id: currentUserId ?? null,
				due_on: today(formatting?.timezone ?? getLocalTimeZone())
					.add({ days: 1 })
					.toString()
			}),
		onSuccess: () => {
			invalidatePipeline(queryClient);
			tryAgainOffer = false;
			toast.success('Task added for tomorrow');
		},
		// The call is already saved. The usual reason to land here is the five-open-Tasks limit, and its message
		// says so in words a person can act on.
		onError: (error: Error) => {
			tryAgainOffer = false;
			toast.error('The call is saved, but the Task was not added', error.message);
		}
	}));
</script>

<section class="calls" aria-labelledby="brief-calls-heading">
	<div class="calls__header">
		<h3 id="brief-calls-heading" class="calls__heading">Calls</h3>
		{#if canEdit && !logOpen}
			<Button
				size="small"
				variant="tertiary"
				onclick={() => {
					tryAgainOffer = false;
					logOpen = true;
				}}
			>
				+ Log call
			</Button>
		{/if}
	</div>

	{#if logOpen && canEdit}
		<div class="calls__bar" role="group" aria-labelledby="brief-calls-question">
			<p id="brief-calls-question" class="calls__question">How did the call go?</p>
			<div class="calls__outcomes">
				{#each CALL_OUTCOMES as outcome (outcome)}
					<Button
						size="small"
						variant="secondary"
						disabled={logMutation.isPending}
						onclick={() => logMutation.mutate(outcome)}
					>
						{CALL_OUTCOME_LABELS[outcome]}
					</Button>
				{/each}
			</div>
			{#if noteOpen}
				<Textarea
					id="brief-call-note"
					label="Note (optional)"
					rows={2}
					maxlength={2000}
					bind:value={note}
				/>
			{/if}
			<div class="calls__bar-footer">
				{#if !noteOpen}
					<Button size="small" variant="tertiary" onclick={() => (noteOpen = true)}>
						+ Add a note
					</Button>
				{/if}
				<Button size="small" variant="tertiary" onclick={closeBar}>Not now</Button>
			</div>
		</div>
	{/if}

	{#if tryAgainOffer}
		<div class="calls__offer" role="status">
			<span>Try again tomorrow?</span>
			<span class="calls__offer-actions">
				<Button
					size="small"
					variant="secondary"
					loading={tryAgainMutation.isPending}
					onclick={() => tryAgainMutation.mutate()}
				>
					Add a task
				</Button>
				<Button size="small" variant="tertiary" onclick={() => (tryAgainOffer = false)}>
					No thanks
				</Button>
			</span>
		</div>
	{/if}

	{#if callsQuery.isPending}
		<p class="calls__state">Loading calls…</p>
	{:else if callsQuery.isError}
		<p class="calls__state calls__state--error">The calls could not be loaded.</p>
	{:else if calls.length === 0}
		<p class="calls__state">No calls logged yet</p>
	{:else}
		<ul class="calls__list">
			{#each calls as call (call.id)}
				{@const who = loggedBy(call)}
				<li class="calls__row">
					<div class="calls__row-top">
						<Badge status={badgeStatus(call.outcome)} size="small">
							{CALL_OUTCOME_LABELS[call.outcome]}
						</Badge>
						<span class="calls__meta">{who ? `${who} · ` : ''}{when(call)}</span>
					</div>
					{#if call.note}<p class="calls__note">{call.note}</p>{/if}
				</li>
			{/each}
		</ul>
	{/if}
</section>

<style lang="scss">
	.calls {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}
	.calls__header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.calls__heading {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.calls__bar,
	.calls__offer {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--active);
	}
	.calls__offer {
		flex-direction: row;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}
	.calls__offer-actions {
		display: inline-flex;
		gap: var(--space-smaller);
	}
	.calls__question {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}
	.calls__outcomes {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-smaller);
	}
	.calls__bar-footer {
		display: flex;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.calls__state {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		&--error {
			color: var(--color-critical);
		}
	}
	.calls__list {
		display: flex;
		flex-direction: column;
	}
	.calls__row {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: var(--space-small) 0;
		border-bottom: var(--border-base) solid var(--color-border);

		&:last-child {
			border-bottom: 0;
		}
	}
	.calls__row-top {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.calls__meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.calls__note {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
		white-space: pre-wrap;
		overflow-wrap: anywhere;
	}
</style>
