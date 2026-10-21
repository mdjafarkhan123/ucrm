<script lang="ts">
	import { tick } from 'svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import AuthorMeta from '$lib/components/collaboration/AuthorMeta.svelte';
	import NoteBody from '$lib/components/collaboration/NoteBody.svelte';
	import NoteFiles from '$lib/components/collaboration/NoteFiles.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchNotes,
		fetchProfiles,
		notesKey,
		pendingFileRefetchMs,
		profilesKey,
		type EntityType,
		type Note,
		type NoteChange,
		type NoteFile
	} from '$lib/collaboration/api';
	import { downloadFile, fileImageUrl } from '$lib/files/api';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import dotsIcon from '@tabler/icons/outline/dots.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
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
		canManageTeam = canManage,
		currentUserId,
		pending = [],
		compact = false,
		onChange
	}: {
		entityType: EntityType;
		entityId: string;
		canManage?: boolean;
		/** May change another teammate's note. Own notes still follow canManage. */
		canManageTeam?: boolean;
		currentUserId?: string;
		/** Staged changes, held by the page so its action bar can save them. */
		pending?: NoteChange[];
		/** App look: notes read as rows under hairlines, and the note field sits at the bottom with a send
		 *  button. Sending still only stages the note; the page's bar saves it. */
		compact?: boolean;
		onChange: (next: NoteChange[]) => void;
	} = $props();

	const toast = getToastManager();

	// A photo added from the Pipeline Brief is still being virus-checked for a moment; until it is, the list
	// is asked again every few seconds so it appears on its own.
	const notesQuery = createQuery<Note[]>(() => ({
		queryKey: notesKey(entityType, entityId),
		queryFn: () => fetchNotes(entityType, entityId),
		refetchInterval: (query: { state: { data?: Note[]; dataUpdateCount: number } }) =>
			query.state.data?.some((note) =>
				note.files.some((file) => file.processing_state === 'pending')
			)
				? pendingFileRefetchMs(query.state.dataUpdateCount)
				: false
	}));
	const notes = $derived(notesQuery.data ?? []);
	const canManageNote = (note: Note) =>
		canManage && (canManageTeam || Boolean(currentUserId && note.created_by === currentUserId));

	// Authors and the people each Note mentions, so both can be named.
	const profileIds = $derived([
		...new Set(
			notes
				.flatMap((note) => [note.created_by, note.edited_by, ...note.mention_user_ids])
				.concat(
					compact && pending.some((change) => change.kind === 'create') ? [currentUserId] : []
				)
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

	function mentionNames(note: Note) {
		return note.mention_user_ids
			.map((id) => profileById.get(id)?.full_name)
			.filter((name): name is string => Boolean(name));
	}

	async function downloadNoteFile(file: NoteFile) {
		try {
			await downloadFile(file.id);
		} catch (error) {
			toast.error(
				'Could not download the file',
				error instanceof Error ? error.message : undefined
			);
		}
	}

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

	/** What the compact panel's status line says about a saved note's changes waiting for Save. */
	function waitingFor(note: Note) {
		if (stagedBodyFor(note.id) !== undefined) return 'Edit waiting for Save';
		const pin = stagedPinFor(note.id);
		if (pin !== undefined && pin !== note.pinned)
			return pin ? 'Pin waiting for Save' : 'Unpin waiting for Save';
		return undefined;
	}

	// A new note has no saved time yet; its author line shows when it was written.
	const draftTimes = new Map<string, string>();
	function draftTime(key: string) {
		if (!draftTimes.has(key)) draftTimes.set(key, new Date().toISOString());
		return draftTimes.get(key)!;
	}

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

	// One line until the note needs more, then it grows with the text up to the CSS limit.
	function growField(event: Event) {
		const field = event.currentTarget as HTMLTextAreaElement;
		field.style.height = '28px';
		field.style.height = `${Math.min(field.scrollHeight, 120)}px`;
	}

	function sendFromField(event: KeyboardEvent) {
		if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
		event.preventDefault();
		addNote();
	}

	function addNote() {
		const body = newBody.trim();
		if (!body) return;
		stage({ kind: 'create', key: crypto.randomUUID(), body });
		newBody = '';
		const field = document.getElementById(`note-composer-${entityId}`);
		if (field && compact) field.style.height = '28px';
	}

	// --- Editing an existing note -----------------------------------------------------------------------

	let editingId = $state<string | null>(null);
	let editBody = $state('');

	async function startEdit(note: Note) {
		editingId = note.id;
		editBody = stagedBodyFor(note.id) ?? note.body;
		if (!compact) return;
		await tick();
		document.getElementById(`note-edit-${note.id}`)?.focus();
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
{#if !compact}
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
				{notesQuery.error instanceof Error
					? notesQuery.error.message
					: 'Notes could not be loaded.'}
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
							<Button
								variant="quiet"
								size="small"
								onclick={() =>
									unstage((change) => change.kind === 'create' && change.key === draft.key)}
							>
								Remove
							</Button>
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
									<Button
										variant="quiet"
										size="small"
										onclick={() =>
											unstage((change) => change.kind === 'delete' && change.id === note.id)}
									>
										{@html undoIcon}Undo
									</Button>
								{:else if canManageNote(note)}
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
							<NoteBody {body} mentionNames={mentionNames(note)} />
							<NoteFiles
								files={note.files}
								imageSrc={(file, size) => fileImageUrl(file.id, size)}
								onDownload={downloadNoteFile}
							/>
							{#if removed}
								<p class="notes-panel__muted">Will be deleted when you save.</p>
							{/if}
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</div>
{:else}
	<!-- concept.pen → "Notes panel · menu and states" (l9ZBWI), look in the design skill's notes.md. -->
	<div class="notes-panel notes-panel--compact">
		{#if notesQuery.isPending}
			<div class="notes-panel__list" role="status" aria-label="Loading notes" aria-busy="true">
				{#each [0, 1, 2] as index (index)}
					<div class="notes-panel__bone">
						<span class="skeleton notes-panel__bone-avatar"></span>
						<span class="notes-panel__bone-lines">
							<span class="skeleton notes-panel__bone-line notes-panel__bone-line--name"></span>
							<span class="skeleton notes-panel__bone-line"></span>
							<span class="skeleton notes-panel__bone-line notes-panel__bone-line--short"></span>
						</span>
					</div>
				{/each}
			</div>
		{:else if notesQuery.isError}
			<div class="notes-panel__state" role="alert">
				<IconTile icon={alertIcon} tone="critical" size={32} />
				<p class="notes-panel__state-title">Notes didn't load</p>
				<p class="notes-panel__state-hint">Check your connection, then try again.</p>
				<Button
					size="small"
					variant="secondary"
					loading={notesQuery.isFetching}
					onclick={() => notesQuery.refetch()}
				>
					{@html refreshIcon}Try again
				</Button>
			</div>
		{:else if notes.length === 0 && createdNotes.length === 0}
			<div class="notes-panel__state">
				{#if !canManage}<IconTile icon={notesIcon} tone="inactive" size={32} />{/if}
				<p class="notes-panel__state-title">No notes yet</p>
				{#if canManage}
					<p class="notes-panel__state-hint">
						Gate codes, pets, parking: anything the crew should know before they arrive.
					</p>
				{/if}
			</div>
		{:else}
			<ul class="notes-panel__list">
				{#each createdNotes as draft (draft.key)}
					<li class="notes-panel__note notes-panel__note--draft">
						<div class="notes-panel__note-top">
							<AuthorMeta
								userId={currentUserId ?? null}
								profile={currentUserId ? profileById.get(currentUserId) : undefined}
								{currentUserId}
								fallbackName="You"
								timestamp={draftTime(draft.key)}
							/>
						</div>
						<NoteBody body={draft.body} mentionNames={[]} />
						<div class="notes-panel__status notes-panel__status--warning">
							<span class="notes-panel__status-icon" aria-hidden="true">{@html clockIcon}</span>
							Not saved yet
							<span class="notes-panel__status-action">
								<Button
									variant="quiet"
									size="small"
									onclick={() =>
										unstage((change) => change.kind === 'create' && change.key === draft.key)}
								>
									Remove
								</Button>
							</span>
						</div>
					</li>
				{/each}

				{#each notes as note (note.id)}
					{@const removed = isStagedForDelete(note.id)}
					{@const body = stagedBodyFor(note.id) ?? note.body}
					{@const editing = editingId === note.id && !removed}
					{@const waiting = removed ? undefined : waitingFor(note)}
					<li
						class="notes-panel__note"
						class:notes-panel__note--pinned={pinnedOf(note) && !removed}
						class:notes-panel__note--removed={removed}
					>
						<div class="notes-panel__note-top">
							<span class="notes-panel__author">
								<AuthorMeta
									userId={note.created_by}
									profile={note.created_by ? profileById.get(note.created_by) : undefined}
									{currentUserId}
									timestamp={note.created_at}
									suffix={note.edited_at ? 'edited' : undefined}
								/>
							</span>
							{#if !removed && !editing}
								<span class="notes-panel__note-actions">
									{#if pinnedOf(note)}
										<span class="notes-panel__pin" title="Pinned" aria-hidden="true"
											>{@html pinIcon}</span
										>
									{/if}
									{#if canManageNote(note)}
										<DropdownMenu
											triggerLabel="Note actions"
											triggerIcon={dotsIcon}
											triggerClass="dropdown-menu__trigger notes-panel__menu-trigger"
											items={[
												{
													label: pinnedOf(note) ? 'Unpin' : 'Pin',
													icon: pinnedOf(note) ? pinnedOffIcon : pinIcon,
													onSelect: () => togglePin(note)
												},
												{ label: 'Edit', icon: pencilIcon, onSelect: () => startEdit(note) }
											]}
											footer={[
												{
													label: 'Delete',
													icon: trashIcon,
													destructive: true,
													onSelect: () => restage({ kind: 'delete', id: note.id })
												}
											]}
										/>
									{/if}
								</span>
							{/if}
						</div>

						{#if editing}
							<textarea
								id={`note-edit-${note.id}`}
								class="notes-panel__edit-input"
								aria-label="Edit the note"
								rows="3"
								maxlength="4000"
								bind:value={editBody}></textarea>
							<div class="notes-panel__edit-actions">
								<Button size="small" variant="secondary" onclick={() => (editingId = null)}>
									Cancel
								</Button>
								<Button size="small" disabled={!editBody.trim()} onclick={() => applyEdit(note)}>
									Done
								</Button>
							</div>
						{:else}
							<NoteBody {body} mentionNames={mentionNames(note)} />
							<NoteFiles
								files={note.files}
								imageSrc={(file, size) => fileImageUrl(file.id, size)}
								onDownload={downloadNoteFile}
							/>
						{/if}

						{#if removed}
							<div class="notes-panel__status notes-panel__status--critical">
								<span class="notes-panel__status-icon" aria-hidden="true">{@html trashIcon}</span>
								Deleted when you save
								<span class="notes-panel__status-action">
									<Button
										variant="secondary"
										size="small"
										onclick={() =>
											unstage((change) => change.kind === 'delete' && change.id === note.id)}
									>
										{@html undoIcon}Undo
									</Button>
								</span>
							</div>
						{:else if waiting && !editing}
							<div class="notes-panel__status notes-panel__status--warning">
								<span class="notes-panel__status-icon" aria-hidden="true">{@html clockIcon}</span>
								{waiting}
							</div>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}

		{#if canManage}
			<div class="notes-panel__foot">
				<div class="notes-panel__field">
					<textarea
						id={`note-composer-${entityId}`}
						class="notes-panel__field-input"
						aria-label="Write a note for the team"
						placeholder="Write a note for the team…"
						rows="1"
						maxlength="4000"
						bind:value={newBody}
						onkeydown={sendFromField}
						oninput={growField}></textarea>
					<button
						type="button"
						class="notes-panel__send"
						class:notes-panel__send--ready={newBody.trim()}
						aria-label="Add note"
						disabled={!newBody.trim()}
						onclick={addNote}>{@html arrowUpIcon}</button
					>
				</div>
			</div>
		{/if}
	</div>
{/if}

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
			padding: var(--space-slim);
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			background: var(--color-surface--background);

			&--pinned {
				border-color: var(--color-warning);
				background: var(--color-warning--surface);
			}

			// Still on screen so it can be put back, but clearly on its way out.
			&--removed {
				border-style: dashed;
				opacity: 0.6;

				:global(.note-body) {
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

	// App look (`notes.md` → Notes panel): note bands in the card's body, and the note field at the foot.
	.notes-panel--compact {
		gap: 0;

		.notes-panel__list {
			display: flex;
			flex-direction: column;
			gap: 10px;
			margin: 0;
			padding: var(--space-base);
			list-style: none;
		}
	}

	.notes-panel__note {
		display: flex;
		flex-direction: column;
		min-width: 0;
		padding: var(--space-slim);
		border: var(--border-base) solid transparent;
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		&--pinned {
			border-color: var(--color-warning--surface-edge);
			background: var(--color-warning--surface);
		}

		&--draft {
			border-color: var(--color-warning);
			background: var(--color-surface);
		}

		// Still on screen so it can be put back, but clearly on its way out.
		&--removed {
			.notes-panel__author {
				opacity: 0.5;
			}

			:global(.note-body) {
				color: var(--color-text--secondary);
				text-decoration: line-through;
			}
		}
	}

	.notes-panel__note-top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-small);
		min-width: 0;
	}

	.notes-panel__author {
		display: flex;
		min-width: 0;
	}

	.notes-panel__note-actions {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-smaller);
	}

	.notes-panel__pin {
		display: grid;
		place-items: center;
		color: var(--color-warning);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	:global(.dropdown-menu__trigger.notes-panel__menu-trigger) {
		width: 28px;
		height: 28px;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.notes-panel__status {
		display: flex;
		align-items: center;
		gap: 6px;
		margin-top: var(--space-small);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;

		&--warning {
			color: var(--color-warning--onSurface);
		}

		&--critical {
			color: var(--color-critical--onSurface);
		}
	}

	.notes-panel__status-icon {
		display: grid;
		flex: 0 0 auto;
		place-items: center;

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}
	}

	.notes-panel__status-action {
		margin-left: auto;
	}

	.notes-panel__edit-input {
		width: 100%;
		min-height: 72px;
		margin-top: 6px;
		padding: var(--space-small) var(--space-slim);
		border: var(--border-base) solid var(--color-interactive);
		border-radius: var(--radius-base);
		outline: none;
		box-shadow: 0 0 0 0.5px var(--color-interactive);
		color: var(--color-text);
		background: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-base);
		line-height: var(--typography--lineHeight-large);
		resize: vertical;
	}

	.notes-panel__edit-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
		margin-top: var(--space-small);
	}

	// Three note-shaped bones while the notes load.
	.notes-panel__bone {
		display: flex;
		gap: var(--space-small);
		padding: var(--space-slim);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}

	.notes-panel__bone-avatar {
		flex: 0 0 auto;
		width: 32px;
		height: 32px;
		border-radius: var(--radius-circle);
	}

	.notes-panel__bone-lines {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		gap: var(--space-small);
		padding-top: var(--space-smaller);
	}

	.notes-panel__bone-line {
		height: 8px;
		border-radius: var(--radius-small);

		&--name {
			width: 96px;
			height: 10px;
		}

		&--short {
			width: 60%;
		}
	}

	// Empty and couldn't load: a few quiet lines, centred over the note field.
	.notes-panel__state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-large) var(--space-base) var(--space-medium);
		text-align: center;

		:global(.icon-tile) {
			margin-bottom: var(--space-smaller);
		}

		:global(.button) {
			margin-top: var(--space-small);
		}
	}

	.notes-panel__state-title {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
	}

	.notes-panel__state-hint {
		max-width: 260px;
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-large);
	}

	.notes-panel__foot {
		padding: var(--space-slim) var(--space-base) var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}

	.notes-panel__field {
		display: flex;
		align-items: flex-end;
		gap: var(--space-small);
		padding: var(--space-smaller) var(--space-smaller) var(--space-smaller) var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
		transition:
			border-color var(--timing-base),
			background-color var(--timing-base);

		&:focus-within {
			border-color: var(--color-interactive);
			box-shadow: 0 0 0 0.5px var(--color-interactive);
			background: var(--color-surface);
		}
	}

	.notes-panel__field-input {
		flex: 1 1 auto;
		align-self: center;
		min-width: 0;
		height: 28px;
		min-height: 28px;
		max-height: 120px;
		padding: var(--space-smaller) 0;
		border: 0;
		outline: none;
		color: var(--color-text);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-base);
		line-height: 1.4;
		resize: none;
		overflow-y: auto;

		// The app-wide placeholder rule leaves room above it for a floating label; this field has none.
		&::placeholder {
			padding-top: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
		}
	}

	.notes-panel__send {
		display: grid;
		flex: 0 0 auto;
		width: 32px;
		height: 32px;
		place-items: center;
		border: 0;
		border-radius: var(--radius-base);
		color: var(--color-inactive--onSurface);
		background: var(--color-inactive--surface);
		cursor: not-allowed;
		transition: background-color var(--timing-base);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}

		&--ready {
			color: var(--color-surface);
			background: var(--color-interactive);
			cursor: pointer;

			&:hover {
				background: var(--color-interactive--hover);
			}

			&:active {
				background: var(--color-interactive--hover);
			}
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
</style>
