<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import AuthorMeta from '$lib/components/collaboration/AuthorMeta.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		createOpportunityNote,
		deleteOpportunityNote,
		fetchOpportunityNotes,
		opportunityNotesKey,
		updateOpportunityNote,
		type PipelineNote
	} from '$lib/pipeline/api';
	import { fetchProfiles, profilesKey } from '$lib/collaboration/api';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import pencilPlusIcon from '@tabler/icons/outline/pencil-plus.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// The Brief's Notes block: immediate-save, unlike the staged `NotesPanel` the Request/Client detail
	// pages use. Authorized by pipeline.edit, including for a Client-targeted Note -- see
	// `$lib/server/pipeline/notes.ts` and the `pipeline_*_opportunity_note` database functions. Keyed by
	// `opportunity.id` in the parent, same as `OpportunityTasksSection`, so switching cards resets any open
	// composer or edit row instead of leaking it onto the next card.
	let {
		opportunityId,
		hasClient,
		currentUserId,
		canEdit
	}: {
		opportunityId: string;
		hasClient: boolean;
		currentUserId?: string;
		canEdit: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const notesQuery = createQuery(() => ({
		queryKey: opportunityNotesKey(opportunityId),
		queryFn: () => fetchOpportunityNotes(opportunityId)
	}));
	const notes = $derived(notesQuery.data ?? []);

	const authorIds = $derived([
		...new Set(
			notes
				.flatMap((note) => [note.created_by, note.edited_by])
				.filter((id): id is string => Boolean(id))
		)
	]);
	const profilesQuery = createQuery(() => ({
		queryKey: profilesKey(authorIds),
		queryFn: () => fetchProfiles(authorIds),
		enabled: authorIds.length > 0
	}));
	const profileById = $derived(
		new Map((profilesQuery.data ?? []).map((profile) => [profile.id, profile]))
	);

	function invalidateNotes() {
		return queryClient.invalidateQueries({ queryKey: opportunityNotesKey(opportunityId) });
	}

	// --- Composer -----------------------------------------------------------------------------------------

	let composerOpen = $state(false);
	let newBody = $state('');
	let newTarget = $state<'request' | 'client'>('request');
	const showComposer = $derived(canEdit && (composerOpen || notes.length > 0));

	const targetOptions = $derived(
		hasClient
			? [
					{ value: 'request', label: 'Request' },
					{ value: 'client', label: 'Client' }
				]
			: [{ value: 'request', label: 'Request' }]
	);

	const createMutationState = createMutation(() => ({
		mutationFn: () =>
			createOpportunityNote(opportunityId, { entityType: newTarget, body: newBody.trim() }),
		onSuccess: () => {
			invalidateNotes();
			newBody = '';
			composerOpen = false;
		},
		onError: (error: Error) => toast.error('Could not add the note', error.message)
	}));

	function addNote() {
		if (!newBody.trim()) return;
		createMutationState.mutate();
	}

	// --- Editing an existing note ---------------------------------------------------------------------------

	let editingId = $state<string | null>(null);
	let editBody = $state('');

	function startEdit(note: PipelineNote) {
		editingId = note.id;
		editBody = note.body;
	}

	const updateMutationState = createMutation(() => ({
		mutationFn: (note: PipelineNote) =>
			updateOpportunityNote(opportunityId, note.id, editBody.trim()),
		onSuccess: () => {
			invalidateNotes();
			editingId = null;
		},
		onError: (error: Error) => toast.error('Could not save the note', error.message)
	}));

	function applyEdit(note: PipelineNote) {
		const body = editBody.trim();
		if (!body || body === note.body) {
			editingId = null;
			return;
		}
		updateMutationState.mutate(note);
	}

	// --- Delete -----------------------------------------------------------------------------------------------

	let deletingNote = $state<PipelineNote | null>(null);

	const deleteMutationState = createMutation(() => ({
		mutationFn: (note: PipelineNote) =>
			deleteOpportunityNote(opportunityId, note.id, note.entity_type),
		onSuccess: () => {
			invalidateNotes();
			deletingNote = null;
		},
		onError: (error: Error) => {
			toast.error('Could not delete the note', error.message);
			deletingNote = null;
		}
	}));

	function menuItems(note: PipelineNote) {
		return [
			{ label: 'Edit', icon: pencilIcon, onSelect: () => startEdit(note) },
			{ label: 'Delete', icon: trashIcon, destructive: true, onSelect: () => (deletingNote = note) }
		];
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<section class="brief-notes" aria-labelledby="brief-notes-heading">
	<div class="brief-notes__header">
		<h3 id="brief-notes-heading" class="brief-notes__heading">Notes</h3>
		{#if canEdit && !composerOpen && notes.length > 0}
			<Button size="small" variant="tertiary" onclick={() => (composerOpen = true)}
				>+ Add note</Button
			>
		{/if}
	</div>

	{#if showComposer}
		<div class="brief-notes__composer">
			{#if targetOptions.length > 1}
				<SegmentedControl
					label="Target"
					size="small"
					options={targetOptions}
					bind:value={newTarget}
				/>
			{/if}
			<Textarea
				id={`opportunity-note-composer-${opportunityId}`}
				label="Add a note"
				bind:value={newBody}
				maxlength={4000}
				rows={3}
			/>
			<div class="brief-notes__composer-actions">
				<Button
					size="small"
					disabled={!newBody.trim() || createMutationState.isPending}
					onclick={addNote}
				>
					Add note
				</Button>
			</div>
		</div>
	{/if}

	{#if notesQuery.isPending}
		<p class="brief-notes__state">Loading notes…</p>
	{:else if notesQuery.isError}
		<p class="brief-notes__state brief-notes__state--error">The notes could not be loaded.</p>
	{:else if notes.length === 0 && !showComposer}
		<EmptyState
			title="No notes yet"
			description="Notes you add here also show on the Request and Client."
			icon={canEdit ? pencilPlusIcon : notesIcon}
			iconLabel={canEdit ? 'Add a note' : undefined}
			onIconClick={canEdit ? () => (composerOpen = true) : undefined}
		/>
	{:else}
		<ul class="brief-notes__list">
			{#each notes as note (note.id)}
				<li class="brief-notes__item">
					<div class="brief-notes__item-header">
						<AuthorMeta
							userId={note.created_by}
							profile={note.created_by ? profileById.get(note.created_by) : undefined}
							{currentUserId}
							timestamp={note.created_at}
							suffix={note.edited_at ? 'edited' : undefined}
						/>
						<div class="brief-notes__item-actions">
							<Badge size="small">{note.entity_type === 'client' ? 'Client' : 'Request'}</Badge>
							{#if canEdit}
								<DropdownMenu items={menuItems(note)} triggerLabel="Note actions" />
							{/if}
						</div>
					</div>

					{#if editingId === note.id}
						<div class="brief-notes__edit">
							<Textarea
								id={`opportunity-note-edit-${note.id}`}
								bind:value={editBody}
								maxlength={4000}
								rows={3}
							/>
							<div class="brief-notes__edit-actions">
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									onclick={() => (editingId = null)}
								>
									Cancel
								</Button>
								<Button
									size="small"
									disabled={!editBody.trim() || updateMutationState.isPending}
									onclick={() => applyEdit(note)}
								>
									Done
								</Button>
							</div>
						</div>
					{:else}
						<p class="brief-notes__body">{note.body}</p>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</section>

{#if deletingNote}
	{@const note = deletingNote}
	<ConfirmDialog
		open
		title="Delete this note?"
		tone="critical"
		confirmLabel="Delete note"
		destructive
		loading={deleteMutationState.isPending}
		onConfirm={() => deleteMutationState.mutate(note)}
		onClose={() => (deletingNote = null)}
	>
		<p>This note will be removed. This cannot be undone.</p>
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.brief-notes {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__header {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-base);
		}

		&__heading {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			text-transform: uppercase;
			letter-spacing: 0.04em;
		}

		&__composer {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__composer-actions {
			display: flex;
			justify-content: flex-end;
		}

		&__state {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			&--error {
				color: var(--color-critical);
			}
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__item-header {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__item-actions {
			display: flex;
			flex: 0 0 auto;
			align-items: center;
			gap: var(--space-smaller);
		}

		&__body {
			margin-top: var(--space-small);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			line-height: var(--typography--lineHeight-large);
			white-space: pre-wrap;
			overflow-wrap: anywhere;
		}

		&__edit {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}

		&__edit-actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
