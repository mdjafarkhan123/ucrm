<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { activityKey } from '$lib/collaboration/api';
	import FileThumb from './FileThumb.svelte';
	import {
		createFileShare,
		type CreatedFileShare,
		type FileListItem,
		type FileShareDays
	} from '$lib/files/api';

	// "Share with customer" (behavior contract, "How a selected-file share works"). Staff pick exactly one
	// Client and how long the link lasts, see the Files and the Client's name, and only then is a link made.
	// A share is fixed once made -- more files or more time is a new share -- so the second step here only
	// hands out the link; it never edits what was shared.
	//
	// The parent renders this only while sharing, so closing destroys it and every choice resets on its own.
	let {
		files,
		onShared,
		onClose
	}: {
		/** The Files being shared, in the order they will appear to the customer. */
		files: FileListItem[];
		/** The link now exists. The library uses it to clear its ticked files. */
		onShared?: () => void;
		onClose: () => void;
	} = $props();

	const MAX_FILES = 50;
	const queryClient = useQueryClient();
	const toast = getToastManager();

	let clientId = $state('');
	let clientName = $state('');
	let days = $state<string>('30');
	let saving = $state(false);
	let errorMessage = $state('');
	let created = $state<CreatedFileShare | null>(null);
	let copied = $state(false);

	// Checking and Trash are refused by the server as well; saying so here saves a round trip.
	const unshareable = $derived(
		files.filter((file) => file.processing_state !== 'available' || file.trashed_at !== null)
	);
	const tooMany = $derived(files.length > MAX_FILES);
	const canCreate = $derived(
		Boolean(clientId) && files.length > 0 && unshareable.length === 0 && !tooMany && !saving
	);

	const fileWord = $derived(files.length === 1 ? 'file' : 'files');

	function formatDate(value: string) {
		return new Date(value).toLocaleDateString(undefined, {
			month: 'long',
			day: 'numeric',
			year: 'numeric'
		});
	}

	async function submit() {
		if (!canCreate) return;
		saving = true;
		errorMessage = '';
		try {
			created = await createFileShare(
				files.map((file) => file.id),
				clientId,
				Number(days) as FileShareDays
			);
			void queryClient.invalidateQueries({ queryKey: activityKey('client', clientId) });
			onShared?.();
			await copyLink();
		} catch (error) {
			errorMessage = error instanceof Error ? error.message : 'That link could not be made.';
		} finally {
			saving = false;
		}
	}

	async function copyLink() {
		if (!created) return;
		try {
			await navigator.clipboard.writeText(created.url);
			copied = true;
			toast.success('Link copied');
		} catch {
			// Some browsers refuse the clipboard without a fresh click. The link is on screen to copy by hand.
			copied = false;
		}
	}

	function selectLink(event: FocusEvent) {
		(event.currentTarget as HTMLInputElement).select();
	}
</script>

<Dialog open title={created ? 'Link ready' : 'Share with customer'} {onClose}>
	<div class="file-share">
		{#if created}
			<p class="file-share__lead">
				<strong>{created.share.client_name}</strong> can open {created.share.file_count}
				{created.share.file_count === 1 ? 'file' : 'files'} with this link until
				{formatDate(created.share.expires_at)}. Send it to them by email or text.
			</p>
			<div class="file-share__link">
				<label class="file-share__label" for="file-share-url">Customer link</label>
				<div class="file-share__link-row">
					<input
						id="file-share-url"
						class="file-share__url"
						type="text"
						readonly
						value={created.url}
						onfocus={selectLink}
					/>
					<Button variant="primary" onclick={copyLink}>{copied ? 'Copied' : 'Copy link'}</Button>
				</div>
			</div>
			<p class="file-share__hint">
				The customer sees these files under the names they have now. Renaming a file later does not
				change their page.
			</p>
			<div class="file-share__actions">
				<Button variant="secondary" onclick={onClose}>Done</Button>
			</div>
		{:else}
			<!-- ClientPicker renders its own "Client" label. -->
			<ClientPicker
				id="file-share-client"
				required
				placeholder="Search by name or company"
				onSelect={(client) => {
					clientId = client?.id ?? '';
					clientName = client?.display_name ?? '';
				}}
			/>

			<SegmentedControl
				label="Link works for"
				bind:value={days}
				options={[
					{ value: '7', label: '7 days' },
					{ value: '30', label: '30 days' },
					{ value: '90', label: '90 days' }
				]}
			/>

			<section class="file-share__files" aria-labelledby="file-share-files-title">
				<h3 id="file-share-files-title" class="file-share__label">
					{files.length}
					{fileWord}
					{clientName ? `for ${clientName}` : 'to share'}
				</h3>
				<ul class="file-share__list">
					{#each files as file (file.id)}
						<li class="file-share__row">
							<FileThumb
								fileId={file.id}
								displayName={file.display_name}
								mimeType={file.mime_type}
								kind={file.kind}
								processingState={file.processing_state}
								hasThumbnail={file.has_thumbnail}
								size="row"
							/>
							<span class="file-share__name" title={file.display_name}>{file.display_name}</span>
						</li>
					{/each}
				</ul>
			</section>

			{#if tooMany}
				<p class="file-share__error" role="alert">
					A link can hold at most {MAX_FILES} files. Choose fewer, or make a second link.
				</p>
			{:else if unshareable.length > 0}
				<p class="file-share__error" role="alert">
					Files still being checked or in Trash cannot be shared. Take them out of the selection.
				</p>
			{/if}
			<p class="file-share__hint">
				The customer sees only these files, and can download each one. The link cannot be changed
				later — to add files or more time, make a new link.
			</p>
			{#if errorMessage}<p class="file-share__error" role="alert">{errorMessage}</p>{/if}

			<div class="file-share__actions">
				<Button variant="secondary" onclick={onClose} disabled={saving}>Cancel</Button>
				<Button variant="primary" loading={saving} disabled={!canCreate} onclick={submit}>
					Create link
				</Button>
			</div>
		{/if}
	</div>
</Dialog>

<style lang="scss">
	.file-share {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.file-share__lead,
	.file-share__hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.file-share__lead strong {
		color: var(--color-heading);
	}

	.file-share__label {
		margin: 0 0 var(--space-smaller);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
	}

	.file-share__link {
		display: flex;
		flex-direction: column;
	}

	.file-share__link-row {
		display: flex;
		gap: var(--space-small);
	}

	.file-share__url {
		flex: 1;
		min-width: 0;
		padding: var(--space-small) var(--space-base);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
		color: var(--color-heading);
		font: inherit;
		font-size: var(--typography--fontSize-small);

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.file-share__list {
		display: flex;
		flex-direction: column;
		max-height: 32vh;
		margin: 0;
		padding: 0;
		overflow-y: auto;
		list-style: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.file-share__row {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-smaller) var(--space-small);

		& + & {
			border-top: 1px solid var(--color-border);
		}
	}

	.file-share__name {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;
	}

	.file-share__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.file-share__actions {
		display: flex;
		gap: var(--space-small);
		justify-content: flex-end;
	}
</style>
