<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';

	type ClosureRecord = { id: string; reason: string; started_at: string; deadline_at: string } | null;
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};
	type StartInput = { reason: string; typed_organization_name: string; idempotency_key: string };
	type RestoreInput = { restoration_evidence_note: string; idempotency_key: string };

	class ClosureActionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'This action could not be completed.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let {
		organizationId,
		organizationName,
		lifecycleStatus,
		closure
	}: {
		organizationId: string;
		organizationName: string;
		lifecycleStatus: string;
		closure: ClosureRecord;
	} = $props();

	const queryClient = useQueryClient();

	let dialogOpen = $state<'start' | 'restore' | null>(null);
	let idempotencyKey = $state('');
	let reason = $state('');
	let typedName = $state('');
	let evidenceNote = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let feedbackMessage = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUp = $state<{ kind: 'start' | 'restore'; input: StartInput | RestoreInput } | null>(
		null
	);

	function resetDialog() {
		dialogOpen = null;
		idempotencyKey = '';
		reason = '';
		typedName = '';
		evidenceNote = '';
		fieldErrors = {};
	}

	function openStart() {
		resetDialog();
		feedbackError = '';
		feedbackMessage = '';
		dialogOpen = 'start';
		idempotencyKey = crypto.randomUUID();
	}

	function openRestore() {
		resetDialog();
		feedbackError = '';
		feedbackMessage = '';
		dialogOpen = 'restore';
		idempotencyKey = crypto.randomUUID();
	}

	function closeDialog() {
		if (!startMutation.isPending && !restoreMutation.isPending) resetDialog();
	}

	function daysRemaining(deadlineAt: string) {
		const ms = new Date(deadlineAt).getTime() - Date.now();
		return Math.max(0, Math.ceil(ms / (24 * 60 * 60 * 1000)));
	}

	function formatDateTime(value: string) {
		return new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
	}

	function invalidate() {
		void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations', organizationId] });
		void queryClient.invalidateQueries({ queryKey: ['jafar', 'organizations'] });
	}

	const startMutation = createMutation<MutationResponse, ClosureActionError, StartInput>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/closure/start`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new ClosureActionError(result);
			return result;
		},
		onMutate: () => {
			fieldErrors = {};
			feedbackError = '';
		},
		onError: (error, input) => {
			if (error.stepUpRequired) {
				pendingStepUp = { kind: 'start', input };
				reconfirmOpen = true;
				return;
			}
			fieldErrors = error.fieldErrors;
			feedbackError = error.message;
		},
		onSuccess: () => {
			resetDialog();
			pendingStepUp = null;
			feedbackMessage =
				'Closure started. Contractor access is blocked now. Restore any time in the next 30 days.';
			invalidate();
		}
	}));

	const restoreMutation = createMutation<MutationResponse, ClosureActionError, RestoreInput>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/closure/restore`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new ClosureActionError(result);
			return result;
		},
		onMutate: () => {
			fieldErrors = {};
			feedbackError = '';
		},
		onError: (error, input) => {
			if (error.stepUpRequired) {
				pendingStepUp = { kind: 'restore', input };
				reconfirmOpen = true;
				return;
			}
			fieldErrors = error.fieldErrors;
			feedbackError = error.message;
		},
		onSuccess: () => {
			resetDialog();
			pendingStepUp = null;
			feedbackMessage = 'Organization restored.';
			invalidate();
		}
	}));

	function buildStartInput(): StartInput | null {
		const errors: Record<string, string> = {};
		if (!reason.trim()) errors.reason = 'Enter a private reason.';
		if (typedName.trim() !== organizationName) {
			errors.typed_organization_name = 'Type the organization name exactly to confirm.';
		}
		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return null;
		return {
			reason: reason.trim(),
			typed_organization_name: typedName.trim(),
			idempotency_key: idempotencyKey
		};
	}

	function buildRestoreInput(): RestoreInput | null {
		const errors: Record<string, string> = {};
		if (!evidenceNote.trim()) errors.restoration_evidence_note = 'Describe how you verified this.';
		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return null;
		return { restoration_evidence_note: evidenceNote.trim(), idempotency_key: idempotencyKey };
	}

	function submitStart(event: SubmitEvent) {
		event.preventDefault();
		const input = buildStartInput();
		if (input) startMutation.mutate(input);
	}

	function submitRestore(event: SubmitEvent) {
		event.preventDefault();
		const input = buildRestoreInput();
		if (input) restoreMutation.mutate(input);
	}

	function confirmStepUp() {
		if (!pendingStepUp) return;
		if (pendingStepUp.kind === 'start') startMutation.mutate(pendingStepUp.input as StartInput);
		else restoreMutation.mutate(pendingStepUp.input as RestoreInput);
	}
