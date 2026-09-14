<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';

	type LedgerEntry = {
		id: string;
		amount_minor: number;
		balance_after_minor: number;
		reason: string | null;
		occurred_at: string;
	};
	type ListResponse = { entries?: LedgerEntry[]; error?: string };
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};
	type AdjustmentInput = {
		kind: 'adjustment';
		amount_minor: number;
		reason: string;
		idempotency_key: string;
	};
	type RefundInput = {
		kind: 'refund';
		amount_minor: number;
		reason: string;
		idempotency_key: string;
	};
	type LedgerInput = AdjustmentInput | RefundInput;

	class LedgerError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'The ledger entry could not be recorded.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const adjustmentsKey = $derived(['jafar', 'organizations', organizationId, 'sms', 'adjustments']);
	const refundsKey = $derived(['jafar', 'organizations', organizationId, 'sms', 'refunds']);

	const adjustmentsQuery = createQuery<ListResponse>(() => ({
		queryKey: adjustmentsKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/adjustments`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'SMS adjustments could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));
	const refundsQuery = createQuery<ListResponse>(() => ({
		queryKey: refundsKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/refunds`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'SMS refunds could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	type HistoryRow = LedgerEntry & { kind: 'adjustment' | 'refund' };
	const history = $derived(
		[
			...(adjustmentsQuery.data?.entries ?? []).map((entry): HistoryRow => ({
				...entry,
				kind: 'adjustment'
			})),
			...(refundsQuery.data?.entries ?? []).map((entry): HistoryRow => ({
				...entry,
				kind: 'refund'
			}))
		].sort((a, b) => b.occurred_at.localeCompare(a.occurred_at))
	);

	function formatMoney(minor: number) {
		const sign = minor < 0 ? '-' : '';
		return `${sign}$${(Math.abs(minor) / 100).toFixed(2)}`;
	}
	function formatTime(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
			new Date(value)
		);
	}

	const directionOptions = [
		{ value: 'increase', label: 'Increase the balance' },
		{ value: 'decrease', label: 'Decrease the balance' }
	];

	let activeDialog = $state<'adjustment' | 'refund' | null>(null);
	let amountUsd = $state('');
	let direction = $state<'increase' | 'decrease'>('increase');
	let reason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<LedgerInput | null>(null);

	function openDialog(kind: 'adjustment' | 'refund') {
		activeDialog = kind;
		amountUsd = '';
		direction = 'increase';
		reason = '';
		fieldErrors = {};
		feedbackError = '';
	}

	const ledgerMutation = createMutation<MutationResponse, LedgerError, LedgerInput>(() => ({
		mutationFn: async (input) => {
			const url = `/api/jafar/organizations/${organizationId}/communications/sms/${input.kind === 'adjustment' ? 'adjustments' : 'refunds'}`;
			const response = await fetch(url, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					amount_minor: input.amount_minor,
					reason: input.reason,
					idempotency_key: input.idempotency_key
				})
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new LedgerError(result);
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
			activeDialog = null;
			pendingStepUpInput = null;
			feedbackMessage = input.kind === 'adjustment' ? 'Adjustment recorded.' : 'Refund recorded.';
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: adjustmentsKey }),
				queryClient.invalidateQueries({ queryKey: refundsKey })
			]);
		}
	}));

	function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!activeDialog) return;
		const errors: Record<string, string> = {};
		const dollars = Number(amountUsd);
		const magnitude = Number.isFinite(dollars) ? Math.round(dollars * 100) : 0;
		if (magnitude <= 0) errors.amount_minor = 'Enter an amount greater than zero.';
		if (!reason.trim() || reason.trim().length < 3)
			errors.reason = 'Enter a reason of at least 3 characters.';
		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return;

		const amountMinor =
			activeDialog === 'adjustment' && direction === 'decrease' ? -magnitude : magnitude;
		ledgerMutation.mutate({
			kind: activeDialog,
			amount_minor: amountMinor,
			reason: reason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
	function confirmStepUp() {
		if (pendingStepUpInput) ledgerMutation.mutate(pendingStepUpInput);
	}
</script>

<div class="sms-ledger-actions">
	<div class="sms-ledger-actions__heading">
		<div>
			<h3>Adjustments and refunds</h3>
			<p>
				Standalone reasoned corrections to settled SMS credit. Every entry is immutable; a mistake
				is fixed with a new, reasoned entry, never by editing history.
			</p>
		</div>
		<div class="sms-ledger-actions__buttons">
			<Button size="small" variant="secondary" onclick={() => openDialog('adjustment')}>
				Record adjustment
			</Button>
			<Button size="small" variant="secondary" onclick={() => openDialog('refund')}>
				Record refund
			</Button>
		</div>
	</div>

	{#if feedbackMessage}<p class="sms-ledger-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="sms-ledger-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if adjustmentsQuery.isPending || refundsQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading adjustments and refunds" />
	{:else if adjustmentsQuery.isError || refundsQuery.isError}
		<ErrorState
			title="Adjustments and refunds could not be loaded"
			description={adjustmentsQuery.error instanceof Error
				? adjustmentsQuery.error.message
				: refundsQuery.error instanceof Error
					? refundsQuery.error.message
					: 'Try again.'}
			retry={() => {
				adjustmentsQuery.refetch();
				refundsQuery.refetch();
			}}
		/>
	{:else if history.length === 0}
		<EmptyState
			title="No adjustments or refunds yet"
			description="Standalone corrections and offsite refunds will appear here."
		/>
	{:else}
		<ul class="sms-ledger-actions__list">
			{#each history as entry (entry.kind + ':' + entry.id)}
				<li class="sms-ledger-actions__row">
					<div class="sms-ledger-actions__row-heading">
						<div>
							<h4>{formatMoney(entry.amount_minor)}</h4>
							<p>{entry.reason ?? 'No reason recorded'}</p>
						</div>
						<Badge status={entry.kind === 'refund' ? 'warning' : 'informative'}>
							{entry.kind === 'refund' ? 'Refund' : 'Adjustment'}
						</Badge>
					</div>
					<p class="sms-ledger-actions__meta">
						{formatTime(entry.occurred_at)} &middot; balance after {formatMoney(
							entry.balance_after_minor
						)}
					</p>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<Dialog
	open={activeDialog === 'adjustment'}
	title="Record an adjustment"
	onClose={() => (activeDialog = null)}
>
	<form class="sms-ledger-actions__form" onsubmit={submit}>
		<Select
			id="sms-ledger-direction"
			label="Direction"
			options={directionOptions}
			bind:value={direction}
		/>
		<Input
			id="sms-ledger-adjustment-amount"
			label="Amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={amountUsd}
			invalid={Boolean(fieldErrors.amount_minor)}
			errorMessage={fieldErrors.amount_minor}
		/>
		<Textarea
			id="sms-ledger-adjustment-reason"
			label="Reason"
			bind:value={reason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
			required
		/>
		<div class="sms-ledger-actions__dialog-actions">
			<Button type="submit" loading={ledgerMutation.isPending}>Record adjustment</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (activeDialog = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<Dialog
	open={activeDialog === 'refund'}
	title="Record a refund"
	onClose={() => (activeDialog = null)}
>
	<form class="sms-ledger-actions__form" onsubmit={submit}>
		<p>Enter the refund as a positive amount. It always lowers the settled balance.</p>
		<Input
			id="sms-ledger-refund-amount"
			label="Amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={amountUsd}
			invalid={Boolean(fieldErrors.amount_minor)}
			errorMessage={fieldErrors.amount_minor}
		/>
		<Textarea
			id="sms-ledger-refund-reason"
			label="Reason"
			bind:value={reason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
			required
		/>
		<div class="sms-ledger-actions__dialog-actions">
			<Button type="submit" loading={ledgerMutation.isPending}>Record refund</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (activeDialog = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm this ledger entry"
	description="Money decisions require a fresh password reconfirmation."
	confirmLabel="Confirm"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.sms-ledger-actions,
	.sms-ledger-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-ledger-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-ledger-actions__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.sms-ledger-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-ledger-actions__buttons {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.sms-ledger-actions__success {
		color: var(--color-success--onSurface);
	}
	.sms-ledger-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-ledger-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-ledger-actions__row {
		display: grid;
		gap: var(--space-smallest);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-ledger-actions__row-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-ledger-actions__row-heading h4 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.sms-ledger-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-ledger-actions__meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-ledger-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-ledger-actions__heading,
		.sms-ledger-actions__row-heading {
			flex-direction: column;
		}
	}
</style>
