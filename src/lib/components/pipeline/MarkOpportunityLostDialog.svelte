<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import {
		markOpportunityLost,
		OutcomeWriteError,
		LOST_REASONS,
		type LostReason,
		type OutcomeCommandResult
	} from '$lib/pipeline/api';

	// The card's `Mark as lost` action. Owns its own write, the same way `TaskDialog` does — there is no
	// page draft to stage into, so Save writes straight away and the caller only has to react to the
	// result.
	let {
		open,
		opportunityId,
		onSaved,
		onClose
	}: {
		open: boolean;
		opportunityId: string;
		onSaved: (result: OutcomeCommandResult) => void;
		onClose: () => void;
	} = $props();

	const reasonOptions = [
		{ value: '', label: 'No reason selected' },
		...LOST_REASONS.map((reason) => ({ value: reason.value, label: reason.label }))
	];

	let reason = $state('');
	let note = $state('');
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	// Minted once per open, not per submit — a retried submit after a dropped response carries the same
	// key, so the server recognises it as a repeat instead of a second Lost event.
	let idempotencyKey = crypto.randomUUID();

	const noteRequired = $derived(reason === 'other');

	async function save() {
		if (saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		try {
			const result = await markOpportunityLost(opportunityId, {
				idempotencyKey,
				reason: (reason || null) as LostReason | null,
				note: note.trim() || null
			});
			onSaved(result);
		} catch (thrown) {
			if (thrown instanceof OutcomeWriteError) {
				fieldErrors = thrown.fieldErrors;
				formError =
					fieldErrors.form ?? (Object.keys(fieldErrors).length === 0 ? thrown.message : '');
			} else {
				formError =
					thrown instanceof Error ? thrown.message : 'That opportunity could not be marked lost.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Mark as lost" onClose={saving ? () => {} : onClose}>
	<div class="lost-dialog">
		<p class="lost-dialog__notice">
			This request will leave the board, be archived, and its open tasks will be marked complete.
		</p>

		<div class="lost-dialog__field">
			<label class="lost-dialog__label" for="lost-dialog-reason">Reason (optional)</label>
			<Select id="lost-dialog-reason" bind:value={reason} options={reasonOptions} />
		</div>

		<Textarea
			id="lost-dialog-note"
			label={noteRequired ? 'Note (required for "Other")' : 'Note (optional)'}
			rows={3}
			maxlength={1000}
			bind:value={note}
			invalid={Boolean(fieldErrors.note)}
			errorMessage={fieldErrors.note}
		/>

		{#if formError}<p class="lost-dialog__error" role="alert">{formError}</p>{/if}

		<div class="lost-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button
				variant="primary"
				variation="destructive"
				disabled={noteRequired && note.trim().length === 0}
				loading={saving}
				onclick={() => void save()}
			>
				Mark as lost
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.lost-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__notice {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}
		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}
		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
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
