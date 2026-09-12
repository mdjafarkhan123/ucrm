<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import { createForm, type FormCreateResult } from '$lib/forms/api';
	import { FORM_OUTCOME_HINTS, FORM_OUTCOME_LABELS } from '$lib/forms/labels';
	import {
		FORM_DESCRIPTION_MAX,
		FORM_NAME_MAX,
		FORM_OUTCOMES,
		FORM_TITLE_MAX,
		type FormOutcome
	} from '$lib/forms/types';

	// A new form of any of the three outcomes — a reviewed request, a self-booked assessment, or a straight
	// job booking (Part 4B-2c added the latter two once their booking rules and builder screens existed).
	// It creates the form (seeded with a usable default builder, and booking rules for the two booking
	// outcomes) and hands the new id back so the list page can open the builder straight away.
	let {
		open,
		onCreated,
		onClose
	}: {
		open: boolean;
		onCreated: (result: FormCreateResult) => void;
		onClose: () => void;
	} = $props();

	const outcomeOptions = FORM_OUTCOMES.map((value) => ({
		value,
		label: FORM_OUTCOME_LABELS[value]
	}));

	let outcome = $state<FormOutcome>('request');
	let name = $state('');
	let title = $state('');
	let description = $state('');
	let saving = $state(false);
	let error = $state('');

	$effect(() => {
		if (!open) return;
		outcome = 'request';
		name = '';
		title = '';
		description = '';
		error = '';
	});

	async function create() {
		if (saving) return;
		error = '';
		if (!name.trim()) {
			error = 'Give this form a name so you can find it later.';
			return;
		}
		if (!title.trim()) {
			error = 'Give this form a title your customers will see.';
			return;
		}
		saving = true;
		try {
			const result = await createForm({
				outcome,
				name: name.trim(),
				title: title.trim(),
				description: description.trim() || undefined
			});
			onCreated(result);
		} catch (caught) {
			error = caught instanceof Error ? caught.message : 'That form could not be created.';
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	{open}
	title={`New ${FORM_OUTCOME_LABELS[outcome].toLowerCase()}`}
	onClose={saving ? () => {} : onClose}
>
	<div class="form-create">
		{#if error}<p class="form-create__error" role="alert">{error}</p>{/if}

		<div class="form-create__field-group">
			<SegmentedControl
				label="What does this form do?"
				options={outcomeOptions}
				bind:value={outcome}
				fullWidth
			/>
			<p class="form-create__hint">{FORM_OUTCOME_HINTS[outcome]}</p>
		</div>

		<Input
			id="new-form-name"
			label="Form name (only your team sees this)"
			bind:value={name}
			required
			maxlength={FORM_NAME_MAX}
			placeholder="Website request form"
		/>
		<Input
			id="new-form-title"
			label="Title customers see"
			bind:value={title}
			required
			maxlength={FORM_TITLE_MAX}
			placeholder="Request a quote"
		/>
		<Textarea
			id="new-form-description"
			label="Short description (optional)"
			bind:value={description}
			rows={3}
			maxlength={FORM_DESCRIPTION_MAX}
			showCount
		/>

		<div class="form-create__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button onclick={() => void create()} loading={saving}>Create form</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.form-create {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}

		&__field-group {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
