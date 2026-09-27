<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';
	import { jafarOrganizationSmsCreditTopupsKey } from '$lib/jafar/query-keys';

	type TopupStatus = 'awaiting_confirmation' | 'confirmed' | 'rejected' | 'cancelled';
	type TopupRequest = {
		id: string;
		requested_amount_minor: number;
		currency_code: string;
		offsite_reference: string | null;
		note: string | null;
		status: TopupStatus;
		requested_at: string;
		decided_at: string | null;
		decision_reason: string | null;
		settled_amount_minor: number | null;
	};
	type Balance = {
		currency_code: string;
		settled_balance_minor: number;
		reserved_balance_minor: number;
		promotional_balance_minor: number;
		spendable_balance_minor: number;
	};
	type ListResponse = { requests?: TopupRequest[]; balance?: Balance; error?: string };
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};
	type DecisionInput =
		| {
				requestId: string;
				action: 'confirm';
				settled_amount_minor: number;
				decision_reason?: string;
		  }
		| { requestId: string; action: 'reject'; decision_reason: string };

	class DecisionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'The top-up decision could not be recorded.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const listKey = $derived(jafarOrganizationSmsCreditTopupsKey(organizationId));

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/credit-topups`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'SMS credit top-ups could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	function formatMoney(minor: number, currency: string) {
		return `$${(minor / 100).toFixed(2)} ${currency}`;
	}
	function formatTime(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
					new Date(value)
				)
			: 'Not yet';
	}
	const statusTone: Record<TopupStatus, 'success' | 'warning' | 'critical' | 'inactive'> = {
		awaiting_confirmation: 'warning',
		confirmed: 'success',
		rejected: 'critical',
		cancelled: 'inactive'
	};
	const statusLabel: Record<TopupStatus, string> = {
		awaiting_confirmation: 'Awaiting confirmation',
		confirmed: 'Confirmed',
		rejected: 'Rejected',
		cancelled: 'Cancelled'
	};

	// Confirm / reject ---------------------------------------------------------------------------
	let decisionOpen = $state<{ requestId: string; action: 'confirm' | 'reject' } | null>(null);
	let settledAmountUsd = $state('');
	let decisionReason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<DecisionInput | null>(null);

	function openDecision(request: TopupRequest, action: 'confirm' | 'reject') {
		decisionOpen = { requestId: request.id, action };
		settledAmountUsd = (request.requested_amount_minor / 100).toFixed(2);
		decisionReason = '';
		fieldErrors = {};
		feedbackError = '';
	}

	function buildInput(): DecisionInput | null {
		if (!decisionOpen) return null;
		const errors: Record<string, string> = {};
		if (decisionOpen.action === 'confirm') {
			const dollars = Number(settledAmountUsd);
			const settledAmountMinor = Number.isFinite(dollars) ? Math.round(dollars * 100) : 0;
			if (settledAmountMinor <= 0)
				errors.settled_amount_minor = 'Enter an amount greater than zero.';
			fieldErrors = errors;
			if (Object.keys(errors).length > 0) return null;
			return {
				requestId: decisionOpen.requestId,
				action: 'confirm',
				settled_amount_minor: settledAmountMinor,
				...(decisionReason.trim() ? { decision_reason: decisionReason.trim() } : {})
			};
		}
		if (!decisionReason.trim() || decisionReason.trim().length < 3)
			errors.decision_reason = 'Enter a reason of at least 3 characters.';
		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return null;
		return {
			requestId: decisionOpen.requestId,
			action: 'reject',
			decision_reason: decisionReason.trim()
		};
	}

	const decisionMutation = createMutation<MutationResponse, DecisionError, DecisionInput>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/credit-topups/${input.requestId}`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(
						input.action === 'confirm'
							? {
									action: 'confirm',
									settled_amount_minor: input.settled_amount_minor,
									...(input.decision_reason ? { decision_reason: input.decision_reason } : {})
								}
							: { action: 'reject', decision_reason: input.decision_reason }
					)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new DecisionError(result);
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
			decisionOpen = null;
			pendingStepUpInput = null;
			feedbackMessage =
				input.action === 'confirm' ? 'Top-up confirmed and credited.' : 'Top-up rejected.';
			await queryClient.invalidateQueries({ queryKey: listKey });
		}
	}));

	function submitDecision(event: SubmitEvent) {
		event.preventDefault();
		const input = buildInput();
		if (input) decisionMutation.mutate(input);
	}

	function confirmStepUp() {
		if (pendingStepUpInput) decisionMutation.mutate(pendingStepUpInput);
	}
</script>

