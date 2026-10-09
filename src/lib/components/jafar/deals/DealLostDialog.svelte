<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { DEAL_NOTE_MAX, LOST_REASONS, LOST_REASON_LABELS, refreshDeals } from '$lib/jafar/deals';

	// Jafar business management B4: mark a Deal Lost. A reason from the fixed list (B4 Q5) and an optional note.
	// The Deal leaves the board, keeps its history, and can be reopened.
	let {
		dealId,
		relationshipId,
		businessName,
		onDone,
		onClose
	}: {
		dealId: string;
		relationshipId: string;
		businessName: string;
		onDone?: () => void;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let reason = $state('');
	let note = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);

	const options = LOST_REASONS.map((value) => ({ value, label: LOST_REASON_LABELS[value] }));

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (saving) return;
		formError = '';
		fieldErrors = reason ? {} : { reason: 'Choose why the Deal was lost.' };
		if (!reason) return;

		saving = true;
		const result = await sendLeadWrite(
			`/api/jafar/deals/${encodeURIComponent(dealId)}/lost`,
			'POST',
			{ reason, note: note.trim() || null }
		);
		saving = false;
		if (!result.ok) {
			fieldErrors = result.fieldErrors;
			formError = result.error;
			return;
		}
		await refreshDeals(queryClient, relationshipId);
		toast.success('Marked as Lost');
		onDone?.();
		onClose();
	}
</script>

<Dialog open={true} title="Mark as Lost" size="small" {onClose}>
	<form class="deal-lost" onsubmit={submit} novalidate>
		<p class="deal-lost__lead">
			{businessName} leaves the board. Its history stays, and you can reopen it if they come back.
		</p>

		<div class="deal-lost__field">
			<Select
				id="deal-lost-reason"
				label="Why was it lost?"
				placeholder="Choose a reason"
				required
				{options}
				bind:value={reason}
			/>
			{#if fieldErrors.reason}
				<p class="deal-lost__error" role="alert">{fieldErrors.reason}</p>
			{/if}
		</div>

		<Textarea
			id="deal-lost-note"
			label="Note (optional)"
			rows={3}
			maxlength={DEAL_NOTE_MAX}
			placeholder="e.g. Went with a local agency at $80/mo"
			invalid={Boolean(fieldErrors.note)}
			errorMessage={fieldErrors.note ?? ''}
			bind:value={note}
		/>

		{#if formError && !fieldErrors.reason && !fieldErrors.note}
			<p class="deal-lost__error" role="alert">{formError}</p>
		{/if}

		<div class="deal-lost__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button type="submit" variant="primary" variation="destructive" loading={saving}
				>Mark as Lost</Button
			>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.deal-lost {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__lead {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
