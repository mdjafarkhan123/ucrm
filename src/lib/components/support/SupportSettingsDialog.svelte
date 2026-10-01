<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import { saveSupportSettings, type SupportSettings } from '$lib/support/api';

	// How Uplift appears in the messenger. Both answers are shown to contractors exactly as written, so the
	// hours line is only ever what Jafar has actually promised — left empty, the messenger promises nothing.
	let {
		settings,
		onClose,
		onSaved
	}: {
		settings: SupportSettings;
		onClose: () => void;
		onSaved: (settings: SupportSettings) => void;
	} = $props();

	// The dialog is created when it opens, so it starts from what is saved at that moment.
	// svelte-ignore state_referenced_locally
	let responderName = $state(settings.responder_name);
	// svelte-ignore state_referenced_locally
	let availabilityNote = $state(settings.availability_note);
	let pending = $state(false);
	let formError = $state('');

	const nameMissing = $derived(responderName.trim() === '');

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (nameMissing) return;
		pending = true;
		formError = '';
		try {
			onSaved(
				await saveSupportSettings({
					responder_name: responderName.trim(),
					availability_note: availabilityNote.trim()
				})
			);
		} catch (error) {
			formError = error instanceof Error ? error.message : 'Support settings could not be saved.';
		} finally {
			pending = false;
		}
	}
</script>

<Dialog open title="Support settings" initialFocusId="support-settings-name" {onClose}>
	<form class="support-settings" onsubmit={submit}>
		<div class="support-settings__field">
			<Input
				id="support-settings-name"
				label="Your name on replies"
				required
				maxlength={80}
				bind:value={responderName}
			/>
			<p class="support-settings__hint">
				Clients see each reply as “Uplift Support · {responderName.trim() || 'your name'}”.
			</p>
		</div>
		<div class="support-settings__field">
			<Input
				id="support-settings-hours"
				label="Support hours and usual reply time"
				maxlength={160}
				bind:value={availabilityNote}
			/>
			<p class="support-settings__hint">
				Shown under “Uplift Support” in the chat, word for word — only write what you can keep to.
				Leave it empty and clients read “We reply here as soon as we can.”
			</p>
		</div>
		{#if formError}<p class="support-settings__error" role="alert">{formError}</p>{/if}
		<div class="support-settings__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending} disabled={nameMissing}>Save</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.support-settings {
		display: grid;
		gap: var(--space-base);

		&__field {
			display: grid;
			gap: var(--space-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
