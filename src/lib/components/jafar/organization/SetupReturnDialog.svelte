<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import type { SetupCheckItem } from '$lib/setup/check';
	import { SETUP_REVIEW_NOTE_MAX } from '$lib/setup/review';

	// Client onboarding C3 (plan §4; Content Snare's "send back with a reason"): Jafar sends one task back to
	// the client, saying what to change and ticking the questions to change. The client sees the note at the
	// top of that task and the ticked questions highlighted; every other task keeps its decision.
	let {
		sectionTitle,
		items,
		initialNote = '',
		initialKeys = [],
		pending,
		error,
		onSubmit,
		onClose
	}: {
		sectionTitle: string;
		items: Pick<SetupCheckItem, 'key' | 'label'>[];
		/** What was sent back before, when changing an earlier return. */
		initialNote?: string;
		initialKeys?: string[];
		pending: boolean;
		error: string;
		onSubmit: (input: { note: string; question_keys: string[] }) => void;
		onClose: () => void;
	} = $props();

	const uid = $props.id();
	// The dialog opens fresh each time, so the starting values are read once.
	// svelte-ignore state_referenced_locally
	let note = $state(initialNote);
	// svelte-ignore state_referenced_locally
	let ticked = $state<string[]>([...initialKeys]);
	let noteError = $state('');

	function toggle(key: string, on: boolean) {
		ticked = on ? [...ticked, key] : ticked.filter((item) => item !== key);
	}

	function submit(event: SubmitEvent) {
		event.preventDefault();
		if (!note.trim()) {
			noteError = 'Say what the client should change.';
			return;
		}
		noteError = '';
		// In the task's own order.
		onSubmit({
			note: note.trim(),
			question_keys: items.map((item) => item.key).filter((key) => ticked.includes(key))
		});
	}
</script>

<Dialog open title={`Send back “${sectionTitle}”`} initialFocusId={`${uid}-note`} {onClose}>
	<form class="return-dialog" onsubmit={submit} novalidate>
		<p class="return-dialog__lead">
			The client is asked to change this task and send it again. Your other decisions stay as they
			are.
		</p>
		<Textarea
			id={`${uid}-note`}
			label="What should they change?"
			rows={4}
			maxlength={SETUP_REVIEW_NOTE_MAX}
			required
			bind:value={note}
			invalid={Boolean(noteError)}
			errorMessage={noteError}
		/>
		{#if items.length > 0}
			<fieldset class="return-dialog__questions">
				<legend
					>Questions to change <span>(optional — they are highlighted for the client)</span></legend
				>
				{#each items as item (item.key)}
					<Checkbox
						id={`${uid}-${item.key}`}
						label={item.label}
						checked={ticked.includes(item.key)}
						onchange={(on) => toggle(item.key, on)}
					/>
				{/each}
			</fieldset>
		{/if}
		{#if error}
			<p class="return-dialog__error" role="alert">{error}</p>
		{/if}
		<div class="return-dialog__actions">
			<Button type="button" variant="secondary" variation="subtle" onclick={onClose}>Cancel</Button>
			<Button type="submit" loading={pending}>Send back</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.return-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__lead {
			margin: 0;
			color: var(--color-text--secondary);
		}

		&__questions {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			max-height: 280px;
			margin: 0;
			padding: 0;
			overflow-y: auto;
			border: 0;

			legend {
				margin-bottom: var(--space-small);
				padding: 0;
				color: var(--color-heading);
				font-weight: 700;

				span {
					color: var(--color-text--secondary);
					font-size: var(--typography--fontSize-small);
					font-weight: 400;
				}
			}
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
