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
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';

	type RegistrationStatus = 'waiting_for_info' | 'under_review' | 'action_needed' | 'approved';
	type ReadinessState =
		| 'not_included'
		| 'needs_setup'
		| 'waiting_for_info'
		| 'under_review'
		| 'action_needed'
		| 'finishing_setup'
		| 'ready';
	type Registration = {
		id: string;
		country_code: string;
		sender_type: string;
		use_case: string;
		status: RegistrationStatus;
		provider_registration_sid: string | null;
		provider_outcome: string | null;
		required_fixes: string | null;
		submitted_at: string | null;
		last_checked_at: string | null;
		readiness_state: ReadinessState;
		live_sender_count: number;
	};
	type ListResponse = { registrations?: Registration[]; error?: string };
	type MutationResponse = { error?: string; field_errors?: Record<string, string> };

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const listKey = $derived(['jafar', 'organizations', organizationId, 'sms', 'registrations']);

	const listQuery = createQuery<ListResponse>(() => ({
		queryKey: listKey,
		queryFn: async () => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/registrations`
			);
			const result = (await response.json()) as ListResponse;
			if (!response.ok) throw new Error(result.error ?? 'SMS registrations could not be loaded.');
			return result;
		},
		staleTime: 15_000
	}));

	const senderTypeOptions = [
		{ value: 'long_code', label: 'Long code' },
		{ value: 'toll_free', label: 'Toll-free' },
		{ value: 'short_code', label: 'Short code' },
		{ value: 'alphanumeric', label: 'Alphanumeric' }
	];
	const readinessLabels: Record<ReadinessState, string> = {
		not_included: 'Not included',
		needs_setup: 'Needs setup',
		waiting_for_info: 'Waiting for info',
		under_review: 'Under review',
		action_needed: 'Action needed',
		finishing_setup: 'Finishing setup',
		ready: 'Ready'
	};
	const readinessTone: Record<
		ReadinessState,
		'success' | 'warning' | 'critical' | 'informative' | 'inactive'
	> = {
		not_included: 'inactive',
		needs_setup: 'inactive',
		waiting_for_info: 'warning',
		under_review: 'informative',
		action_needed: 'critical',
		finishing_setup: 'warning',
		ready: 'success'
	};

	function formatTime(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
					new Date(value)
				)
			: 'Not yet';
	}

	// Start (or reopen) a registration -----------------------------------------------------------
	let startOpen = $state(false);
	let startCountry = $state('');
	let startSenderType = $state('long_code');
	let startUseCase = $state('');
	const toast = getToastManager();
	let startFieldErrors = $state<Record<string, string>>({});

	function openStart() {
		startCountry = '';
		startSenderType = 'long_code';
		startUseCase = '';
		startFieldErrors = {};
		startOpen = true;
	}

	const startMutation = createMutation<
		MutationResponse,
		Error,
		{ country_code: string; sender_type: string; use_case: string }
	>(() => ({
		mutationFn: async (body) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/registrations`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) {
				startFieldErrors = result.field_errors ?? {};
				throw new Error(result.error ?? 'The registration could not be started.');
			}
			return result;
		},
		onError: (error) => (startFieldErrors.form = error.message),
		onSuccess: async () => {
			startOpen = false;
			await queryClient.invalidateQueries({ queryKey: listKey });
			toast.success('Registration started.');
		}
	}));

	function submitStart(event: SubmitEvent) {
		event.preventDefault();
		startFieldErrors = {};
		if (!/^[A-Za-z]{2}$/.test(startCountry.trim())) {
			startFieldErrors.country_code = 'Enter a 2-letter country code.';
			return;
		}
		if (!startUseCase.trim()) {
			startFieldErrors.use_case = 'Enter the use case.';
			return;
		}
		startMutation.mutate({
			country_code: startCountry.trim().toUpperCase(),
			sender_type: startSenderType,
			use_case: startUseCase.trim()
		});
	}

	// Record a readiness check --------------------------------------------------------------------
	let checkOpen = $state<string | null>(null);
	let checkDetail = $state('');

	const checkMutation = createMutation<MutationResponse, Error, { registrationId: string }>(() => ({
		mutationFn: async ({ registrationId }) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/registrations/${registrationId}/checks`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify({ detail: checkDetail.trim() || undefined })
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok)
				throw new Error(result.error ?? 'The readiness check could not be recorded.');
			return result;
		},
		onError: (error) => toast.error(error.message),
		onSuccess: async () => {
			checkOpen = null;
			checkDetail = '';
			await queryClient.invalidateQueries({ queryKey: listKey });
			toast.success('Readiness check recorded.');
		}
	}));

	// Record the carrier/provider outcome ---------------------------------------------------------
	let outcomeOpen = $state<string | null>(null);
	let outcomeDecision = $state<'approved' | 'action_needed'>('approved');
	let outcomeText = $state('');
	let outcomeError = $state('');

	function openOutcome(registrationId: string) {
		outcomeOpen = registrationId;
		outcomeDecision = 'approved';
		outcomeText = '';
		outcomeError = '';
	}

	const outcomeMutation = createMutation<
		MutationResponse,
		Error,
		{ registrationId: string; body: Record<string, unknown> }
	>(() => ({
		mutationFn: async ({ registrationId, body }) => {
			const response = await fetch(
				`/api/jafar/organizations/${organizationId}/communications/sms/registrations/${registrationId}/outcome`,
				{
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body)
				}
			);
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new Error(result.error ?? 'The outcome could not be recorded.');
			return result;
		},
		onError: (error) => (outcomeError = error.message),
		onSuccess: async () => {
			outcomeOpen = null;
			await queryClient.invalidateQueries({ queryKey: listKey });
			toast.success('Registration outcome recorded.');
		}
	}));

	function submitOutcome(event: SubmitEvent) {
		event.preventDefault();
		if (!outcomeOpen) return;
		if (!outcomeText.trim()) {
			outcomeError =
				outcomeDecision === 'approved'
					? 'Enter the provider outcome.'
					: 'Enter the fixes the contractor must make.';
			return;
		}
		outcomeMutation.mutate({
			registrationId: outcomeOpen,
			body:
				outcomeDecision === 'approved'
					? { status: 'approved', provider_outcome: outcomeText.trim() }
					: { status: 'action_needed', required_fixes: outcomeText.trim() }
		});
	}
</script>

<div class="sms-registration-actions">
	<div class="sms-registration-actions__heading">
		<div>
			<h3>SMS registration</h3>
			<p>
				One registration per country, sender type and use case. Every submission and decision is
				kept in its own immutable history.
			</p>
		</div>
		<Button size="small" variant="secondary" onclick={openStart}>Start registration</Button>
	</div>

	{#if listQuery.isPending}
		<LoadingSkeleton variant="table" rows={3} label="Loading SMS registrations" />
	{:else if listQuery.isError}
		<ErrorState
			title="SMS registrations could not be loaded"
			description={listQuery.error instanceof Error ? listQuery.error.message : 'Try again.'}
			retry={() => listQuery.refetch()}
		/>
	{:else if (listQuery.data?.registrations ?? []).length === 0}
		<EmptyState
			title="No registration started"
			description="Start a registration for the country, sender type and use case this organization needs."
		/>
	{:else}
		<ul class="sms-registration-actions__list">
			{#each listQuery.data?.registrations ?? [] as registration (registration.id)}
				<li class="sms-registration-actions__row">
					<div class="sms-registration-actions__row-heading">
						<div>
							<h4>
								{registration.country_code} &middot; {registration.sender_type} &middot; {registration.use_case}
							</h4>
							<p>
								Submitted {formatTime(registration.submitted_at)} &middot; last checked {formatTime(
									registration.last_checked_at
								)}
							</p>
						</div>
						<Badge status={readinessTone[registration.readiness_state]}>
							{readinessLabels[registration.readiness_state]}
						</Badge>
					</div>
					{#if registration.provider_outcome}
						<p class="sms-registration-actions__note">{registration.provider_outcome}</p>
					{/if}
					{#if registration.required_fixes}
						<p class="sms-registration-actions__note sms-registration-actions__note--critical">
							{registration.required_fixes}
						</p>
					{/if}
					<div class="sms-registration-actions__row-actions">
						<Button
							size="small"
							variant="secondary"
							variation="subtle"
							onclick={() => {
								checkOpen = registration.id;
								checkDetail = '';
							}}
						>
							Record check
						</Button>
						{#if registration.status === 'under_review'}
							<Button
								size="small"
								variant="secondary"
								variation="subtle"
								onclick={() => openOutcome(registration.id)}
							>
								Record decision
							</Button>
						{/if}
					</div>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<Dialog open={startOpen} title="Start a registration" onClose={() => (startOpen = false)}>
	<form class="sms-registration-actions__form" onsubmit={submitStart}>
		<Input
			id="sms-registration-country"
			label="Country code (e.g. US)"
			bind:value={startCountry}
			maxlength={2}
			invalid={Boolean(startFieldErrors.country_code)}
			errorMessage={startFieldErrors.country_code}
		/>
		<Select
			id="sms-registration-sender-type"
			label="Sender type"
			options={senderTypeOptions}
			bind:value={startSenderType}
		/>
		<Input
			id="sms-registration-use-case"
			label="Use case"
			bind:value={startUseCase}
			invalid={Boolean(startFieldErrors.use_case)}
			errorMessage={startFieldErrors.use_case}
		/>
		{#if startFieldErrors.form}<p class="sms-registration-actions__error" role="alert">
				{startFieldErrors.form}
			</p>{/if}
		<div class="sms-registration-actions__dialog-actions">
			<Button type="submit" loading={startMutation.isPending}>Start registration</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (startOpen = false)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<Dialog
	open={checkOpen !== null}
	title="Record a readiness check"
	onClose={() => (checkOpen = null)}
>
	<form
		class="sms-registration-actions__form"
		onsubmit={(event) => {
			event.preventDefault();
			if (checkOpen) checkMutation.mutate({ registrationId: checkOpen });
		}}
	>
		<p>Records that real provider readiness was checked, without changing the status.</p>
		<Textarea
			id="sms-registration-check-detail"
			label="Note (optional)"
			bind:value={checkDetail}
			rows={3}
			maxlength={2000}
		/>
		<div class="sms-registration-actions__dialog-actions">
			<Button type="submit" loading={checkMutation.isPending}>Record check</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (checkOpen = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<Dialog
	open={outcomeOpen !== null}
	title="Record the carrier decision"
	onClose={() => (outcomeOpen = null)}
>
	<form class="sms-registration-actions__form" onsubmit={submitOutcome}>
		<Select
			id="sms-registration-outcome-decision"
			label="Decision"
			options={[
				{ value: 'approved', label: 'Approved' },
				{ value: 'action_needed', label: 'Action needed' }
			]}
			bind:value={outcomeDecision}
		/>
		<Textarea
			id="sms-registration-outcome-text"
			label={outcomeDecision === 'approved'
				? 'Provider outcome (shown to the contractor)'
				: 'Fixes the contractor must make'}
			bind:value={outcomeText}
			rows={3}
			maxlength={2000}
			required
		/>
		{#if outcomeError}<p class="sms-registration-actions__error" role="alert">
				{outcomeError}
			</p>{/if}
		<div class="sms-registration-actions__dialog-actions">
			<Button type="submit" loading={outcomeMutation.isPending}>Record decision</Button>
			<Button
				type="button"
				variant="secondary"
				variation="subtle"
				onclick={() => (outcomeOpen = null)}
			>
				Cancel
			</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.sms-registration-actions {
		display: grid;
		gap: var(--space-base);
	}
	.sms-registration-actions__heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-registration-actions__heading h3 {
		font-size: var(--typography--fontSize-large);
	}
	.sms-registration-actions__heading p {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.sms-registration-actions__list {
		display: grid;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.sms-registration-actions__row {
		display: grid;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}
	.sms-registration-actions__row-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
	}
	.sms-registration-actions__row-heading h4 {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		text-transform: capitalize;
	}
	.sms-registration-actions__row-heading p {
		margin: var(--space-smallest) 0 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-registration-actions__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.sms-registration-actions__note--critical {
		color: var(--color-critical--onSurface);
	}
	.sms-registration-actions__row-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.sms-registration-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.sms-registration-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.sms-registration-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	@media (max-width: 639px) {
		.sms-registration-actions__heading,
		.sms-registration-actions__row-heading {
			flex-direction: column;
		}
	}
</style>
