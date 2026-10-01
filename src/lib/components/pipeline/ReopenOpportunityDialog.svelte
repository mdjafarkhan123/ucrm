<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		reopenOpportunity,
		OutcomeWriteError,
		type OutcomeCommandResult
	} from '$lib/pipeline/api';

	// A Lost row's only Reopen entry point (Sales Outcomes report). Owns its own write, the same shape
	// `MarkOpportunityLostDialog` uses -- there is no page draft to stage into, so Save writes straight away.
	let {
		open,
		opportunityId,
		subject = 'request',
		onSaved,
		onClose
	}: {
		open: boolean;
		opportunityId: string;
		// What the Lost record stands for, so the notice says what really comes back.
		subject?: 'request' | 'quote';
		onSaved: (result: OutcomeCommandResult) => void;
		onClose: () => void;
	} = $props();

	let explanation = $state('');
	let saving = $state(false);
	const toast = getToastManager();
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	// Minted once per open, not per submit -- a retried submit after a dropped response carries the same
	// key, so the server recognises it as a repeat instead of a second Reopened event.
	let idempotencyKey = crypto.randomUUID();

	async function save() {
		if (saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		try {
			const result = await reopenOpportunity(opportunityId, {
				idempotencyKey,
				reopenExplanation: explanation.trim()
			});
			toast.success('Opportunity reopened');
			onSaved(result);
		} catch (thrown) {
			if (thrown instanceof OutcomeWriteError) {
				fieldErrors = thrown.fieldErrors;
				formError =
					fieldErrors.form ?? (Object.keys(fieldErrors).length === 0 ? thrown.message : '');
			} else {
				formError =
					thrown instanceof Error ? thrown.message : 'That opportunity could not be reopened.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Reopen opportunity" onClose={saving ? () => {} : onClose}>
	<div class="reopen-dialog">
		<p class="reopen-dialog__notice">
			{#if subject === 'quote'}
				This puts the quote back where it stood before it was lost and returns its card to the
				board. A customer's decline is cleared; it stays in the quote's history. Tasks removed when
				it was lost do not come back.
			{:else}
				This restores the request to the board and reopens the tasks that closing it completed
				automatically. Tasks someone finished by hand stay completed.
			{/if}
		</p>

		<Textarea
			id="reopen-dialog-explanation"
			label="Why is this reopening?"
			rows={3}
			maxlength={500}
			bind:value={explanation}
			invalid={Boolean(fieldErrors.reopen_explanation)}
			errorMessage={fieldErrors.reopen_explanation}
		/>

		{#if formError}<p class="reopen-dialog__error" role="alert">{formError}</p>{/if}

		<div class="reopen-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button
				variant="primary"
				disabled={explanation.trim().length === 0}
				loading={saving}
				onclick={() => void save()}
			>
				Reopen
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.reopen-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__notice {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
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
