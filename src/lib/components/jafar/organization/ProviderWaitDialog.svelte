<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		PROVIDER_WAIT_NOTE_MAX,
		PROVIDER_WAIT_STATUSES,
		PROVIDER_WAIT_TITLE,
		providerWaitOwnerLabel,
		type ProviderWait,
		type ProviderWaitKey,
		type ProviderWaitStatus
	} from '$lib/setup/provider-waits';

	// Client onboarding E2 (plan §5): Jafar moves one outside wait to a stage, with an optional note the client
	// reads under the badge. "They need to do something" needs the note and emails the client; "Not started"
	// hides the wait from the client again.
	let {
		waitKey,
		current,
		pending,
		error,
		onSubmit,
		onClose
	}: {
		waitKey: ProviderWaitKey;
		current: ProviderWait | null;
		pending: boolean;
		error: string;
		onSubmit: (input: { status: ProviderWaitStatus | null; note: string | null }) => void;
		onClose: () => void;
	} = $props();

	const uid = $props.id();
	const NOT_STARTED = 'not_started';
	// The dialog opens fresh each time, so the starting values are read once.
	// svelte-ignore state_referenced_locally
	let status = $state<string>(current?.status ?? 'waiting_for_access');
	// svelte-ignore state_referenced_locally
	let note = $state(current?.note ?? '');
	let noteError = $state('');

	const options = $derived([
		{ value: NOT_STARTED, label: 'Not started — hidden from the client' },
		...PROVIDER_WAIT_STATUSES.map((value) => ({
			value,
			label: providerWaitOwnerLabel(waitKey, value)
		}))
	]);
	const needsNote = $derived(status === 'action_needed');

	function submit(event: SubmitEvent) {
		event.preventDefault();
		if (needsNote && !note.trim()) {
			noteError = 'Say what the client needs to do.';
			return;
		}
		noteError = '';
		onSubmit({
			status: status === NOT_STARTED ? null : (status as ProviderWaitStatus),
			note: status === NOT_STARTED ? null : note.trim() || null
		});
	}
</script>

<Dialog open title={PROVIDER_WAIT_TITLE[waitKey]} initialFocusId={`${uid}-status`} {onClose}>
	<form class="wait-dialog" onsubmit={submit} novalidate>
		<p class="wait-dialog__lead">
			The client sees this stage and your note under their project. It never changes Uplift's dates.
		</p>
		<Select id={`${uid}-status`} label="Where it stands" {options} bind:value={status} />
		{#if status !== NOT_STARTED}
			<Textarea
				id={`${uid}-note`}
				label={needsNote ? 'What do they need to do?' : 'Note for the client (optional)'}
				rows={3}
				maxlength={PROVIDER_WAIT_NOTE_MAX}
				required={needsNote}
				bind:value={note}
				invalid={Boolean(noteError) && !note.trim()}
				errorMessage={note.trim() ? '' : noteError}
			/>
		{/if}
		{#if needsNote}
			<p class="wait-dialog__hint">
				The business owner and administrators are emailed this note with a link to their Setup page.
			</p>
		{/if}
		{#if error}
			<p class="wait-dialog__error" role="alert">{error}</p>
		{/if}
		<div class="wait-dialog__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending}>Save</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.wait-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__lead,
		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__hint {
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical--onSurface);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}
	}
</style>