</script>

<div class="closure-actions">
	{#if lifecycleStatus === 'pending_closure' || lifecycleStatus === 'closed'}
		{#if closure}
			<div class="closure-actions__countdown">
				<Badge status="critical"
					>{daysRemaining(closure.deadline_at)} day{daysRemaining(closure.deadline_at) === 1
						? ''
						: 's'} left to restore</Badge
				>
				<p>Permanent deletion happens {formatDateTime(closure.deadline_at)} unless restored.</p>
			</div>
		{/if}
		<Button variant="secondary" onclick={openRestore}>Restore organization</Button>
	{:else}
		<Button variant="secondary" variation="destructive" onclick={openStart}>Close organization</Button
		>
	{/if}
	{#if feedbackMessage}<p class="closure-actions__success" role="status">{feedbackMessage}</p>{/if}
	{#if feedbackError}<p class="closure-actions__error" role="alert">{feedbackError}</p>{/if}
</div>

<Dialog open={dialogOpen === 'start'} title="Close organization" onClose={closeDialog}>
	<form class="closure-actions__form" onsubmit={submitStart}>
		<p>
			Closing blocks the team from working right away. All contractor access stops today, and
			automatic email notices go out now, then again 14 and 3 days before deletion.
		</p>
		<p>
			<strong>If nobody restores this within 30 days, everything is deleted for good</strong> —
			customers, jobs, invoices, files, and login access. You can restore it any time during those
			30 days.
		</p>
		<Input
			id="closure-start-reason"
			label="Private reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<Input
			id="closure-start-typed-name"
			label={`Type "${organizationName}" to confirm`}
			bind:value={typedName}
			invalid={Boolean(fieldErrors.typed_organization_name)}
			errorMessage={fieldErrors.typed_organization_name}
		/>
		<div class="closure-actions__dialog-actions">
			<Button type="submit" variation="destructive" loading={startMutation.isPending}
				>Close organization</Button
			>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={dialogOpen === 'restore'} title="Restore organization" onClose={closeDialog}>
	<form class="closure-actions__form" onsubmit={submitRestore}>
		<p>
			Restoring returns this organization to its status before closure and cancels the deletion
			countdown. Contractor access resumes immediately.
		</p>
		<Input
			id="closure-restore-evidence"
			label="How did you verify this restoration?"
			bind:value={evidenceNote}
			invalid={Boolean(fieldErrors.restoration_evidence_note)}
			errorMessage={fieldErrors.restoration_evidence_note}
		/>
		<div class="closure-actions__dialog-actions">
			<Button type="submit" loading={restoreMutation.isPending}>Restore organization</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title={pendingStepUp?.kind === 'start' ? 'Confirm closure' : 'Confirm restoration'}
	description="This action requires a recent password reconfirmation."
	confirmLabel={pendingStepUp?.kind === 'start' ? 'Close organization' : 'Restore organization'}
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.closure-actions {
		display: grid;
		gap: var(--space-small);
	}
	.closure-actions__countdown {
		display: grid;
		gap: var(--space-smallest);
	}
	.closure-actions__countdown p {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.closure-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.closure-actions__form > p {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.closure-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.closure-actions__success {
		color: var(--color-success--onSurface);
	}
	.closure-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
</style>
