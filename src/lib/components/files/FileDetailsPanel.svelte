<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import FileThumb from './FileThumb.svelte';
	import FileAttachToRecordDialog from './FileAttachToRecordDialog.svelte';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import folderIcon from '@tabler/icons/outline/folder.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import restoreIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import {
		downloadFile,
		fetchFile,
		fetchFileFolders,
		fileDetailKey,
		fileFoldersKey,
		fileImageUrl,
		formatFileSize,
		formatFileType,
		formatOrigin,
		formatRole,
		moveFile,
		renameFile,
		restoreFile,
		trashFile,
		usageGroupLabel,
		type FileListItem,
		type FileUsageRow
	} from '$lib/files/api';

	// The right-side panel for one File. The library stays visible behind it and keeps its scroll, which is
	// the whole reason this is a side panel rather than a page.
	let {
		file,
		open,
		onClose,
		onOpenLightbox
	}: {
		/** The row that was clicked. Its facts draw the panel instantly while the full detail loads. */
		file: FileListItem | null;
		open: boolean;
		onClose: () => void;
		/** Opens the full-size picture. Left out when the file is not a viewable photo. */
		onOpenLightbox?: (file: FileListItem) => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const uid = $props.id();

	// Off until there is a file to ask about. Hover on a tile has usually already prefetched this, so a
	// click normally paints from cache; a click that beats the prefetch shows the skeleton below.
	const detailQuery = createQuery(() => ({
		queryKey: fileDetailKey(file?.id ?? ''),
		queryFn: () => fetchFile(file!.id),
		enabled: Boolean(file)
	}));

	const detail = $derived(detailQuery.data);
	const usage = $derived(detail?.usage ?? []);
	// The count is of distinct records this reader may view. A hidden job is absent from the list and from
	// the number, so the total can never hint that one exists.
	const usageCount = $derived(usage.length);
	const isPhoto = $derived(file?.kind === 'image' && file.processing_state === 'available');

	// "Used in" groups by record type, the way the blueprint asks: Quotes (3), Jobs (2).
	const usageGroups = $derived.by(() => {
		const groups: [string, FileUsageRow[]][] = [];
		for (const row of usage) {
			const existing = groups.find(([entityType]) => entityType === row.entity_type);
			if (existing) existing[1].push(row);
			else groups.push([row.entity_type, [row]]);
		}
		return groups;
	});

	// --- The manage actions -----------------------------------------------------------------------------
	// What this member may do is the server's answer, carried on the detail. Every write re-checks it, so
	// this only decides which items the menu offers.

	const canManage = $derived(detail?.can_manage ?? false);
	const canTrash = $derived(detail?.can_trash ?? false);
	const inTrash = $derived(Boolean(file?.trashed_at));
	// A use the customer already received cannot be detached, so the file cannot go to Trash until its
	// owning record retires it. Saying so on the menu beats letting them press it and reading a refusal.
	const hasProtectedUse = $derived(usage.some((row) => row.protected));

	let renameOpen = $state(false);
	let renameValue = $state('');
	let moveOpen = $state(false);
	let moveValue = $state('');
	let trashOpen = $state(false);
	let saving = $state(false);
	let actionError = $state('');

	// Off until the move dialog is opened. The File Manager has usually filled this cache already — same
	// query key — so the dialog normally paints its folder list with nothing to wait for.
	const foldersQuery = createQuery(() => ({
		queryKey: fileFoldersKey,
		queryFn: fetchFileFolders,
		enabled: moveOpen
	}));
	const folderOptions = $derived([
		{ value: '', label: 'No folder' },
		...(foldersQuery.data ?? []).map((folder) => ({ value: folder.id, label: folder.name }))
	]);

	// Every list, every folder count and this file's own detail can all have changed, and which ones did
	// depends on the view the contractor is looking at. Invalidating the three roots is cheaper to be right
	// about than working out the exact key, and TanStack only refetches what is actually mounted.
	function refreshAfterWrite(fileId: string) {
		void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
		void queryClient.invalidateQueries({ queryKey: fileDetailKey(fileId) });
		void queryClient.invalidateQueries({ queryKey: fileFoldersKey });
	}

	async function runAction(action: () => Promise<unknown>, done: () => void) {
		if (!file || saving) return;
		saving = true;
		actionError = '';
		try {
			await action();
			refreshAfterWrite(file.id);
			done();
		} catch (error) {
			actionError = error instanceof Error ? error.message : 'That did not save.';
		} finally {
			saving = false;
		}
	}

	function openRename() {
		if (!file) return;
		// The extension is added back by the server, so the contractor edits the name they read rather than
		// having to retype ".jpg" to keep it.
		const dot = file.display_name.lastIndexOf('.');
		renameValue = dot > 0 ? file.display_name.slice(0, dot) : file.display_name;
		actionError = '';
		renameOpen = true;
	}

	function openMove() {
		moveValue = file?.folder_id ?? '';
		actionError = '';
		moveOpen = true;
	}

	function submitRename() {
		void runAction(
			() => renameFile(file!.id, renameValue),
			() => {
				renameOpen = false;
				toast.success('File renamed');
			}
		);
	}

	function submitMove() {
		void runAction(
			() => moveFile(file!.id, moveValue || null),
			() => {
				moveOpen = false;
				toast.success(moveValue ? 'File moved' : 'File taken out of its folder');
			}
		);
	}

	function submitTrash() {
		void runAction(
			() => trashFile(file!.id),
			() => {
				trashOpen = false;
				toast.success('File moved to Trash');
				onClose();
			}
		);
	}

	function submitRestore() {
		void runAction(
			() => restoreFile(file!.id),
			() => {
				toast.success('File restored');
				onClose();
			}
		);
	}

	const menuItems = $derived.by(() => {
		if (!file) return [];
		if (inTrash)
			return canTrash
				? [{ label: 'Restore', icon: restoreIcon, onSelect: submitRestore, disabled: saving }]
				: [];
		return [
			...(canManage
				? [
						{ label: 'Rename', icon: pencilIcon, onSelect: openRename },
						{ label: 'Move to folder', icon: folderIcon, onSelect: openMove }
					]
				: []),
			...(canTrash
				? [
						{
							label: 'Move to Trash',
							icon: trashIcon,
							destructive: true,
							disabled: hasProtectedUse,
							onSelect: () => {
								actionError = '';
								trashOpen = true;
							}
						}
					]
				: [])
		];
	});

	let downloadError = $state('');
	// "Attach to…": the file is already chosen, so the dialog asks which record it belongs on. Only offered
	// for a file that has passed its checks, because an unchecked one cannot be attached to anything.
	let attachOpen = $state(false);

	async function handleDownload() {
		if (!file) return;
		downloadError = '';
		try {
			await downloadFile(file.id);
		} catch (error) {
			downloadError = error instanceof Error ? error.message : 'That download did not start.';
		}
	}

	// Annotated, not inferred: `resolve()` returns the whole union of this app's route ids, and inferring
	// four of them together is more than the type checker will represent.
	function usageHref(row: FileUsageRow): string | null {
		if (row.link_type === 'client') return resolve('/(app)/clients/[id=uuid]', { id: row.link_id });
		if (row.link_type === 'request')
			return resolve('/(app)/requests/[id=uuid]', { id: row.link_id });
		if (row.link_type === 'quote') return resolve('/(app)/quotes/[id=uuid]', { id: row.link_id });
		if (row.link_type === 'invoice')
			return resolve('/(app)/invoices/[id=uuid]', { id: row.link_id });
		if (row.link_type === 'job') return resolve('/(app)/jobs/[id=uuid]', { id: row.link_id });
		// A property has no page of its own; it is read on its client, which the row's context names.
		return null;
	}

	function formatUploadedAt(value: string) {
		return new Date(value).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}

	function statusTone(status: string | null) {
		if (!status) return undefined;
		if (['paid', 'approved', 'customer', 'completed', 'closed'].includes(status)) return 'success';
		if (['draft', 'archived'].includes(status)) return 'inactive';
		return 'informative';
	}

	// Closing throws the detail away only if nothing else wants it; TanStack keeps it cached, so reopening
	// the same file is instant.
	function handleClose() {
		queryClient.cancelQueries({ queryKey: fileDetailKey(file?.id ?? '') });
		onClose();
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SidePanel
	{open}
	title={file?.display_name ?? 'File'}
	subtitle={file
		? `${formatFileType(file.mime_type, file.display_name)} · ${formatFileSize(file.size_bytes)}`
		: undefined}
	onClose={handleClose}
>
	{#if !file}
		<LoadingSkeleton variant="card" label="Loading file" />
	{:else}
		<div class="file-panel__preview">
			{#if isPhoto && onOpenLightbox}
				<button
					type="button"
					class="file-panel__preview-button"
					onclick={() => onOpenLightbox(file)}
				>
					<img class="file-panel__image" src={fileImageUrl(file.id)} alt={file.display_name} />
					<span class="file-panel__preview-hint">Open full size</span>
				</button>
			{:else}
				<FileThumb
					fileId={file.id}
					displayName={file.display_name}
					mimeType={file.mime_type}
					kind={file.kind}
					processingState={file.processing_state}
					hasThumbnail={file.has_thumbnail}
					size="panel"
				/>
			{/if}
		</div>

		<div class="file-panel__actions">
			<Button
				variant="secondary"
				size="small"
				disabled={file.processing_state !== 'available'}
				onclick={handleDownload}>Download</Button
			>
			{#if !inTrash}
				<Button
					variant="secondary"
					size="small"
					disabled={file.processing_state !== 'available'}
					onclick={() => {
						actionError = '';
						attachOpen = true;
					}}>Attach to…</Button
				>
			{/if}
			{#if inTrash && canTrash}
				<Button variant="secondary" size="small" disabled={saving} onclick={submitRestore}>
					Restore
				</Button>
			{/if}
			<span class="file-panel__menu">
				{#if menuItems.length > 0}
					<DropdownMenu items={menuItems} triggerLabel="More file actions" />
				{/if}
			</span>
		</div>
		{#if hasProtectedUse && !inTrash}
			<p class="file-panel__note">
				Part of this file has already gone to a customer, so it cannot be moved to Trash until that
				record lets it go.
			</p>
		{/if}
		{#if downloadError}
			<p class="file-panel__error" role="alert">{downloadError}</p>
		{/if}
		{#if actionError && !renameOpen && !moveOpen && !trashOpen}
			<p class="file-panel__error" role="alert">{actionError}</p>
		{/if}

		<dl class="file-panel__facts">
			<div class="file-panel__fact">
				<dt>Type</dt>
				<dd>{formatFileType(file.mime_type, file.display_name)}</dd>
			</div>
			<div class="file-panel__fact">
				<dt>Size</dt>
				<dd>{formatFileSize(file.size_bytes)}</dd>
			</div>
			<div class="file-panel__fact">
				<dt>Uploaded</dt>
				<dd>
					{formatUploadedAt(file.created_at)}{#if detail?.file.uploaded_by_name}
						· {detail.file.uploaded_by_name}{/if}
				</dd>
			</div>
			<div class="file-panel__fact">
				<dt>Came from</dt>
				<dd>{formatOrigin(file.origin_type)}</dd>
			</div>
			<div class="file-panel__fact">
				<dt>Folder</dt>
				<dd>{file.folder_name ?? 'No folder'}</dd>
			</div>
			{#if file.processing_state !== 'available'}
				<div class="file-panel__fact">
					<dt>Status</dt>
					<dd>
						{#if file.processing_state === 'pending'}
							Still being checked
						{:else if file.processing_state === 'quarantined'}
							Blocked by the virus scan
						{:else}
							Upload failed
						{/if}
					</dd>
				</div>
			{/if}
		</dl>

		<section class="file-panel__usage">
			{#if detailQuery.isPending}
				<LoadingSkeleton variant="text" label="Loading where this file is used" rows={4} />
			{:else if detailQuery.isError}
				<ErrorState
					description="Where this file is used could not be loaded."
					retry={() => detailQuery.refetch()}
				/>
			{:else if usageCount === 0}
				<h3 class="file-panel__usage-title">Not attached to anything yet</h3>
				<p class="file-panel__usage-empty">
					This file is in your library but no job, quote or client is using it.
				</p>
			{:else}
				<h3 class="file-panel__usage-title">
					Used in {usageCount}
					{usageCount === 1 ? 'place' : 'places'}
				</h3>
				{#each usageGroups as [entityType, rows] (entityType)}
					<p class="file-panel__group">
						{usageGroupLabel(entityType, rows.length)} ({rows.length})
					</p>
					<ul class="file-panel__rows">
						{#each rows as row (row.id)}
							{@const href = usageHref(row)}
							<li>
								{#if href}
									<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- usageHref() already ran resolve() on a real route id; the rule cannot see through the call. -->
									<a class="file-panel__row" {href}>
										<span class="file-panel__row-main">
											<span class="file-panel__row-title">{row.title ?? 'Record'}</span>
											{#if row.context}<span class="file-panel__row-context">{row.context}</span
												>{/if}
										</span>
										<span class="file-panel__row-meta">
											{#if row.status}<Badge size="small" status={statusTone(row.status)}
													>{row.status}</Badge
												>{/if}
											<span class="file-panel__row-role">{formatRole(row.role)}</span>
											{#if row.protected}
												<span
													class="file-panel__row-lock"
													title="The customer already received this, so it cannot be removed here."
												>
													<span aria-hidden="true">{@html lockIcon}</span>
													<span class="file-panel__row-lock-text">Sent to the customer</span>
												</span>
											{/if}
										</span>
										<span class="file-panel__row-chevron" aria-hidden="true"
											>{@html chevronRightIcon}</span
										>
									</a>
								{:else}
									<div class="file-panel__row file-panel__row--plain">
										<span class="file-panel__row-main">
											<span class="file-panel__row-title">{row.title ?? 'Record'}</span>
											{#if row.context}<span class="file-panel__row-context">{row.context}</span
												>{/if}
										</span>
										<span class="file-panel__row-role">{formatRole(row.role)}</span>
									</div>
								{/if}
							</li>
						{/each}
					</ul>
				{/each}
				{#if detail?.usage_next_cursor}
					<p class="file-panel__usage-more">
						Showing the {usageCount} most recent places this file is used.
					</p>
				{/if}
			{/if}
		</section>
	{/if}
</SidePanel>

<Dialog
	open={renameOpen}
	title="Rename file"
	size="small"
	initialFocusId={`${uid}-rename`}
	onClose={() => (renameOpen = false)}
>
	<form
		class="file-panel__form"
		onsubmit={(event) => {
			event.preventDefault();
			submitRename();
		}}
	>
		<Input id={`${uid}-rename`} label="File name" bind:value={renameValue} required />
		<p class="file-panel__hint">
			The file type stays the same, so <strong
				>.{formatFileType(file?.mime_type ?? '', file?.display_name ?? '').toLowerCase()}</strong
			> is kept on the end for you.
		</p>
		{#if actionError}<p class="file-panel__error" role="alert">{actionError}</p>{/if}
		<div class="file-panel__form-actions">
			<Button variant="secondary" variation="subtle" onclick={() => (renameOpen = false)}>
				Cancel
			</Button>
			<Button type="submit" loading={saving} disabled={!renameValue.trim()}>Save</Button>
		</div>
	</form>
</Dialog>

<Dialog open={moveOpen} title="Move to folder" size="small" onClose={() => (moveOpen = false)}>
	<form
		class="file-panel__form"
		onsubmit={(event) => {
			event.preventDefault();
			submitMove();
		}}
	>
		<Select
			id={`${uid}-folder`}
			label="Folder"
			bind:value={moveValue}
			options={folderOptions}
			contentClass="file-panel__select-content"
		/>
		<p class="file-panel__hint">
			Folders only change where this file sits in your library. It stays attached to exactly the
			same jobs, quotes and clients.
		</p>
		{#if actionError}<p class="file-panel__error" role="alert">{actionError}</p>{/if}
		<div class="file-panel__form-actions">
			<Button variant="secondary" variation="subtle" onclick={() => (moveOpen = false)}>
				Cancel
			</Button>
			<Button type="submit" loading={saving}>Move</Button>
		</div>
	</form>
</Dialog>

<ConfirmDialog
	open={trashOpen}
	title="Move this file to Trash?"
	tone="critical"
	destructive
	confirmLabel="Move to Trash"
	loading={saving}
	onConfirm={submitTrash}
	onClose={() => (trashOpen = false)}
>
	<!-- The contract asks for every affected visible record and the consequence, before the button, not
	     after it. The list is the same "Used in" this reader can already see. -->
	{#if usageCount === 0}
		<p>This file is not attached to anything. It waits in Trash for 30 days before it goes.</p>
	{:else}
		<p>
			It will be taken off {usageCount}
			{usageCount === 1 ? 'record' : 'records'}:
		</p>
		<ul class="file-panel__confirm-list">
			{#each usage as row (row.id)}
				<li>
					{row.title ?? 'Record'}{#if row.context}
						· {row.context}{/if}
				</li>
			{/each}
		</ul>
		<p>
			It waits in Trash for 30 days, and you can restore it. Restoring brings the file back — it
			does not put it back on those records.
		</p>
	{/if}
	{#if actionError}<p class="file-panel__error" role="alert">{actionError}</p>{/if}
</ConfirmDialog>

{#if file}
	<FileAttachToRecordDialog
		open={attachOpen}
		fileId={file.id}
		fileName={file.display_name}
		onClose={() => (attachOpen = false)}
		onAttached={() => toast.success('File attached')}
	/>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.file-panel__preview-button {
		display: block;
		width: 100%;
		padding: 0;
		border: none;
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
		cursor: pointer;

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}
	.file-panel__image {
		display: block;
		width: 100%;
		max-height: 320px;
		object-fit: contain;
		border-radius: var(--radius-base);
	}
	.file-panel__preview-hint {
		display: block;
		padding: var(--space-smaller) 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.file-panel__actions {
		display: flex;
		align-items: center;
		gap: var(--space-small);
	}
	// Pushes the ••• to the far end, where every other record's secondary menu sits.
	.file-panel__menu {
		margin-inline-start: auto;
	}
	.file-panel__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}
	.file-panel__note,
	.file-panel__hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.file-panel__form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}
	.file-panel__form-actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
	.file-panel__confirm-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smallest);
		max-height: 180px;
		overflow-y: auto;
		padding-inline-start: var(--space-base);
		list-style: disc;
	}

	.file-panel__facts {
		display: grid;
		gap: var(--space-small);
	}
	.file-panel__fact {
		display: grid;
		grid-template-columns: 110px 1fr;
		gap: var(--space-small);
		font-size: var(--typography--fontSize-base);

		dt {
			color: var(--color-text--secondary);
		}
		dd {
			color: var(--color-text);
		}
	}

	.file-panel__usage {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.file-panel__usage-title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
	}
	.file-panel__usage-empty,
	.file-panel__usage-more {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.file-panel__group {
		margin-top: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.file-panel__rows {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		list-style: none;
	}
	.file-panel__row {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border-radius: var(--radius-base);
		color: inherit;
		text-decoration: none;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
		&--plain:hover {
			background: transparent;
		}
	}
	.file-panel__row-main {
		display: flex;
		flex: 1 1 auto;
		flex-direction: column;
		min-width: 0;
	}
	.file-panel__row-title {
		color: var(--color-heading);
		font-weight: 600;
	}
	.file-panel__row-context,
	.file-panel__row-role {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.file-panel__row-meta {
		display: flex;
		flex: 0 0 auto;
		align-items: center;
		gap: var(--space-smaller);
	}
	.file-panel__row-lock {
		display: inline-flex;
		align-items: center;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 14px;
			height: 14px;
		}
	}
	// Read aloud beside the padlock; sighted users get the same words as a hover title.
	.file-panel__row-lock-text {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
	}
	.file-panel__row-chevron {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
</style>
