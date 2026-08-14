<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';

	type SuspensionCategory = 'nonpayment' | 'payment_dispute' | 'security' | 'support' | 'other';
	type LifecycleInput =
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

	class LifecycleActionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'Organization status could not be changed.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let { organizationId, lifecycleStatus }: { organizationId: string; lifecycleStatus: string } =
		$props();

	const queryClient = useQueryClient();
	const categoryOptions: { value: SuspensionCategory; label: string }[] = [
		{ value: 'nonpayment', label: 'Nonpayment' },
		{ value: 'payment_dispute', label: 'Payment dispute' },
		{ value: 'security', label: 'Security' },
		{ value: 'support', label: 'Support' },
		{ value: 'other', label: 'Other' }
	];

	let activeAction = $state<'suspended' | 'active' | null>(null);
	let idempotencyKey = $state('');
	let suspensionCategory = $state<SuspensionCategory | ''>('');
	let reason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let feedbackMessage = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<LifecycleInput | null>(null);

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
		if (!lifecycleMutation.isPending) resetDialog();
	}

	function buildInput(action: 'suspended' | 'active'): LifecycleInput | null {
		const errors: Record<string, string> = {};
		if (!reason.trim()) errors.reason = 'Enter a private reason.';
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

	const lifecycleMutation = createMutation<MutationResponse, LifecycleActionError, LifecycleInput>(
		() => ({
			mutationFn: async (input) => {
				const response = await fetch(`/api/jafar/organizations/${organizationId}/lifecycle`, {
					method: 'PATCH',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(input)
				});
				const result = (await response.json()) as MutationResponse;
				if (!response.ok) throw new LifecycleActionError(result);
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
					input.status === 'suspended' ? 'Organization suspended.' : 'Organization reactivated.';
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
		if (input) lifecycleMutation.mutate(input);
	}

	function confirmStepUp() {
		if (pendingStepUpInput) lifecycleMutation.mutate(pendingStepUpInput);
	}
</script>

<div class="lifecycle-actions">
	{#if lifecycleStatus === 'active'}
		<Button variant="secondary" variation="destructive" onclick={() => openDialog('suspended')}
			>Suspend organization</Button
		>
	{:else}
		<Button variant="secondary" onclick={() => openDialog('active')}>Reactivate organization</Button
		>
	{/if}
	{#if feedbackMessage}<p class="lifecycle-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="lifecycle-actions__error" role="alert">{feedbackError}</p>{/if}
</div>

<Dialog open={activeAction === 'suspended'} title="Suspend organization" onClose={closeDialog}>
	<form class="lifecycle-actions__form" onsubmit={(event) => submit('suspended', event)}>
		<p>Contractors lose access immediately. Records stay preserved and reactivation stays available.</p>
		<div class="lifecycle-actions__field">
			<label for="suspend-category">Category</label>
			<Select
				id="suspend-category"
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
			id="suspend-reason"
			label="Private reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="lifecycle-actions__dialog-actions">
			<Button type="submit" variation="destructive" loading={lifecycleMutation.isPending}
				>Suspend organization</Button
			>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={activeAction === 'active'} title="Reactivate organization" onClose={closeDialog}>
	<form class="lifecycle-actions__form" onsubmit={(event) => submit('active', event)}>
		<p>
			Reactivating after nonpayment or a payment dispute requires restored paid-through eligibility
			or an active free-access grant. Other suspension reasons only need a resolution note.
		</p>
		<Input
			id="reactivate-reason"
			label="Reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="lifecycle-actions__dialog-actions">
			<Button type="submit" loading={lifecycleMutation.isPending}>Reactivate organization</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title={pendingStepUpInput?.status === 'suspended' ? 'Confirm suspension' : 'Confirm reactivation'}
	description="Suspension and reactivation both require a recent password reconfirmation."
	confirmLabel={pendingStepUpInput?.status === 'suspended'
		? 'Suspend organization'
		: 'Reactivate organization'}
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.lifecycle-actions {
		display: grid;
		gap: var(--space-small);
	}
	.lifecycle-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.lifecycle-actions__form > p {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.lifecycle-actions__field {
		display: grid;
		gap: var(--space-smaller);
	}
	.lifecycle-actions__field > label {
		color: var(--color-text);
	}
	.lifecycle-actions__field > p,
	.lifecycle-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.lifecycle-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.lifecycle-actions__success {
		color: var(--color-success--onSurface);
	}
</style>
