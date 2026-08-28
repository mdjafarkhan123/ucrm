<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		createCommunicationEmailTemplate,
		updateCommunicationEmailTemplate,
		EmailTemplateWriteError,
		type CommunicationEmailTemplate
	} from '$lib/communications/email-templates';

	// Adds an organization-written template, or edits one (including a copied one -- editing never touches
	// its source link, only the dedicated "Adopt update" action does that). No revision protection: the
	// same proportionate choice as SnippetDialog, since the last save simply wins.
	let {
		open,
		mode = 'create',
		template = null,
		existingFolders = [],
		onSaved,
		onClose
	}: {
		open: boolean;
		mode?: 'create' | 'update';
		/** The template being edited. Required in `update` mode. */
		template?: CommunicationEmailTemplate | null;
		existingFolders?: string[];
		onSaved: (template: CommunicationEmailTemplate) => void;
		onClose: () => void;
	} = $props();

	let folder = $state(untrack(() => template?.folder ?? ''));
	let name = $state(untrack(() => template?.name ?? ''));
	let subject = $state(untrack(() => template?.subject ?? ''));
	let body = $state(untrack(() => template?.body ?? ''));
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const dialogTitle = $derived(mode === 'update' ? 'Edit template' : 'New template');
	const wasCopied = $derived(mode === 'update' && Boolean(template?.source_template_id));

	async function submit() {
		if (saving) return;
		formError = '';
		fieldErrors = {};
		if (!name.trim()) {
			fieldErrors = { name: 'Give this template a name.' };
			return;
		}
		if (!subject.trim()) {
			fieldErrors = { subject: 'Enter a subject line.' };
			return;
		}
		if (!body.trim()) {
			fieldErrors = { body: 'Enter the template body.' };
			return;
		}
		saving = true;
		try {
			const draft = {
				folder: folder.trim() || null,
				name: name.trim(),
				subject: subject.trim(),
				body: body.trim()
			};
			const result =
				mode === 'update' && template
					? await updateCommunicationEmailTemplate(template.id, draft)
					: await createCommunicationEmailTemplate(draft);
			onSaved(result);
		} catch (cause) {
			if (cause instanceof EmailTemplateWriteError) {
				fieldErrors = cause.fieldErrors;
				formError = Object.keys(fieldErrors).length ? '' : cause.message;
			} else {
				formError = 'That email template could not be saved.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title={dialogTitle} {onClose}>
	<div class="email-template-dialog">
		{#if formError}<p class="email-template-dialog__error" role="alert">{formError}</p>{/if}
		{#if wasCopied}
			<p class="email-template-dialog__hint">
				Copied from the platform library. Editing it here only changes your copy.
			</p>
		{/if}

		<Input
			id="email-template-folder"
			label="Folder (optional)"
			placeholder="e.g. Follow-ups"
			disabled={saving}
			bind:value={folder}
			list="email-template-folder-options"
		/>
		<datalist id="email-template-folder-options">
			{#each existingFolders as folderName (folderName)}<option value={folderName}></option>{/each}
		</datalist>

		<Input
			id="email-template-name"
			label="Name"
			required
			disabled={saving}
			bind:value={name}
			invalid={Boolean(fieldErrors.name)}
			errorMessage={fieldErrors.name ?? ''}
			maxlength={120}
		/>

		<Input
			id="email-template-subject"
			label="Subject"
			required
			disabled={saving}
			bind:value={subject}
			invalid={Boolean(fieldErrors.subject)}
			errorMessage={fieldErrors.subject ?? ''}
			maxlength={300}
		/>

		<Textarea
			id="email-template-body"
			label="Body"
			required
			rows={10}
			maxlength={50000}
			disabled={saving}
			bind:value={body}
			invalid={Boolean(fieldErrors.body)}
			errorMessage={fieldErrors.body ?? ''}
		/>

		<div class="email-template-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={submit}>
				{mode === 'update' ? 'Save changes' : 'Create template'}
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.email-template-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--active);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}
	}
</style>
