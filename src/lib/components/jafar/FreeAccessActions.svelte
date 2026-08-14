<script lang="ts">
	import { createMutation, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import OwnerReconfirmDialog from '$lib/components/jafar/OwnerReconfirmDialog.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';

	type FreeAccessGrant = { grant_id: string; starts_at: string; access_until_date: string | null };
	type FreeAccessState = { active: FreeAccessGrant | null; future: FreeAccessGrant | null };
	type FreeAccessAction = 'grant' | 'extend' | 'convert_to_forever' | 'end';
	type FreeAccessInput =
		| {
				action: 'grant';
				starts_at: string;
				access_until_date?: string | null;
				reason: string;
				idempotency_key: string;
		  }
		| {
				action: 'extend';
				grant_id: string;
				access_until_date: string;
				reason: string;
				idempotency_key: string;
		  }
		| { action: 'convert_to_forever'; grant_id: string; reason: string; idempotency_key: string }
		| { action: 'end'; grant_id: string; reason: string; idempotency_key: string };
	type MutationResponse = {
		error?: string;
		field_errors?: Record<string, string>;
		step_up_required?: boolean;
	};

	class FreeAccessActionError extends Error {
		fieldErrors: Record<string, string>;
		stepUpRequired: boolean;

		constructor(result: MutationResponse) {
			super(result.error ?? 'Free access could not be changed.');
			this.fieldErrors = result.field_errors ?? {};
			this.stepUpRequired = result.step_up_required === true;
		}
	}

	let {
		organizationId,
		hasPackageAssignment,
		freeAccess
	}: { organizationId: string; hasPackageAssignment: boolean; freeAccess: FreeAccessState } =
		$props();

	const queryClient = useQueryClient();

	const activeIsForever = $derived(
		freeAccess.active !== null && freeAccess.active.access_until_date === null
	);
	const canGrant = $derived(!activeIsForever && !(freeAccess.active && freeAccess.future));
	const panels = $derived(
		[
			{ label: 'Active', grant: freeAccess.active },
			{ label: 'Scheduled', grant: freeAccess.future }
		].filter((panel): panel is { label: string; grant: FreeAccessGrant } => panel.grant !== null)
	);

	function todayIso() {
		const date = new Date();
		return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(
			date.getDate()
		).padStart(2, '0')}`;
	}
	const todayCalendarDate = calendarDateFromString(todayIso());
	function formatCalendarDate(value: string | null) {
		if (!value) return 'forever';
		const [year, month, day] = value.split('-').map(Number);
		return new Date(year, month - 1, day).toLocaleDateString('en-US', {
			year: 'numeric',
			month: 'long',
			day: 'numeric'
		});
	}

	let activeAction = $state<FreeAccessAction | null>(null);
	let targetGrantId = $state<string | null>(null);
	let idempotencyKey = $state('');
	let startsAt = $state('');
	let untilDate = $state('');
	let reason = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let feedbackError = $state('');
	let feedbackMessage = $state('');
	let reconfirmOpen = $state(false);
	let pendingStepUpInput = $state<FreeAccessInput | null>(null);

	function resetDialog() {
		activeAction = null;
		targetGrantId = null;
		idempotencyKey = '';
		startsAt = '';
		untilDate = '';
		reason = '';
		fieldErrors = {};
	}

	function openGrantDialog() {
		resetDialog();
		feedbackError = '';
		feedbackMessage = '';
		activeAction = 'grant';
		idempotencyKey = crypto.randomUUID();
		startsAt = todayIso();
	}

	function openActionDialog(action: 'extend' | 'convert_to_forever' | 'end', grantId: string) {
		resetDialog();
		feedbackError = '';
		feedbackMessage = '';
		activeAction = action;
		targetGrantId = grantId;
		idempotencyKey = crypto.randomUUID();
	}

	function closeDialog() {
		if (!freeAccessMutation.isPending) resetDialog();
	}

	function buildInput(action: FreeAccessAction): FreeAccessInput | null {
		const errors: Record<string, string> = {};
		if (!reason.trim()) errors.reason = 'Enter a private reason.';
		if (action === 'grant' && !startsAt) errors.starts_at = 'Choose a start date.';
		if (action === 'extend' && !untilDate) errors.access_until_date = 'Choose a new end date.';
		if (
			(action === 'extend' || action === 'convert_to_forever' || action === 'end') &&
			!targetGrantId
		)
			errors.grant_id = 'The grant to act on is missing.';

		fieldErrors = errors;
		if (Object.keys(errors).length > 0) return null;

		if (action === 'grant')
			return {
				action: 'grant',
				starts_at: startsAt,
				access_until_date: untilDate || null,
				reason: reason.trim(),
				idempotency_key: idempotencyKey
			};
		if (action === 'extend')
			return {
				action: 'extend',
				grant_id: targetGrantId as string,
				access_until_date: untilDate,
				reason: reason.trim(),
				idempotency_key: idempotencyKey
			};
		if (action === 'convert_to_forever')
			return {
				action: 'convert_to_forever',
				grant_id: targetGrantId as string,
				reason: reason.trim(),
				idempotency_key: idempotencyKey
			};
		return {
			action: 'end',
			grant_id: targetGrantId as string,
			reason: reason.trim(),
			idempotency_key: idempotencyKey
		};
	}

	const freeAccessMutation = createMutation<
		MutationResponse,
		FreeAccessActionError,
		FreeAccessInput
	>(() => ({
		mutationFn: async (input) => {
			const response = await fetch(`/api/jafar/organizations/${organizationId}/free-access`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(input)
			});
			const result = (await response.json()) as MutationResponse;
			if (!response.ok) throw new FreeAccessActionError(result);
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
				input.action === 'grant'
					? 'Free access granted.'
					: input.action === 'extend'
						? 'Free access extended.'
						: input.action === 'convert_to_forever'
							? 'Free access converted to forever.'
							: 'Free access ended.';
			void queryClient.invalidateQueries({
				queryKey: ['jafar', 'organizations', organizationId]
			});
		}
	}));

	function submit(action: FreeAccessAction, event: SubmitEvent) {
		event.preventDefault();
		const input = buildInput(action);
		if (input) freeAccessMutation.mutate(input);
	}

	function confirmStepUp() {
		if (pendingStepUpInput) freeAccessMutation.mutate(pendingStepUpInput);
	}
</script>

<div class="free-access-actions">
	{#if !hasPackageAssignment}
		<span class="free-access-actions__notice"
			>Assign a published package version before granting free access</span
		>
	{:else}
		{#if panels.length === 0}
			<p class="free-access-actions__empty">This organization is on paid access.</p>
		{/if}
		<div class="free-access-actions__panels">
			{#each panels as panel (panel.grant.grant_id)}
				<div class="free-access-actions__panel">
					<p class="free-access-actions__panel-label">{panel.label} free access</p>
					<p class="free-access-actions__panel-detail">
						{formatCalendarDate(panel.grant.starts_at)} through {formatCalendarDate(
							panel.grant.access_until_date
						)}
					</p>
					<div class="free-access-actions__panel-buttons">
						<Button
							variant="secondary"
							variation="subtle"
							onclick={() => openActionDialog('extend', panel.grant.grant_id)}>Extend</Button
						>
						{#if panel.grant.access_until_date !== null}
							<Button
								variant="secondary"
								variation="subtle"
								onclick={() => openActionDialog('convert_to_forever', panel.grant.grant_id)}
								>Convert to forever</Button
							>
						{/if}
						<Button
							variant="secondary"
							variation="destructive"
							onclick={() => openActionDialog('end', panel.grant.grant_id)}>End</Button
						>
					</div>
				</div>
			{/each}
		</div>
		{#if canGrant}
			<Button variant="secondary" onclick={openGrantDialog}
				>{freeAccess.active ? 'Schedule future free access' : 'Grant free access'}</Button
			>
		{/if}
	{/if}
	{#if feedbackMessage}<p class="free-access-actions__success" role="status">
			{feedbackMessage}
		</p>{/if}
	{#if feedbackError}<p class="free-access-actions__error" role="alert">{feedbackError}</p>{/if}
</div>

<Dialog
	open={activeAction === 'grant'}
	title={freeAccess.active ? 'Schedule future free access' : 'Grant free access'}
	onClose={closeDialog}
>
	<form class="free-access-actions__form" onsubmit={(event) => submit('grant', event)}>
		<CalendarPicker
			id="free-access-starts-at"
			label="Start date"
			value={calendarDateFromString(startsAt)}
			minValue={todayCalendarDate}
			invalid={Boolean(fieldErrors.starts_at)}
			errorMessage={fieldErrors.starts_at}
			onchange={(value) => (startsAt = calendarDateToString(value))}
		/>
		<CalendarPicker
			id="free-access-until-date"
			label="End date (leave blank for forever)"
			value={calendarDateFromString(untilDate)}
			onchange={(value) => (untilDate = calendarDateToString(value))}
		/>
		<Input
			id="free-access-grant-reason"
			label="Private reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="free-access-actions__dialog-actions">
			<Button type="submit" loading={freeAccessMutation.isPending}>Grant free access</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={activeAction === 'extend'} title="Extend free access" onClose={closeDialog}>
	<form class="free-access-actions__form" onsubmit={(event) => submit('extend', event)}>
		<CalendarPicker
			id="free-access-extend-until"
			label="New end date"
			value={calendarDateFromString(untilDate)}
			invalid={Boolean(fieldErrors.access_until_date)}
			errorMessage={fieldErrors.access_until_date}
			onchange={(value) => (untilDate = calendarDateToString(value))}
		/>
		<Input
			id="free-access-extend-reason"
			label="Private reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="free-access-actions__dialog-actions">
			<Button type="submit" loading={freeAccessMutation.isPending}>Extend free access</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog
	open={activeAction === 'convert_to_forever'}
	title="Convert to forever"
	onClose={closeDialog}
>
	<form class="free-access-actions__form" onsubmit={(event) => submit('convert_to_forever', event)}>
		<p>This removes the end date. Free access will not expire on its own.</p>
		<Input
			id="free-access-convert-reason"
			label="Private reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="free-access-actions__dialog-actions">
			<Button type="submit" loading={freeAccessMutation.isPending}>Convert to forever</Button>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<Dialog open={activeAction === 'end'} title="End free access" onClose={closeDialog}>
	<form class="free-access-actions__form" onsubmit={(event) => submit('end', event)}>
		<Input
			id="free-access-end-reason"
			label="Private reason"
			bind:value={reason}
			invalid={Boolean(fieldErrors.reason)}
			errorMessage={fieldErrors.reason}
		/>
		<div class="free-access-actions__dialog-actions">
			<Button type="submit" variation="destructive" loading={freeAccessMutation.isPending}
				>End free access</Button
			>
			<Button type="button" variant="secondary" variation="subtle" onclick={closeDialog}
				>Cancel</Button
			>
		</div>
	</form>
</Dialog>

<OwnerReconfirmDialog
	bind:open={reconfirmOpen}
	title="Confirm permanent free access"
	description="Granting free access forever requires a recent password reconfirmation."
	confirmLabel="Confirm"
	onConfirm={confirmStepUp}
/>

<style lang="scss">
	.free-access-actions {
		display: grid;
		gap: var(--space-base);
	}
	.free-access-actions__panels {
		display: grid;
		gap: var(--space-small);
	}
	.free-access-actions__panel {
		display: grid;
		gap: var(--space-smaller);
		padding: var(--space-small) var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-small);
	}
	.free-access-actions__panel-label {
		color: var(--color-text);
		font-weight: 600;
	}
	.free-access-actions__panel-detail {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.free-access-actions__panel-buttons {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}
	.free-access-actions__empty {
		color: var(--color-text--secondary);
	}
	.free-access-actions__notice {
		padding: var(--space-small) var(--space-slim);
		border-radius: var(--radius-small);
		color: var(--color-informative--onSurface);
		background: var(--color-informative--surface);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-tighter);
	}
	.free-access-actions__form {
		display: grid;
		gap: var(--space-base);
	}
	.free-access-actions__form > p {
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}
	.free-access-actions__dialog-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.free-access-actions__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.free-access-actions__success {
		color: var(--color-success--onSurface);
	}
</style>
