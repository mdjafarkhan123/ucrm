<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';

	type CommercialAction = 'renewal' | 'correction' | 'refund' | 'reversal';
	type OriginalEvent = {
		id: string;
		event_kind: string;
		occurred_at: string;
		summary: string;
		amount_usd_cents: number | null;
		paid_through_after: string | null;
		private_reference: string | null;
	};
	type CommercialInput = {
		action: CommercialAction;
		idempotency_key: string;
		paid_through_effect: 'set' | 'unchanged';
		paid_through_date?: string;
		amount_usd_cents: number;
		private_reference: string;
		private_reason?: string;
		original_event_id?: string;
		reactivate?: boolean;
	};
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};

	class CommercialActionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'The commercial action could not be recorded.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let {
		organizationId,
		lifecycleStatus,
		currentPaidThroughDate,
		originalEvents
	}: {
		organizationId: string;
		lifecycleStatus: string;
		currentPaidThroughDate: string | null;
		originalEvents: OriginalEvent[];
	} = $props();

	const queryClient = useQueryClient();
	const paidThroughOptions = [
		{ value: 'set', label: 'Set the resulting paid-through date' },
		{ value: 'unchanged', label: 'Confirm no paid-through change' }
	];
	const originalEventOptions = $derived(
		originalEvents.map((event) => ({
			value: event.id,
			label: `${event.event_kind === 'initial_payment_confirmed' ? 'Initial payment' : 'Renewal'} · ${new Date(event.occurred_at).toLocaleDateString('en-US')} · ${event.private_reference ?? 'No reference'}`
		}))
	);

	let activeAction = $state<CommercialAction | null>(null);
	let idempotencyKey = $state('');
	let amountUsd = $state('');
	let privateReference = $state('');
	let privateReason = $state('');
	let originalEventId = $state('');
	let paidThroughEffect = $state('');
	let paidThroughDate = $state('');
	let reactivate = $state(false);
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let feedbackMessage = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<CommercialInput | null>(null);

	function resetDialog() {
		activeAction = null;
		idempotencyKey = '';
		amountUsd = '';
		privateReference = '';
		privateReason = '';
		originalEventId = '';
		paidThroughEffect = '';
		paidThroughDate = '';
		reactivate = false;
		fieldErrors = {};
	}

	function openDialog(action: CommercialAction) {
		resetDialog();
		feedbackError = '';
		feedbackMessage = '';
		activeAction = action;
		idempotencyKey = crypto.randomUUID();
	}

	function closeDialog() {
		if (!commercialMutation.isPending) resetDialog();
	}

	function dollarsToCents(value: string) {
		const dollars = Number(value);
		return Number.isFinite(dollars) ? Math.round(dollars * 100) : 0;
	}

	function buildInput(action: CommercialAction): CommercialInput | null {
		const errors: Record<string, string> = {};
		const amount = dollarsToCents(amountUsd);
		if (!privateReference.trim()) errors.private_reference = 'Enter the private payment reference.';
		if (!paidThroughEffect) errors.paid_through_effect = 'Confirm the paid-through result.';
		if (paidThroughEffect === 'set' && !paidThroughDate)
			errors.paid_through_date = 'Confirm the resulting paid-through date.';
		if (action === 'correction' ? amount === 0 : amount <= 0)
			errors.amount_usd_cents =
				action === 'correction'
					? 'Enter a non-zero corrected amount.'
					: 'Enter an amount greater than zero.';
		if (action !== 'renewal' && !originalEventId)
			errors.original_event_id = 'Choose the original payment or renewal.';
		if (action !== 'renewal' && !privateReason.trim())
			errors.private_reason = 'Enter a private reason.';

		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return null;

		return {
			action,
			idempotency_key: idempotencyKey,
			paid_through_effect: paidThroughEffect as 'set' | 'unchanged',
			...(paidThroughEffect === 'set' ? { paid_through_date: paidThroughDate } : {}),
			amount_usd_cents: amount,
			private_reference: privateReference.trim(),
			...(privateReason.trim() ? { private_reason: privateReason.trim() } : {}),
			...(action !== 'renewal' ? { original_event_id: originalEventId } : {}),
			...(action === 'renewal' ? { reactivate } : {})
		};
	}

	const commercialMutation = createMutation<
		MutationResponse,
		CommercialActionError,
		CommercialInput
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/commercial`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new CommercialActionError(result);
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
		onSuccess: (_result, input) => {
			const action = input.action;
			resetDialog();
			pendingStepUpInput = null;
			feedbackMessage =
				action === 'renewal'
					? input.reactivate
						? 'Renewal recorded and organization reactivated.'
						: 'Renewal recorded.'
					: action === 'correction'
						? 'Payment correction recorded.'
						: action === 'refund'
							? 'Refund recorded.'
							: 'Payment reversal recorded.';
			void queryClient.invalidateQueries({
				queryKey: ['jafar', 'organizations', organizationId]
			});
			void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations'] });
		}
	}));

	function submit(action: CommercialAction, event: SubmitEvent) {
		event.preventDefault();
		const input = buildInput(action);
		if (input) commercialMutation.mutate(input);
	}

	function confirmRenewalReactivation() {
		if (pendingStepUpInput) commercialMutation.mutate(pendingStepUpInput);
	}
</script>

<div class="commercial-actions">
	<div class="commercial-actions__heading">
		<div>
			<h3>Payment actions</h3>
			<p>
				Each action adds an immutable commercial record. Original confirmations are never edited.
			</p>
		</div>
		<div class="commercial-actions__buttons">
			<Button variant="secondary" onclick={() => openDialog('renewal')}>Renew</Button>
			<Button
				variant="secondary"
				disabled={originalEvents.length === 0}
				onclick={() => openDialog('correction')}>Fix a mistake</Button
			>
			<Button
				variant="secondary"
				disabled={originalEvents.length === 0}
				onclick={() => openDialog('refund')}>Refund</Button
			>
			<Button
				variant="secondary"
				disabled={originalEvents.length === 0}
				onclick={() => openDialog('reversal')}>Reversal</Button
			>
		</div>
	</div>
	{#if originalEvents.length === 0}
		<p class="commercial-actions__notice">
			Fixes, refunds, and reversals need an initial-payment or renewal event to reference.
		</p>
	{/if}
	{#if feedbackMessage}<p class="commercial-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="commercial-actions__error" role="alert">{feedbackError}</p>{/if}
</div>

{#snippet originalEventField()}
	<div class="commercial-actions__field">
		<label for="commercial-original-event">Original payment or renewal</label>
		<Select
			id="commercial-original-event"
			ariaLabel="Original payment or renewal"
			placeholder="Choose the original event"
			options={originalEventOptions}
			bind:value={originalEventId}
		/>
		{#if fieldErrors.original_event_id}<p role="alert">{fieldErrors.original_event_id}</p>{/if}
	</div>
{/snippet}

{#snippet paidThroughFields()}
	<div class="commercial-actions__field">
		<label for="commercial-paid-through-effect">Paid-through result</label>
		<Select
			id="commercial-paid-through-effect"
			ariaLabel="Paid-through result"
			placeholder="Choose the resulting state"
			options={paidThroughOptions}
			bind:value={paidThroughEffect}
		/>
		{#if fieldErrors.paid_through_effect}<p role="alert">{fieldErrors.paid_through_effect}</p>{/if}
	</div>
	{#if paidThroughEffect === 'set'}
		<CalendarPicker
			id="commercial-paid-through-date"
			label="Resulting paid-through date"
			value={calendarDateFromString(paidThroughDate)}
			invalid={Boolean(fieldErrors.paid_through_date)}
			errorMessage={fieldErrors.paid_through_date}
			onchange={(value) => (paidThroughDate = calendarDateToString(value))}
		/>
	{:else if paidThroughEffect === 'unchanged'}
		<p class="commercial-actions__confirmation">
			The paid-through date will remain {currentPaidThroughDate ?? 'not recorded'}.
		</p>
	{/if}
{/snippet}

{#snippet referenceAndReason(reasonRequired: boolean)}
	<Input
		id="commercial-private-reference"
		label="Private payment reference"
		bind:value={privateReference}
		invalid={Boolean(fieldErrors.private_reference)}
		errorMessage={fieldErrors.private_reference}
	/>
	<Input
		id="commercial-private-reason"
		label={reasonRequired ? 'Private reason' : 'Private note (optional)'}
		bind:value={privateReason}
		invalid={Boolean(fieldErrors.private_reason)}
		errorMessage={fieldErrors.private_reason}
	/>
{/snippet}

<Dialog open={activeAction === 'renewal'} title="Record renewal" onClose={closeDialog}>
	<form class="commercial-actions__form" onsubmit={(event) => submit('renewal', event)}>
		<p>Record the offsite renewal amount and explicitly confirm the resulting access date.</p>
		<Input
			id="renewal-amount"
			label="Renewal amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={amountUsd}
			invalid={Boolean(fieldErrors.amount_usd_cents)}
			errorMessage={fieldErrors.amount_usd_cents}
		/>
		{@render referenceAndReason(false)}
		{@render paidThroughFields()}
		{#if lifecycleStatus === 'suspended'}
			<Checkbox
				id="renewal-reactivate"
				label="Record renewal and reactivate"
				description="Reactivation requires password reconfirmation and happens in the same transaction."
				bind:checked={reactivate}
			/>
		{/if}
		<div class="commercial-actions__dialog-actions">
			<Button type="submit" loading={commercialMutation.isPending}
				>{reactivate ? 'Renew and reactivate' : 'Record renewal'}</Button
			>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={activeAction === 'correction'} title="Fix a payment mistake" onClose={closeDialog}>
	<form class="commercial-actions__form" onsubmit={(event) => submit('correction', event)}>
		<p>Add a correction without changing the original confirmation.</p>
		{@render originalEventField()}
		<Input
			id="correction-amount"
			label="Corrected amount (USD)"
			type="number"
			step="0.01"
			bind:value={amountUsd}
			invalid={Boolean(fieldErrors.amount_usd_cents)}
			errorMessage={fieldErrors.amount_usd_cents}
		/>
		{@render referenceAndReason(true)}
		{@render paidThroughFields()}
		<div class="commercial-actions__dialog-actions">
			<Button type="submit" loading={commercialMutation.isPending}>Record correction</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={activeAction === 'refund'} title="Record refund" onClose={closeDialog}>
	<form class="commercial-actions__form" onsubmit={(event) => submit('refund', event)}>
		<p>Enter the refund as a positive amount. The refund event records that it reduces value.</p>
		{@render originalEventField()}
		<Input
			id="refund-amount"
			label="Refund amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={amountUsd}
			invalid={Boolean(fieldErrors.amount_usd_cents)}
			errorMessage={fieldErrors.amount_usd_cents}
		/>
		{@render referenceAndReason(true)}
		{@render paidThroughFields()}
		<div class="commercial-actions__dialog-actions">
			<Button type="submit" loading={commercialMutation.isPending}>Record refund</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={activeAction === 'reversal'} title="Record payment reversal" onClose={closeDialog}>
	<form class="commercial-actions__form" onsubmit={(event) => submit('reversal', event)}>
		<p>
			Enter the reversal as a positive amount. The reversal event records that it reduces value.
		</p>
		{@render originalEventField()}
		<Input
			id="reversal-amount"
			label="Reversal amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={amountUsd}
			invalid={Boolean(fieldErrors.amount_usd_cents)}
			errorMessage={fieldErrors.amount_usd_cents}
		/>
		{@render referenceAndReason(true)}
		{@render paidThroughFields()}
		<div class="commercial-actions__dialog-actions">
			<Button type="submit" loading={commercialMutation.isPending}>Record reversal</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm renewal and reactivation"
	description="This records the renewal and reactivates the suspended organization in one transaction."
	confirmLabel="Renew and reactivate"
	onConfirm={confirmRenewalReactivation}
/>

<style lang="scss">
	.commercial-actions,
	.commercial-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.commercial-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.commercial-actions__heading h3 {
		font-size: var(--typography--fontSize-large);
	}
	.commercial-actions__heading p,
	.commercial-actions__form > p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.commercial-actions__buttons,
	.commercial-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.commercial-actions__field {
		display: grid;
		gap: var(--space-smaller);
	}
	.commercial-actions__field > label {
		color: var(--color-text);
	}
	.commercial-actions__field > p,
	.commercial-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.commercial-actions__notice,
	.commercial-actions__confirmation {
		padding: var(--space-small) var(--space-slim);
		border-radius: var(--radius-small);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.commercial-actions__success {
		color: var(--color-success--onSurface);
	}
	@media (max-width: 639px) {
		.commercial-actions__heading {
			flex-direction: column;
			align-items: stretch;
		}
		.commercial-actions__buttons {
			justify-content: flex-start;
		}
	}
</style>
