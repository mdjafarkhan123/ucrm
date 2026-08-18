<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import AuthorMeta from '$lib/components/collaboration/AuthorMeta.svelte';
	import {
		fetchNotes,
		fetchProfiles,
		notesKey,
		profilesKey,
		type EntityType,
		type Note,
		type NoteChange
	} from '$lib/collaboration/api';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import pencilPlusIcon from '@tabler/icons/outline/pencil-plus.svg?raw';
	import pinIcon from '@tabler/icons/outline/pin.svg?raw';
	import pinnedOffIcon from '@tabler/icons/outline/pinned-off.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import undoIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';

	// Nothing here writes to the server. Adding, editing, pinning, and deleting a note all stage a change,
	// and the page's action bar saves them together with the rest of the record. The container owns the
	// "Notes" heading and its count, so the panel draws no heading of its own.
	let {
		entityType,
		entityId,
		canManage = false,
		currentUserId,
		pending = [],
		onChange
	}: {
		entityType: EntityType;
		entityId: string;
		canManage?: boolean;
		currentUserId?: string;
		/** Staged changes, held by the page so its action bar can save them. */
		pending?: NoteChange[];
		onChange: (next: NoteChange[]) => void;
	} = $props();

	const notesQuery = createQuery<Note[]>(() => ({
		queryKey: notesKey(entityType, entityId),
		queryFn: () => fetchNotes(entityType, entityId)
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

	// --- Staged changes ---------------------------------------------------------------------------------

	function stage(change: NoteChange) {
		onChange([...pending, change]);
	}

	/** Replaces any earlier staged change of the same kind for the same note, so a row never queues twice. */
	function restage(change: NoteChange & { id: string }) {
		onChange([
			...pending.filter(
				(entry) => !('id' in entry && entry.id === change.id && entry.kind === change.kind)
			),
			change
		]);
	}

	function unstage(predicate: (change: NoteChange) => boolean) {
		onChange(pending.filter((change) => !predicate(change)));
	}

	const createdNotes = $derived(pending.filter((change) => change.kind === 'create'));
	const stagedBodyFor = $derived((id: string) => {
		const edit = pending.find((change) => change.kind === 'update' && change.id === id);
		return edit?.kind === 'update' ? edit.body : undefined;
	});
	const stagedPinFor = $derived((id: string) => {
		const pin = pending.find((change) => change.kind === 'pin' && change.id === id);
		return pin?.kind === 'pin' ? pin.pinned : undefined;
	});
	const isStagedForDelete = $derived((id: string) =>
		pending.some((change) => change.kind === 'delete' && change.id === id)
	);

	// --- Composer ---------------------------------------------------------------------------------------

	let newBody = $state('');
	let composerOpen = $state(false);
	const showComposer = $derived(
		canManage && (composerOpen || notes.length > 0 || createdNotes.length > 0)
	);

	async function openComposer() {
		composerOpen = true;
		await tick();
		document.getElementById(`note-composer-${entityId}`)?.focus();
	}

	function addNote() {
		const body = newBody.trim();
		if (!body) return;
		stage({ kind: 'create', key: crypto.randomUUID(), body });
		newBody = '';
	}

	// --- Editing an existing note -----------------------------------------------------------------------

	let editingId = $state<string | null>(null);
	let editBody = $state('');

	function startEdit(note: Note) {
		editingId = note.id;
		editBody = stagedBodyFor(note.id) ?? note.body;
	}

	function applyEdit(note: Note) {
		const body = editBody.trim();
		if (!body) return;
		// Typing it back to what is saved is not a change worth queueing.
		if (body === note.body) unstage((change) => change.kind === 'update' && change.id === note.id);
		else restage({ kind: 'update', id: note.id, body });
		editingId = null;
	}

	function togglePin(note: Note) {
		const next = stagedPinFor(note.id) ?? note.pinned;
		if (!next === note.pinned) unstage((change) => change.kind === 'pin' && change.id === note.id);
		else restage({ kind: 'pin', id: note.id, pinned: !next });
	}

	function pinnedOf(note: Note) {
		return stagedPinFor(note.id) ?? note.pinned;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="notes-panel">
	{#if showComposer}
		<div class="notes-panel__composer">
			<Textarea
				id={`note-composer-${entityId}`}
				label="Add a note"
				bind:value={newBody}
				maxlength={4000}
				rows={3}
			/>
			<div class="notes-panel__composer-actions">
				<Button size="small" disabled={!newBody.trim()} onclick={addNote}>Add note</Button>
			</div>
		</div>
	{/if}

	{#if notesQuery.isPending}
		<p class="notes-panel__muted">Loading notes…</p>
	{:else if notesQuery.isError}
		<p class="notes-panel__error" role="alert">
			{notesQuery.error instanceof Error ? notesQuery.error.message : 'Notes could not be loaded.'}
		</p>
	{:else if notes.length === 0 && createdNotes.length === 0 && !showComposer}
		<EmptyState
			title="No notes yet"
			description="Notes you add here are visible to everyone on your team."
			icon={canManage ? pencilPlusIcon : notesIcon}
			iconLabel={canManage ? 'Add a note' : undefined}
			onIconClick={canManage ? openComposer : undefined}
		/>
	{:else}
		<ul class="notes-panel__list">
			{#each createdNotes as draft (draft.key)}
				<li class="notes-panel__item notes-panel__item--draft">
					<div class="notes-panel__item-header">
						<Badge size="small" status="warning">Not saved yet</Badge>
						<button
							type="button"
							class="notes-panel__undo"
							onclick={() =>
								unstage((change) => change.kind === 'create' && change.key === draft.key)}
						>
							Remove
						</button>
					</div>
					<p class="notes-panel__body">{draft.body}</p>
				</li>
			{/each}

			{#each notes as note (note.id)}
				{@const removed = isStagedForDelete(note.id)}
				{@const body = stagedBodyFor(note.id) ?? note.body}
				<li
					class="notes-panel__item"
					class:notes-panel__item--pinned={pinnedOf(note) && !removed}
					class:notes-panel__item--removed={removed}
				>
					<div class="notes-panel__item-header">
						<AuthorMeta
							userId={note.created_by}
							profile={note.created_by ? profileById.get(note.created_by) : undefined}
							{currentUserId}
							timestamp={note.created_at}
							suffix={note.edited_at ? 'edited' : undefined}
						/>
						<div class="notes-panel__item-actions">
							{#if body !== note.body || pinnedOf(note) !== note.pinned}
								<Badge size="small" status="warning">Unsaved</Badge>
							{/if}
							{#if pinnedOf(note) && !removed}
								<span class="notes-panel__pin-flag" title="Pinned" aria-hidden="true"
									>{@html pinIcon}</span
								>
							{/if}
							{#if removed}
								<button
									type="button"
									class="notes-panel__undo"
									onclick={() =>
										unstage((change) => change.kind === 'delete' && change.id === note.id)}
								>
									<span aria-hidden="true">{@html undoIcon}</span>Undo
								</button>
							{:else if canManage}
								<DropdownMenu
									triggerLabel="Note actions"
									items={[
										{
											label: pinnedOf(note) ? 'Unpin' : 'Pin',
											icon: pinnedOf(note) ? pinnedOffIcon : pinIcon,
											onSelect: () => togglePin(note)
										},
										{ label: 'Edit', icon: pencilIcon, onSelect: () => startEdit(note) },
										{
											label: 'Delete',
											icon: trashIcon,
											destructive: true,
											onSelect: () => restage({ kind: 'delete', id: note.id })
										}
									]}
								/>
							{/if}
						</div>
					</div>

					{#if editingId === note.id && !removed}
						<div class="notes-panel__edit">
							<Textarea
								id={`note-edit-${note.id}`}
								bind:value={editBody}
								maxlength={4000}
								rows={3}
							/>
							<div class="notes-panel__edit-actions">
								<Button
									size="small"
									variant="secondary"
									variation="subtle"
									onclick={() => (editingId = null)}
								>
									Cancel
								</Button>
								<Button size="small" disabled={!editBody.trim()} onclick={() => applyEdit(note)}>
									Done
								</Button>
							</div>
						</div>
					{:else}
						<p class="notes-panel__body">{body}</p>
						{#if removed}
							<p class="notes-panel__muted">Will be deleted when you save.</p>
						{/if}
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.notes-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__composer {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__composer-actions {
			display: flex;
			justify-content: flex-end;
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
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

			&--pinned {
				border-color: var(--color-warning);
				background: var(--color-warning--surface);
			}

			// Still on screen so it can be put back, but clearly on its way out.
			&--removed {
				border-style: dashed;
				opacity: 0.6;

				.notes-panel__body {
					text-decoration: line-through;
				}
			}

			&--draft {
				border-style: dashed;
				border-color: var(--color-warning);
			}
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

		&__undo {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				color: var(--color-interactive--hover);
			}

			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__pin-flag {
			display: grid;
			width: 20px;
			height: 20px;
			place-items: center;
			color: var(--color-warning--onSurface);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
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
