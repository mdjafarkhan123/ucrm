<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import AuthorMeta from '$lib/components/collaboration/AuthorMeta.svelte';
	import NoteBody from '$lib/components/collaboration/NoteBody.svelte';
	import NoteFiles from '$lib/components/collaboration/NoteFiles.svelte';
	import MentionTextarea from './MentionTextarea.svelte';
	import NoteAttachInput, {
		attachedFileIds,
		isUploading,
		type NoteAttachItem
	} from './NoteAttachInput.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		createOpportunityNote,
		deleteOpportunityNote,
		fetchOpportunityNotes,
		opportunityNoteFileUrl,
		opportunityNotesKey,
		updateOpportunityNote,
		type PipelineNote
	} from '$lib/pipeline/api';
	import { mentionsStillIn, type PickedMention } from '$lib/pipeline/mentions';
	import {
		fetchProfiles,
		pendingFileRefetchMs,
		profilesKey,
		type NoteFile
	} from '$lib/collaboration/api';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import pencilPlusIcon from '@tabler/icons/outline/pencil-plus.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// The Brief's Notes block: immediate-save, unlike the staged `NotesPanel` the Request/Client detail
	// pages use. Authorized by pipeline.edit, including for a Client-targeted Note -- see
	// `$lib/server/pipeline/notes.ts` and the `pipeline_*_opportunity_note` database functions. Keyed by
	// `opportunity.id` in the parent, same as `OpportunityTasksSection`, so switching cards resets any open
	// composer or edit row instead of leaking it onto the next card.
	//
	// A Note can carry photos and files and @mention teammates (E3). Its files are uploaded against the
	// card's Request, or its Client when there is none -- the database accepts either for a Note on this card.
	let {
		opportunityId,
		requestId,
		clientId,
		currentUserId,
		canEdit
	}: {
		opportunityId: string;
		requestId: string | null;
		clientId: string | null;
		currentUserId?: string;
		canEdit: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const uploadOrigin = $derived<{ type: 'request' | 'client'; id: string | null }>(
		requestId ? { type: 'request', id: requestId } : { type: 'client', id: clientId }
	);

	// A freshly attached file is checked for viruses after the Note saves; until it is, the list is asked
	// again every few seconds so the photo appears on its own.
	const notesQuery = createQuery(() => ({
		queryKey: opportunityNotesKey(opportunityId),
		queryFn: () => fetchOpportunityNotes(opportunityId),
		refetchInterval: (query: { state: { data?: PipelineNote[]; dataUpdateCount: number } }) =>
			query.state.data?.some((note) =>
				note.files.some((file) => file.processing_state === 'pending')
			)
				? pendingFileRefetchMs(query.state.dataUpdateCount)
				: false
	}));
	const notes = $derived(notesQuery.data ?? []);

	// Authors and the people each Note mentions, so both can be named.
	const profileIds = $derived([
		...new Set(
			notes
				.flatMap((note) => [note.created_by, note.edited_by, ...note.mention_user_ids])
				.filter((id): id is string => Boolean(id))
		)
	]);
	const profilesQuery = createQuery(() => ({
		queryKey: profilesKey(profileIds),
		queryFn: () => fetchProfiles(profileIds),
		enabled: profileIds.length > 0
	}));
	const profileById = $derived(
		new Map((profilesQuery.data ?? []).map((profile) => [profile.id, profile]))
	);

	function mentionNames(note: PipelineNote) {
		return note.mention_user_ids
			.map((id) => profileById.get(id)?.full_name)
			.filter((name): name is string => Boolean(name));
	}

	function noteFileSrc(file: NoteFile, size: 'thumb' | 'full') {
		return opportunityNoteFileUrl(opportunityId, file.id, size);
	}

	function downloadNoteFile(file: NoteFile) {
		window.location.href = opportunityNoteFileUrl(opportunityId, file.id, 'download');
	}

	function invalidateNotes() {
		return queryClient.invalidateQueries({ queryKey: opportunityNotesKey(opportunityId) });
	}

	// --- Composer -----------------------------------------------------------------------------------------

	let composerOpen = $state(false);
	let newBody = $state('');
	let newPicked = $state<PickedMention[]>([]);
	let newItems = $state<NoteAttachItem[]>([]);
	let newTarget = $state<'request' | 'client'>('request');
	const showComposer = $derived(canEdit && (composerOpen || notes.length > 0));
	const newUploading = $derived(isUploading(newItems));

	const targetOptions = $derived(
		clientId
			? [
					{ value: 'request', label: 'Request' },
					{ value: 'client', label: 'Client' }
				]
			: [{ value: 'request', label: 'Request' }]
	);

	const createMutationState = createMutation(() => ({
		mutationFn: () => {
			const body = newBody.trim();
			return createOpportunityNote(opportunityId, {
				entityType: newTarget,
				body,
				fileIds: attachedFileIds(newItems),
				mentionUserIds: mentionsStillIn(body, newPicked)
			});
		},
		onSuccess: () => {
			invalidateNotes();
			newBody = '';
			newPicked = [];
			newItems = [];
			composerOpen = false;
			toast.success('Note added');
		},
		onError: (error: Error) => toast.error('Could not add the note', error.message)
	}));

	function addNote() {
		if (!newBody.trim() || newUploading) return;
		createMutationState.mutate();
	}

	// --- Editing an existing note ---------------------------------------------------------------------------

	let editingId = $state<string | null>(null);
	let editBody = $state('');
	let editPicked = $state<PickedMention[]>([]);
	let editItems = $state<NoteAttachItem[]>([]);
	const editUploading = $derived(isUploading(editItems));

	function startEdit(note: PipelineNote) {
		editingId = note.id;
		editBody = note.body;
		editPicked = note.mention_user_ids.map((id) => ({
			id,
			name: profileById.get(id)?.full_name ?? ''
		}));
		editItems = note.files.map((file) => ({
			key: file.id,
			name: file.display_name,
			status: 'saved',
			progress: 1,
			fileId: file.id,
			error: ''
		}));
	}

	// Who the edited text still names. A mention whose name could not be looked up is kept as it was, so a
	// slow profile lookup never silently drops someone.
	function editMentionIds(body: string) {
		const unnamed = editPicked.filter((mention) => !mention.name).map((mention) => mention.id);
		return [...new Set([...mentionsStillIn(body, editPicked), ...unnamed])];
	}

	function sameList(a: string[], b: string[]) {
		return a.length === b.length && a.every((value, index) => value === b[index]);
	}

	const updateMutationState = createMutation(() => ({
		mutationFn: (note: PipelineNote) => {
			const body = editBody.trim();
			return updateOpportunityNote(opportunityId, note.id, {
				body,
				fileIds: attachedFileIds(editItems),
				mentionUserIds: editMentionIds(body)
			});
		},
		onSuccess: () => {
			invalidateNotes();
			editingId = null;
			toast.success('Note saved');
		},
		onError: (error: Error) => toast.error('Could not save the note', error.message)
	}));

	function applyEdit(note: PipelineNote) {
		const body = editBody.trim();
		if (!body || editUploading) return;
		const unchanged =
			body === note.body &&
			sameList(
				attachedFileIds(editItems),
				note.files.map((file) => file.id)
			) &&
			sameList([...editMentionIds(body)].sort(), [...note.mention_user_ids].sort());
		if (unchanged) {
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
			toast.success('Note deleted');
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
			<MentionTextarea
				id={`opportunity-note-composer-${opportunityId}`}
				label="Add a note — type @ to mention a teammate"
				bind:value={newBody}
				bind:picked={newPicked}
				maxlength={4000}
				rows={3}
			/>
			<div class="brief-notes__composer-actions">
				<NoteAttachInput
					id={`opportunity-note-attach-${opportunityId}`}
					bind:items={newItems}
					originType={uploadOrigin.type}
					originId={uploadOrigin.id}
					disabled={createMutationState.isPending}
				/>
				<Button
					size="small"
					disabled={!newBody.trim() || newUploading || createMutationState.isPending}
					onclick={addNote}
				>
					{newUploading ? 'Uploading…' : 'Add note'}
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
							<MentionTextarea
								id={`opportunity-note-edit-${note.id}`}
								bind:value={editBody}
								bind:picked={editPicked}
								maxlength={4000}
								rows={3}
							/>
							<NoteAttachInput
								id={`opportunity-note-edit-attach-${note.id}`}
								bind:items={editItems}
								originType={uploadOrigin.type}
								originId={uploadOrigin.id}
								disabled={updateMutationState.isPending}
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
									disabled={!editBody.trim() || editUploading || updateMutationState.isPending}
									onclick={() => applyEdit(note)}
								>
									{editUploading ? 'Uploading…' : 'Done'}
								</Button>
							</div>
						</div>
					{:else}
						<NoteBody body={note.body} mentionNames={mentionNames(note)} />
						<NoteFiles files={note.files} imageSrc={noteFileSrc} onDownload={downloadNoteFile} />
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
			flex-wrap: wrap;
			align-items: flex-start;
			justify-content: space-between;
			gap: var(--space-small);

			> :global(.note-attach) {
				flex: 1 1 200px;
				min-width: 0;
			}
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
