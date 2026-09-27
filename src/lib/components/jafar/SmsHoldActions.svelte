<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';
	import { jafarOrganizationSmsHoldsKey } from '$lib/jafar/query-keys';

	type HoldScope = 'organization' | 'provider';
	type Hold = {
		id: string;
		scope: HoldScope;
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
	type PlaceInput = { kind: 'place'; scope: HoldScope; reason: string };
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

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const listKey = $derived(jafarOrganizationSmsHoldsKey(organizationId));

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/holds`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'SMS holds could not be loaded.');
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

	const scopeOptions = [
		{ value: 'organization', label: 'Organization (ordinary business pause)' },
		{ value: 'provider', label: 'Provider (emergency subaccount suspension)' }
	];

	function formatTime(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
					new Date(value)
				)
			: 'Not yet';
	}

	let placeOpen = $state(false);
	let placeScope = $state<HoldScope>('organization');
	let placeReason = $state('');
	let releaseOpen = $state<string | null>(null);
	let releaseReason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<HoldInput | null>(null);

	function openPlace() {
		placeScope = 'organization';
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
					? `/api/jafar/organizations/${organizationId}/communications/sms/holds`
					: `/api/jafar/organizations/${organizationId}/communications/sms/holds/${input.holdId}/release`;
			const body =
				input.kind === 'place'
					? { scope: input.scope, reason: input.reason }
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
			feedbackMessage = input.kind === 'place' ? 'Hold placed.' : 'Hold released.';
			await queryClient.invalidateQueries({ queryKey: listKey });
		}
	}));

	function submitPlace(event: SubmitEvent) {
		event.preventDefault();
		if (!placeReason.trim() || placeReason.trim().length < 3) {
			fieldErrors = { reason: 'Enter a reason of at least 3 characters.' };
			return;
		}
		holdMutation.mutate({ kind: 'place', scope: placeScope, reason: placeReason.trim() });
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

<div class="sms-hold-actions">
	<div class="sms-hold-actions__heading">
		<div>
			<h3>Outbound SMS holds</h3>
			<p>A hold pauses outbound texting for this organization only. Inbound stays available.</p>
		</div>
		{#if !activeHold}
			<Button size="small" variant="secondary" onclick={openPlace}>Place a hold</Button>
		{/if}
	</div>

	{#if feedbackMessage}<p class="sms-hold-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="sms-hold-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading SMS holds" />
	{:else if listQuery.isError}
		<ErrorState
			title="SMS holds could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else}
		{#if activeHold}
			<div class="sms-hold-actions__active">
				<div>
					<Badge status="critical">
						{activeHold.scope === 'provider' ? 'Provider suspension' : 'Organization hold'}
					</Badge>
					<p>{activeHold.reason}</p>
					<p class="sms-hold-actions__meta">Placed {formatTime(activeHold.placed_at)}</p>
				</div>
				<Button size="small" variation="destructive" onclick={() => openRelease(activeHold.id)}>
					Release hold
				</Button>
			</div>
		{:else if releasedHolds.length === 0}
			<EmptyState
				title="No holds on this organization"
				description="Outbound texting is not paused by a hold."
			/>
		{/if}

		{#if releasedHolds.length > 0}
			<ul class="sms-hold-actions__list">
				{#each releasedHolds as hold (hold.id)}
					<li class="sms-hold-actions__row">
						<div class="sms-hold-actions__row-heading">
							<div>
								<h4>{hold.scope === 'provider' ? 'Provider suspension' : 'Organization hold'}</h4>
								<p>{hold.reason}</p>
							</div>
							<Badge status="inactive">Released</Badge>
						</div>
						<p class="sms-hold-actions__meta">
							Placed {formatTime(hold.placed_at)} &middot; released {formatTime(hold.released_at)}
						</p>
						{#if hold.release_reason}<p class="sms-hold-actions__meta">
								{hold.release_reason}
							</p>{/if}
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

<Dialog open={placeOpen} title="Place an outbound hold" onClose={() => (placeOpen = false)}>
	<form class="sms-hold-actions__form" onsubmit={submitPlace}>
		<Select id="sms-hold-scope" label="Scope" options={scopeOptions} bind:value={placeScope} />
		<Textarea
			id="sms-hold-reason"
			label="Reason"
			bind:value={placeReason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
			required
		/>
		<div class="sms-hold-actions__dialog-actions">
			<Button type="submit" loading={holdMutation.isPending}>Place hold</Button>
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
	title="Release the outbound hold"
	onClose={() => (releaseOpen = null)}
>
	<form class="sms-hold-actions__form" onsubmit={submitRelease}>
		<Textarea
			id="sms-hold-release-reason"
			label="Reason"
			bind:value={releaseReason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.release_reason)}
			errorMessage={fieldErrors.release_reason}
			required
		/>
		<div class="sms-hold-actions__dialog-actions">
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
	title="Confirm this hold change"
	description="Pausing or resuming outbound texting requires a fresh password reconfirmation."
	confirmLabel="Confirm"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.sms-hold-actions {
		display: grid;
		gap: var(--space-base);
	}
	.sms-hold-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-hold-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-hold-actions__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.sms-hold-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-hold-actions__success {
		color: var(--color-success--onSurface);
	}
	.sms-hold-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-hold-actions__active {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-critical--surface);
		border-radius: var(--radius-base);
		background: var(--color-critical--surface);
	}
	.sms-hold-actions__active p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-critical--onSurface);
	}
	.sms-hold-actions__meta {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-hold-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-hold-actions__row {
		display: grid;
		gap: var(--space-smallest);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-hold-actions__row-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-hold-actions__row-heading h4 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.sms-hold-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-hold-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-hold-actions__heading,
		.sms-hold-actions__active,
		.sms-hold-actions__row-heading {
			flex-direction: column;
		}
	}
</style>
