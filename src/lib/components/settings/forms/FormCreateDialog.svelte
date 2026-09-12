<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { createForm, type FormCreateResult } from '$lib/forms/api';
	import { FORM_DESCRIPTION_MAX, FORM_NAME_MAX, FORM_TITLE_MAX } from '$lib/forms/types';

	// New request form. Outcome is fixed to `request` for this stage — booking forms (assessment/job) arrive
	// with their scheduling rules in 4B-2. It creates the form (seeded with a usable default builder) and
	// hands the new id back so the list page can open the builder straight away.
	let {
		open,
		onCreated,
		onClose
	}: {
		open: boolean;
		onCreated: (result: FormCreateResult) => void;
		onClose: () => void;
	} = $props();

	let name = $state('');
	let title = $state('');
	let description = $state('');
	let saving = $state(false);
	let error = $state('');

	$effect(() => {
		if (!open) return;
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
				outcome: 'request',
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

<Dialog {open} title="New request form" onClose={saving ? () => {} : onClose}>
	<div class="form-create">
		{#if error}<p class="form-create__error" role="alert">{error}</p>{/if}

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

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
