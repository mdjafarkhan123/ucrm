<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { DragWriteError } from '$lib/pipeline/api';

	// Converting a Request to a Quote is a designed boundary, not a side effect of a drop: a Quote now
	// exists and the Request becomes `converted`, which is terminal -- there is no Undo to offer afterwards.
	// So the drop confirms first, naming exactly what is about to happen, the same way `MarkOpportunityLostDialog`
	// confirms its own irreversible action. The caller owns the actual write and passes back whatever error
	// it throws.
	let {
		open,
		clientName,
		requestTitle,
		onConfirm,
		onClose
	}: {
		open: boolean;
		clientName: string;
		requestTitle: string;
		onConfirm: () => Promise<void>;
		onClose: () => void;
	} = $props();

	let saving = $state(false);
	let formError = $state('');

	async function confirm() {
		if (saving) return;
		saving = true;
		formError = '';
		try {
			await onConfirm();
		} catch (thrown) {
			if (thrown instanceof DragWriteError) {
				formError = thrown.fieldErrors.form ?? thrown.message;
			} else {
				formError =
					thrown instanceof Error ? thrown.message : 'That request could not be converted.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title="Convert to quote" onClose={saving ? () => {} : onClose}>
	<div class="convert-dialog">
		<p class="convert-dialog__notice">
			This creates a quote for <strong>{clientName}</strong> from "{requestTitle}". The request will
			be marked converted, which cannot be undone.
		</p>

		{#if formError}<p class="convert-dialog__error" role="alert">{formError}</p>{/if}

		<div class="convert-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={() => void confirm()}>Convert</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.convert-dialog {
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
