<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';
	import {
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import { jafarOrganizationSmsPromotionalCreditsKey } from '$lib/jafar/query-keys';

	type PromotionalCredit = {
		id: string;
		currency_code: string;
		amount_minor: number;
		reason: string;
		granted_at: string;
		expires_at: string;
		status: 'active' | 'revoked';
		revoked_at: string | null;
		revoke_reason: string | null;
	};
	type ListResponse = { credits?: PromotionalCredit[]; error?: string };
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};
	type GrantInput = {
		kind: 'grant';
		amount_minor: number;
		expires_at: string;
		reason: string;
		idempotency_key: string;
	};
	type RevokeInput = { kind: 'revoke'; creditId: string; reason: string };
	type CreditInput = GrantInput | RevokeInput;

	class CreditError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'The promotional credit could not be changed.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const listKey = $derived(jafarOrganizationSmsPromotionalCreditsKey(organizationId));

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/promotional-credits`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'SMS promotional credits could not be loaded.');
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
	function creditState(credit: PromotionalCredit): 'active' | 'expired' | 'revoked' {
		if (credit.status === 'revoked') return 'revoked';
		return new Date(credit.expires_at).getTime() > Date.now() ? 'active' : 'expired';
	}
	const stateTone: Record<'active' | 'expired' | 'revoked', 'success' | 'inactive'> = {
		active: 'success',
		expired: 'inactive',
		revoked: 'inactive'
	};
	const stateLabel: Record<'active' | 'expired' | 'revoked', string> = {
		active: 'Active',
		expired: 'Expired',
		revoked: 'Revoked'
	};

	let grantOpen = $state(false);
	let grantAmountUsd = $state('');
	let grantExpiry = $state('');
	let grantReason = $state('');
	let revokeOpen = $state<string | null>(null);
	let revokeReason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackMessage = $state('');
	let feedbackError = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<CreditInput | null>(null);

	function defaultExpiry() {
		const inThirtyDays = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(inThirtyDays));
	}
	function openGrant() {
		grantAmountUsd = '';
		grantExpiry = defaultExpiry();
		grantReason = '';
		fieldErrors = {};
		feedbackError = '';
		grantOpen = true;
	}
	function openRevoke(creditId: string) {
		revokeOpen = creditId;
		revokeReason = '';
		fieldErrors = {};
		feedbackError = '';
	}
	function handleGrantExpiryChange(value: DateTimePickerValue) {
		grantExpiry = dateTimePickerValueToLocalString(value);
	}

	const creditMutation = createMutation<MutationResponse, CreditError, CreditInput>(() => ({
		mutationFn: async (input) => {
			const url =
				input.kind === 'grant'
					? `/api/jafar/organizations/${organizationId}/communications/sms/promotional-credits`
					: `/api/jafar/organizations/${organizationId}/communications/sms/promotional-credits/${input.creditId}/revoke`;
			const body =
				input.kind === 'grant'
					? {
							amount_minor: input.amount_minor,
							expires_at: input.expires_at,
							reason: input.reason,
							idempotency_key: input.idempotency_key
						}
					: { reason: input.reason };
			const response = await fetch(url, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new CreditError(result);
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
			grantOpen = false;
			revokeOpen = null;
			pendingStepUpInput = null;
			feedbackMessage = input.kind === 'grant' ? 'Promotional credit granted.' : 'Credit revoked.';
			await queryClient.invalidateQueries({ queryKey: listKey });
		}
	}));

	function submitGrant(event: SubmitEvent) {
		event.preventDefault();
		const errors: Record<string, string> = {};
		const dollars = Number(grantAmountUsd);
		const amountMinor = Number.isFinite(dollars) ? Math.round(dollars * 100) : 0;
		if (amountMinor <= 0) errors.amount_minor = 'Enter an amount greater than zero.';
		if (!grantExpiry) errors.expires_at = 'Choose when this credit expires.';
		if (!grantReason.trim() || grantReason.trim().length < 3)
			errors.reason = 'Enter a reason of at least 3 characters.';
		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return;
		creditMutation.mutate({
			kind: 'grant',
			amount_minor: amountMinor,
			expires_at: localDateTimeToIso(grantExpiry),
			reason: grantReason.trim(),
			idempotency_key: crypto.randomUUID()
		});
	}
	function submitRevoke(event: SubmitEvent) {
		event.preventDefault();
		if (!revokeOpen) return;
		if (!revokeReason.trim() || revokeReason.trim().length < 3) {
			fieldErrors = { reason: 'Enter a reason of at least 3 characters.' };
			return;
		}
		creditMutation.mutate({ kind: 'revoke', creditId: revokeOpen, reason: revokeReason.trim() });
	}
	function confirmStepUp() {
		if (pendingStepUpInput) creditMutation.mutate(pendingStepUpInput);
	}
</script>

<div class="sms-promo-actions">
	<div class="sms-promo-actions__heading">
		<div>
			<h3>Promotional SMS credit</h3>
			<p>Expiring credit kept separate from purchased credit. It never affects settled money.</p>
		</div>
		<Button size="small" variant="secondary" onclick={openGrant}>Grant credit</Button>
	</div>

	{#if feedbackMessage}<p class="sms-promo-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="sms-promo-actions__error" role="alert">{feedbackError}</p>{/if}

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={2} label="Loading promotional credits" />
	{:else if listQuery.isError}
		<ErrorState
			title="Promotional credits could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else if (listQuery.data?.credits ?? []).length === 0}
		<EmptyState
			title="No promotional credit granted"
			description="Grant expiring credit for a promotion or goodwill gesture."
		/>
	{:else}
		<ul class="sms-promo-actions__list">
			{#each listQuery.data?.credits ?? [] as credit (credit.id)}
				{@const state = creditState(credit)}
				<li class="sms-promo-actions__row">
					<div class="sms-promo-actions__row-heading">
						<div>
							<h4>{formatMoney(credit.amount_minor, credit.currency_code)}</h4>
							<p>{credit.reason}</p>
						</div>
						<Badge status={stateTone[state]}>{stateLabel[state]}</Badge>
					</div>
					<p class="sms-promo-actions__meta">
						Granted {formatTime(credit.granted_at)} &middot; expires {formatTime(credit.expires_at)}
					</p>
					{#if credit.status === 'revoked' && credit.revoke_reason}
						<p class="sms-promo-actions__meta">
							Revoked {formatTime(credit.revoked_at)} &middot; {credit.revoke_reason}
						</p>
					{:else if state === 'active'}
						<div class="sms-promo-actions__row-actions">
							<Button
								size="small"
								variant="secondary"
								variation="subtle"
								onclick={() => openRevoke(credit.id)}
							>
								Revoke
							</Button>
						</div>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<Dialog open={grantOpen} title="Grant promotional credit" onClose={() => (grantOpen = false)}>
	<form class="sms-promo-actions__form" onsubmit={submitGrant}>
		<Input
			id="sms-promo-amount"
			label="Amount (USD)"
			type="number"
			min="0.01"
			step="0.01"
			bind:value={grantAmountUsd}
			invalid={Boolean(fieldErrors.amount_minor)}
			errorMessage={fieldErrors.amount_minor}
		/>
		<DateTimePicker
			id="sms-promo-expiry"
			dateLabel="Expires on"
			timeLabel="Expires at"
			value={dateTimePickerValueFromLocalString(grantExpiry)}
			required
			onchange={handleGrantExpiryChange}
		/>
		{#if fieldErrors.expires_at}<p class="sms-promo-actions__error" role="alert">
				{fieldErrors.expires_at}
			</p>{/if}
		<Textarea
			id="sms-promo-reason"
			label="Reason"
			bind:value={grantReason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
			required
		/>
		<div class="sms-promo-actions__dialog-actions">
			<Button type="submit" loading={creditMutation.isPending}>Grant credit</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (grantOpen = false)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<Dialog
	open={revokeOpen !== null}
	title="Revoke promotional credit"
	onClose={() => (revokeOpen = null)}
>
	<form class="sms-promo-actions__form" onsubmit={submitRevoke}>
		<Textarea
			id="sms-promo-revoke-reason"
			label="Reason"
			bind:value={revokeReason}
			rows={3}
			maxlength={2000}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
			required
		/>
		<div class="sms-promo-actions__dialog-actions">
			<Button type="submit" variation="destructive" loading={creditMutation.isPending}>
				Revoke credit
			</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (revokeOpen = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm this promotional credit change"
	description="Money decisions require a fresh password reconfirmation."
	confirmLabel="Confirm"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.sms-promo-actions,
	.sms-promo-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-promo-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-promo-actions__heading h3 {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
	}
	.sms-promo-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-promo-actions__success {
		color: var(--color-success--onSurface);
	}
	.sms-promo-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.sms-promo-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-promo-actions__row {
		display: grid;
		gap: var(--space-smallest);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-promo-actions__row-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-promo-actions__row-heading h4 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
	}
	.sms-promo-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-promo-actions__meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-promo-actions__row-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.sms-promo-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	@media (max-width: 639px) {
		.sms-promo-actions__heading,
		.sms-promo-actions__row-heading {
			flex-direction: column;
		}
	}
</style>
