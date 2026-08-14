<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';

	type SuspensionCategory = 'nonpayment' | 'payment_dispute' | 'security' | 'support' | 'other';
	type Readiness = {
		package_assigned: boolean;
		administrator_exists: boolean;
		administrator_login_ready: boolean;
		paid_through_eligible: boolean;
		free_access_active: boolean;
	};
	type ReadinessResponse = {
		organization: { id: string; name: string; lifecycle_status: string };
		readiness: Readiness;
		error?: string;
	};
	type ReconcileInput =
		| {
				status: 'suspended';
				suspension_category: SuspensionCategory;
				reason: string;
				idempotency_key: string;
		  }
		| { status: 'active'; reason: string; idempotency_key: string };
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};

	class ReconcileActionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'The organization could not be reconciled.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const categoryOptions: { value: SuspensionCategory; label: string }[] = [
		{ value: 'nonpayment', label: 'Nonpayment' },
		{ value: 'payment_dispute', label: 'Payment dispute' },
		{ value: 'security', label: 'Security' },
		{ value: 'support', label: 'Support' },
		{ value: 'other', label: 'Other' }
	];

	const readinessQuery = createQuery<ReadinessResponse>(() => ({
		queryKey: ['jafar', 'organizations', organizationId, 'legacy-review'],
		queryFn: async () => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/legacy-review`);
			const result = (await response.json()) as ReadinessResponse;
			if (!response.ok) throw new Error(result.error ?? 'Legacy readiness could not be loaded.');
			return result;
		}
	}));
	const readiness = $derived(readinessQuery.data?.readiness ?? null);
	const canActivate = $derived(
		Boolean(
			readiness?.package_assigned &&
				readiness?.administrator_exists &&
				readiness?.administrator_login_ready &&
				(readiness?.paid_through_eligible || readiness?.free_access_active)
		)
	);

	let activeAction = $state<'suspended' | 'active' | null>(null);
	let idempotencyKey = $state('');
	let suspensionCategory = $state<SuspensionCategory | ''>('');
	let reason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let feedbackMessage = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<ReconcileInput | null>(null);

	function resetDialog() {
		activeAction = null;
		idempotencyKey = '';
		suspensionCategory = '';
		reason = '';
		fieldErrors = {};
	}

	function openDialog(action: 'suspended' | 'active') {
		resetDialog();
		feedbackError = '';
		feedbackMessage = '';
		activeAction = action;
		idempotencyKey = crypto.randomUUID();
	}

	function closeDialog() {
		if (!reconcileMutation.isPending) resetDialog();
	}

	function buildInput(action: 'suspended' | 'active'): ReconcileInput | null {
		const errors: Record<string, string> = {};
		if (!reason.trim()) errors.reason = 'Enter a reconciliation reason.';
		if (action === 'suspended' && !suspensionCategory)
			errors.suspension_category = 'Choose a category.';

		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return null;

		return action === 'suspended'
			? {
					status: 'suspended',
					suspension_category: suspensionCategory as SuspensionCategory,
					reason: reason.trim(),
					idempotency_key: idempotencyKey
				}
			: { status: 'active', reason: reason.trim(), idempotency_key: idempotencyKey };
	}

	const reconcileMutation = createMutation<MutationResponse, ReconcileActionError, ReconcileInput>(
		() => ({
			mutationFn: async (input) => {
				const response = await fetch(`/api/jafar/organizations/${organizationId}/legacy-review`, {
					method: 'PATCH',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(input)
				});
				const result = (await response.json()) as MutationResponse;
				if (!response.ok) throw new ReconcileActionError(result);
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
				resetDialog();
				pendingStepUpInput = null;
				feedbackMessage =
					input.status === 'suspended'
						? 'Legacy organization suspended.'
						: 'Legacy organization activated.';
				void queryClient.invalidateQueries({
					queryKey: ['jafar', 'organizations', organizationId]
				});
				void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations'] });
			}
		})
	);

	function submit(action: 'suspended' | 'active', event: SubmitEvent) {
		event.preventDefault();
		const input = buildInput(action);
		if (input) reconcileMutation.mutate(input);
	}

	function confirmStepUp() {
		if (pendingStepUpInput) reconcileMutation.mutate(pendingStepUpInput);
	}
</script>

<div class="legacy-reconcile-actions">
	{#if readinessQuery.isPending}
		<LoadingSkeleton variant="text" label="Loading legacy review checklist" />
	{:else if readinessQuery.isError}
		<p class="legacy-reconcile-actions__error" role="alert">
			{readinessQuery.error instanceof Error
				? readinessQuery.error.message
				: 'Legacy readiness could not be loaded.'}
		</p>
	{:else if readiness}
		<ul class="legacy-reconcile-actions__checklist">
			<li>
				<Badge status={readiness.package_assigned ? 'success' : 'warning'}
					>{readiness.package_assigned ? 'Ready' : 'Needs review'}</Badge
				>
				<span>Published package version assigned</span>
			</li>
			<li>
				<Badge status={readiness.administrator_exists ? 'success' : 'warning'}
					>{readiness.administrator_exists ? 'Ready' : 'Needs review'}</Badge
				>
				<span>Owner or admin exists</span>
			</li>
			<li>
				<Badge status={readiness.administrator_login_ready ? 'success' : 'warning'}
					>{readiness.administrator_login_ready ? 'Ready' : 'Needs review'}</Badge
				>
				<span>Administrator has completed login setup</span>
			</li>
			<li>
				<Badge
					status={readiness.paid_through_eligible || readiness.free_access_active
						? 'success'
						: 'warning'}
					>{readiness.paid_through_eligible || readiness.free_access_active
						? 'Ready'
						: 'Needs review'}</Badge
				>
				<span>Paid-through date or active free access on record</span>
			</li>
		</ul>

		<div class="legacy-reconcile-actions__buttons">
			<Button onclick={() => openDialog('active')} disabled={!canActivate}>Activate organization</Button>
			<Button variant="secondary" variation="destructive" onclick={() => openDialog('suspended')}
				>Suspend organization</Button
			>
		</div>
		{#if !canActivate}
			<p class="legacy-reconcile-actions__note">
				Resolve every unready item above before activating. Suspending is always available.
			</p>
		{/if}
	{/if}

	{#if feedbackMessage}<p class="legacy-reconcile-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="legacy-reconcile-actions__error" role="alert">{feedbackError}</p>{/if}
</div>

<Dialog open={activeAction === 'active'} title="Activate legacy organization" onClose={closeDialog}>
	<form class="legacy-reconcile-actions__form" onsubmit={(event) => submit('active', event)}>
		<p>
			This one-time review moves the organization out of legacy pending setup into active
			commercial access.
		</p>
		<Input
			id="legacy-activate-reason"
			label="Reconciliation reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="legacy-reconcile-actions__dialog-actions">
			<Button type="submit" loading={reconcileMutation.isPending}>Activate organization</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog
	open={activeAction === 'suspended'}
	title="Suspend legacy organization"
	onClose={closeDialog}
>
	<form class="legacy-reconcile-actions__form" onsubmit={(event) => submit('suspended', event)}>
		<p>
			This one-time review moves the organization out of legacy pending setup into suspended. No
			readiness checks are required to suspend.
		</p>
		<div class="legacy-reconcile-actions__field">
			<label for="legacy-suspend-category">Category</label>
			<Select
				id="legacy-suspend-category"
				ariaLabel="Suspension category"
				placeholder="Choose a category"
				options={categoryOptions}
				bind:value={suspensionCategory}
			/>
			{#if fieldErrors.suspension_category}<p role="alert">
					{fieldErrors.suspension_category}
				</p>{/if}
		</div>
		<Input
			id="legacy-suspend-reason"
			label="Reconciliation reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="legacy-reconcile-actions__dialog-actions">
			<Button type="submit" variation="destructive" loading={reconcileMutation.isPending}
				>Suspend organization</Button
			>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm activation"
	description="Activating a legacy organization requires a recent password reconfirmation."
	confirmLabel="Activate organization"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.legacy-reconcile-actions {
		display: grid;
		gap: var(--space-base);
	}
	.legacy-reconcile-actions__checklist {
		display: grid;
		gap: var(--space-smaller);
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.legacy-reconcile-actions__checklist li {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	.legacy-reconcile-actions__checklist span {
		color: var(--color-text--secondary);
	}
	.legacy-reconcile-actions__buttons {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.legacy-reconcile-actions__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.legacy-reconcile-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.legacy-reconcile-actions__form > p {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.legacy-reconcile-actions__field {
		display: grid;
		gap: var(--space-smaller);
	}
	.legacy-reconcile-actions__field > label {
		color: var(--color-text);
	}
	.legacy-reconcile-actions__field > p,
	.legacy-reconcile-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.legacy-reconcile-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.legacy-reconcile-actions__success {
		color: var(--color-success--onSurface);
	}
</style>