<div class="sms-topup-actions">
	<div class="sms-topup-actions__heading">
		<h3>SMS credit top-ups</h3>
		<p>
			A top-up creates no spendable credit until you verify the offsite payment and confirm the
			amount actually received.
		</p>
	</div>

	{#if feedbackMessage}<p class="sms-topup-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="sms-topup-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading SMS credit top-ups" />
	{:else if listQuery.isError}
		<ErrorState
			title="SMS credit top-ups could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else}
		{@const balance = listQuery.data?.balance}
		{#if balance}
			<dl class="sms-topup-actions__balance">
				<div>
					<dt>Spendable</dt>
					<dd>{formatMoney(balance.spendable_balance_minor, balance.currency_code)}</dd>
				</div>
				<div>
					<dt>Purchased</dt>
					<dd>{formatMoney(balance.settled_balance_minor, balance.currency_code)}</dd>
				</div>
				<div>
					<dt>Promotional</dt>
					<dd>{formatMoney(balance.promotional_balance_minor, balance.currency_code)}</dd>
				</div>
				<div>
					<dt>Reserved</dt>
					<dd>{formatMoney(balance.reserved_balance_minor, balance.currency_code)}</dd>
				</div>
			</dl>
		{/if}

		{#if (listQuery.data?.requests ?? []).length === 0}
			<EmptyState
				title="No top-up requests yet"
				description="Requests the contractor submits will appear here for confirmation."
			/>
		{:else}
			<ul class="sms-topup-actions__list">
				{#each listQuery.data?.requests ?? [] as request (request.id)}
					<li class="sms-topup-actions__row">
						<div class="sms-topup-actions__row-heading">
							<div>
								<h4>
									{formatMoney(request.requested_amount_minor, request.currency_code)} requested
								</h4>
								<p>
									{formatTime(request.requested_at)}
									{#if request.offsite_reference}
										&middot; Reference: {request.offsite_reference}
									{/if}
								</p>
							</div>
							<Badge status={statusTone[request.status]}>{statusLabel[request.status]}</Badge>
						</div>
						{#if request.note}<p class="sms-topup-actions__note">{request.note}</p>{/if}
						{#if request.status === 'confirmed' && request.settled_amount_minor !== null}
							<p class="sms-topup-actions__note">
								Settled {formatMoney(request.settled_amount_minor, request.currency_code)}
								{#if request.decision_reason}&middot; {request.decision_reason}{/if}
							</p>
						{:else if request.status === 'rejected' && request.decision_reason}
							<p class="sms-topup-actions__note sms-topup-actions__note--critical">
								{request.decision_reason}
							</p>
						{/if}
						{#if request.status === 'awaiting_confirmation'}
							<div class="sms-topup-actions__row-actions">
								<Button size="small" onclick={() => openDecision(request, 'confirm')}>
									Confirm
								</Button>
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									onclick={() => openDecision(request, 'reject')}
								>
									Reject
								</Button>
							</div>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>

<Dialog
	open={decisionOpen?.action === 'confirm'}
	title="Confirm top-up"
	onClose={() => (decisionOpen = null)}
>
	<form class="sms-topup-actions__form" onsubmit={submitDecision}>
		<p>Record the amount actually received. It may differ from the requested amount.</p>
		<Input
			id="sms-topup-settled-amount"
			label="Settled amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={settledAmountUsd}
			invalid={Boolean(fieldErrors.settled_amount_minor)}
			errorMessage={fieldErrors.settled_amount_minor}
		/>
		<Textarea
			id="sms-topup-decision-note"
			label="Note (optional)"
			bind:value={decisionReason}
			rows={3}
			maxlength={1000}
		/>
		<div class="sms-topup-actions__dialog-actions">
			<Button type="submit" loading={decisionMutation.isPending}>Confirm and credit</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (decisionOpen = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<Dialog
	open={decisionOpen?.action === 'reject'}
	title="Reject top-up"
	onClose={() => (decisionOpen = null)}
>
	<form class="sms-topup-actions__form" onsubmit={submitDecision}>
		<Textarea
			id="sms-topup-reject-reason"
			label="Reason"
			bind:value={decisionReason}
			rows={3}
			maxlength={1000}
			invalid={Boolean(fieldErrors.decision_reason)}
			errorMessage={fieldErrors.decision_reason}
			required
		/>
		<div class="sms-topup-actions__dialog-actions">
			<Button type="submit" variation="destructive" loading={decisionMutation.isPending}>
				Reject top-up
			</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (decisionOpen = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm this top-up decision"
	description="Money decisions require a fresh password reconfirmation."
	confirmLabel="Confirm decision"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.sms-topup-actions,
	.sms-topup-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-topup-actions__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.sms-topup-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-topup-actions__success {
		color: var(--color-success--onSurface);
	}
	.sms-topup-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-topup-actions__balance {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: var(--space-base);
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-topup-actions__balance dt {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-topup-actions__balance dd {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text);
		font-weight: 700;
	}
	.sms-topup-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-topup-actions__row {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-topup-actions__row-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-topup-actions__row-heading h4 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.sms-topup-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-topup-actions__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-topup-actions__note--critical {
		color: var(--color-critical--onSurface);
	}
	.sms-topup-actions__row-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.sms-topup-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-topup-actions__balance {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.sms-topup-actions__row-heading {
			flex-direction: column;
		}
	}
</style>
