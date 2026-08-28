<script lang="ts">
	import { untrack } from 'svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import {
		createCommunicationSnippet,
		updateCommunicationSnippet,
		SnippetWriteError,
		type CommunicationSnippet
	} from '$lib/communications/snippets';

	// Adds a reusable snippet, or updates one. No revision protection: a snippet is a low-stakes reusable
	// draft, not a document two people are racing to edit, so the last save simply wins -- the same
	// proportionate choice the picker's own unmanaged catalog write makes.
	let {
		open,
		mode = 'create',
		snippet = null,
		existingFolders = [],
		onSaved,
		onClose
	}: {
		open: boolean;
		mode?: 'create' | 'update';
		/** The snippet being edited. Required in `update` mode. */
		snippet?: CommunicationSnippet | null;
		/** Folder names already in use, offered as suggestions so a person reuses a folder instead of
		 * accidentally forking it with a typo. */
		existingFolders?: string[];
		onSaved: (snippet: CommunicationSnippet) => void;
		onClose: () => void;
	} = $props();

	let folder = $state(untrack(() => snippet?.folder ?? ''));
	let title = $state(untrack(() => snippet?.title ?? ''));
	let body = $state(untrack(() => snippet?.body ?? ''));
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const dialogTitle = $derived(mode === 'update' ? 'Edit snippet' : 'New snippet');

	async function submit() {
		if (saving) return;
		formError = '';
		fieldErrors = {};
		if (!title.trim()) {
			fieldErrors = { title: 'Give this snippet a title.' };
			return;
		}
		if (!body.trim()) {
			fieldErrors = { body: 'Enter the snippet text.' };
			return;
		}
		saving = true;
		try {
			const draft = { folder: folder.trim() || null, title: title.trim(), body: body.trim() };
			const result =
				mode === 'update' && snippet
					? await updateCommunicationSnippet(snippet.id, draft)
					: await createCommunicationSnippet(draft);
			onSaved(result);
		} catch (cause) {
			if (cause instanceof SnippetWriteError) {
				fieldErrors = cause.fieldErrors;
				formError = Object.keys(fieldErrors).length ? '' : cause.message;
			} else {
				formError = 'That snippet could not be saved.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog {open} title={dialogTitle} {onClose}>
	<div class="snippet-dialog">
		{#if formError}<p class="snippet-dialog__error" role="alert">{formError}</p>{/if}

		<Input
			id="snippet-folder"
			label="Folder (optional)"
			placeholder="e.g. Follow-ups"
			disabled={saving}
			bind:value={folder}
			list="snippet-folder-options"
		/>
		<datalist id="snippet-folder-options">
			{#each existingFolders as name (name)}<option value={name}></option>{/each}
		</datalist>

		<Input
			id="snippet-title"
			label="Title"
			required
			disabled={saving}
			bind:value={title}
			invalid={Boolean(fieldErrors.title)}
			errorMessage={fieldErrors.title ?? ''}
			maxlength={120}
		/>

		<Textarea
			id="snippet-body"
			label="Text"
			required
			rows={5}
			maxlength={4000}
			disabled={saving}
			bind:value={body}
			invalid={Boolean(fieldErrors.body)}
			errorMessage={fieldErrors.body ?? ''}
		/>

		<div class="snippet-dialog__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button variant="primary" loading={saving} onclick={submit}>
				{mode === 'update' ? 'Save changes' : 'Create snippet'}
			</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.snippet-dialog {
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

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			padding-top: var(--space-small);
		}
	}
</style>
