<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SetupField from '$lib/components/setup/SetupField.svelte';
	import { SETUP_HELP_NOTE_MAX, type SetupHelpItem } from '$lib/setup/help';

	// Client onboarding C3c (plan §4; Jafar, 2026-10-04): Jafar records the answer Uplift found for a question the
	// client asked help with — in the same kind of box the client had, or a written note for photos, files and
	// lists. The client's own "I need Uplift's help" is kept; they see Uplift's answer beside it.
	let {
		item,
		country,
		currency,
		pending,
		error,
		onSubmit,
		onClose
	}: {
		item: SetupHelpItem;
		country: string | null;
		currency: string | null;
		pending: boolean;
		/** The server's refusal, for the box or the note. */
		error: string;
		onSubmit: (input: { value: string | null; note: string | null }) => void;
		onClose: () => void;
	} = $props();

	const uid = $props.id();
	// Uplift's box never offers "I don't have this yet" or "I need Uplift's help".
	const fact = $derived({ ...item.fact, canDefer: false });
	// The dialog opens fresh each time, so the starting values are read once.
	// svelte-ignore state_referenced_locally
	let value = $state(item.answer?.value ?? '');
	// svelte-ignore state_referenced_locally
	let note = $state(item.answer?.note ?? '');
	let missing = $state('');

	function submit(event: SubmitEvent) {
		event.preventDefault();
		if (item.form === 'note' ? !note.trim() : !value.trim()) {
			missing = item.form === 'note' ? 'Write what Uplift found or did.' : 'Enter an answer.';
			return;
		}
		missing = '';
		onSubmit(
			item.form === 'note'
				? { value: null, note: note.trim() }
				: { value: value.trim(), note: null }
		);
	}
</script>

<Dialog
	open
	title={item.answer ? 'Change Uplift’s answer' : 'Add Uplift’s answer'}
	initialFocusId={item.form === 'note' ? `${uid}-note` : undefined}
	{onClose}
>
	<form class="help-dialog" onsubmit={submit} novalidate>
		<div class="help-dialog__asked">
			<span class="help-dialog__where">{item.section_title}</span>
			<span class="help-dialog__question">{item.label}</span>
			{#if item.client_note}
				<span class="help-dialog__client">The client wrote: “{item.client_note}”</span>
			{/if}
		</div>
		{#if item.form === 'note'}
			<Textarea
				id={`${uid}-note`}
				label="What Uplift found or did"
				rows={4}
				maxlength={SETUP_HELP_NOTE_MAX}
				required
				bind:value={note}
				invalid={Boolean(missing || error) && !pending}
				errorMessage={missing || error}
			/>
			<p class="help-dialog__lead">
				For example: “Took the logo from their Facebook page and saved it in the project folder.”
			</p>
		{:else}
			<SetupField
				{fact}
				bind:value
				error={missing || error}
				{country}
				{currency}
				onedit={() => (missing = '')}
				oncommit={() => {}}
			/>
		{/if}
		<p class="help-dialog__lead">
			The client sees this under the question as “Uplift filled this in”.
		</p>
		<div class="help-dialog__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending}>Save answer</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.help-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__asked {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			overflow-wrap: anywhere;
		}

		&__where,
		&__client,
		&__lead {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__question {
			color: var(--color-heading);
			font-weight: 700;
		}

		&__lead {
			margin: 0;
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}
	}
</style>
