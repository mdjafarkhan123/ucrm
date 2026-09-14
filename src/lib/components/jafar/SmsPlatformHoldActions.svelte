<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';

	type Hold = {
		id: string;
		reason: string;
		placed_at: string;
		status: 'active' | 'released';
		released_at: string | null;
		release_reason: string | null;
	};
	type ListResponse = { holds?: Hold[]; error?: string };
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};
	type PlaceInput = { kind: 'place'; reason: string };
	type ReleaseInput = { kind: 'release'; holdId: string; release_reason: string };
	type HoldInput = PlaceInput | ReleaseInput;

	class HoldError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'The hold could not be changed.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	const queryClient = useQueryClient();
	const listKey = ['jafar', 'communications', 'sms', 'platform-holds'] as const;

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch('/api/jafar/communications/sms/platform-holds');
			const result = (await response.json()) as ListResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'Platform-wide SMS holds could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const activeHold = $derived(
		(listQuery.data?.holds ?? []).find((hold) => hold.status === 'active') ?? null
	);
	const releasedHolds = $derived(
		(listQuery.data?.holds ?? []).filter((hold) => hold.status === 'released')
	);

	function formatTime(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
					new Date(value)
				)
			: 'Not yet';
	}

	let placeOpen = $state(false);
	let placeReason = $state('');
	let releaseOpen = $state<string | null>(null);
	let releaseReason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<HoldInput | null>(null);

	function openPlace() {
		placeReason = '';
		fieldErrors = {};
		feedbackError = '';
		placeOpen = true;
	}
	function openRelease(holdId: string) {
		releaseOpen = holdId;
		releaseReason = '';
		fieldErrors = {};
		feedbackError = '';
	}

	const holdMutation = createMutation<MutationResponse, HoldError, HoldInput>(() => ({
		mutationFn: async (input) => {
			const url =
				input.kind === 'place'
					? '/api/jafar/communications/sms/platform-holds'
					: `/api/jafar/communications/sms/platform-holds/${input.holdId}/release`;
			const body =
				input.kind === 'place'
					? { reason: input.reason }
					: { release_reason: input.release_reason };
			const response = await fetch(url, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new HoldError(result);
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
		onSuccess: async (_result, input) => {
			placeOpen = false;
			releaseOpen = null;
			pendingStepUpInput = null;
			feedbackMessage = input.kind === 'place' ? 'Platform-wide hold placed.' : 'Hold released.';
			await queryClient.invalidateQueries({ queryKey: listKey });
		}
	}));

	function submitPlace(event: SubmitEvent) {
		event.preventDefault();
		if (!placeReason.trim() || placeReason.trim().length < 3) {
			fieldErrors = { reason: 'Enter a reason of at least 3 characters.' };
			return;
		}
		holdMutation.mutate({ kind: 'place', reason: placeReason.trim() });
	}
	function submitRelease(event: SubmitEvent) {
		event.preventDefault();
		if (!releaseOpen) return;
		if (!releaseReason.trim() || releaseReason.trim().length < 3) {
			fieldErrors = { release_reason: 'Enter a reason of at least 3 characters.' };
			return;
		}
		holdMutation.mutate({
			kind: 'release',
			holdId: releaseOpen,
			release_reason: releaseReason.trim()
		});
	}
	function confirmStepUp() {
		if (pendingStepUpInput) holdMutation.mutate(pendingStepUpInput);
	}
</script>

<Card class="sms-platform-hold-actions__card">
	<div class="sms-platform-hold-actions__heading">
		<div>
			<h2>Platform-wide SMS hold</h2>
			<p>
				An emergency control that pauses outbound texting for every organization at once. Inbound
				stays available. Use an organization-scoped hold from that organization's detail page for an
				ordinary single-account pause.
			</p>
		</div>
		{#if !activeHold}
			<Button size="small" variant="secondary" onclick={openPlace}>Place platform-wide hold</Button>
		{/if}
	</div>

	{#if feedbackMessage}<p class="sms-platform-hold-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="sms-platform-hold-actions__error" role="alert">
			{feedbackError}
		</p>{/if}

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading platform-wide SMS holds" />
	{:else if listQuery.isError}
		<ErrorState
			title="Platform-wide SMS holds could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else}
		{#if activeHold}
			<div class="sms-platform-hold-actions__active">
				<div>
					<Badge status="critical">Platform-wide hold active</Badge>
					<p>{activeHold.reason}</p>
					<p class="sms-platform-hold-actions__meta">Placed {formatTime(activeHold.placed_at)}</p>
				</div>
				<Button size="small" variation="destructive" onclick={() => openRelease(activeHold.id)}>
					Release hold
				</Button>
			</div>
		{:else if releasedHolds.length === 0}
			<EmptyState
				title="No platform-wide hold"
				description="Outbound texting is not paused platform-wide."
			/>
		{/if}

		{#if releasedHolds.length > 0}
			<ul class="sms-platform-hold-actions__list">
				{#each releasedHolds as hold (hold.id)}
					<li class="sms-platform-hold-actions__row">
						<div class="sms-platform-hold-actions__row-heading">
							<div>
								<h3>Platform-wide hold</h3>
								<p>{hold.reason}</p>
							</div>
							<Badge status="inactive">Released</Badge>
						</div>
						<p class="sms-platform-hold-actions__meta">
							Placed {formatTime(hold.placed_at)} &middot; released {formatTime(hold.released_at)}
						</p>
						{#if hold.release_reason}<p class="sms-platform-hold-actions__meta">
								{hold.release_reason}
							</p>{/if}
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</Card>

<Dialog open={placeOpen} title="Place a platform-wide hold" onClose={() => (placeOpen = false)}>
	<form class="sms-platform-hold-actions__form" onsubmit={submitPlace}>
		<Textarea
			id="sms-platform-hold-reason"
			label="Reason"
			bind:value={placeReason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
			required
		/>
		<div class="sms-platform-hold-actions__dialog-actions">
			<Button type="submit" variation="destructive" loading={holdMutation.isPending}>
				Place hold
			</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (placeOpen = false)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<Dialog
	open={releaseOpen !== null}
	title="Release the platform-wide hold"
	onClose={() => (releaseOpen = null)}
>
	<form class="sms-platform-hold-actions__form" onsubmit={submitRelease}>
		<Textarea
			id="sms-platform-hold-release-reason"
			label="Reason"
			bind:value={releaseReason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.release_reason)}
			errorMessage={fieldErrors.release_reason}
			required
		/>
		<div class="sms-platform-hold-actions__dialog-actions">
			<Button type="submit" loading={holdMutation.isPending}>Release hold</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (releaseOpen = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm this platform-wide hold change"
	description="Pausing or resuming outbound texting for every organization requires a fresh password reconfirmation."
	confirmLabel="Confirm"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	:global(.sms-platform-hold-actions__card) {
		display: grid;
		gap: var(--space-base);
	}
	.sms-platform-hold-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-platform-hold-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-platform-hold-actions__heading h2 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tightest);
	}
	.sms-platform-hold-actions__heading p {
		margin: var(--space-small) 0 0;
		max-width: 70ch;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-platform-hold-actions__success {
		color: var(--color-success--onSurface);
	}
	.sms-platform-hold-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-platform-hold-actions__active {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-critical--surface);
		border-radius: var(--radius-base);
		background: var(--color-critical--surface);
	}
	.sms-platform-hold-actions__active p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-critical--onSurface);
	}
	.sms-platform-hold-actions__meta {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-platform-hold-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-platform-hold-actions__row {
		display: grid;
		gap: var(--space-smallest);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-platform-hold-actions__row-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-platform-hold-actions__row-heading h3 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.sms-platform-hold-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-platform-hold-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-platform-hold-actions__heading,
		.sms-platform-hold-actions__active,
		.sms-platform-hold-actions__row-heading {
			flex-direction: column;
		}
	}
</style>
