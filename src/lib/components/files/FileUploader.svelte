<script lang="ts">
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { finishFileUpload, formatFileSize, startFileUpload } from '$lib/files/api';
	import { MAX_FILE_SIZE_BYTES, allowedTypeFor } from '$lib/files/allowlist';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The upload queue for the File Manager and, later, the record picker. It writes straight away rather
	// than staging: the library is not a form with a Save button, and the two-step handshake underneath it
	// (reserve a File, put the bytes, say they landed) has no meaning half-finished.
	//
	// Nothing here decides whether a file is safe. The browser's checks only save a contractor a 100 MB
	// upload that was always going to be refused; the server checks the claim again before issuing a key,
	// and the processing worker checks the bytes themselves before anything becomes usable.
	let {
		originType = 'file_manager',
		originId = null,
		folderId = null,
		onUploaded
	}: {
		/** Where these files enter UCRM. The library's own uploads are `file_manager` with no record. */
		originType?: string;
		originId?: string | null;
		/** The folder new uploads land in. The library passes whichever folder is open. */
		folderId?: string | null;
		/** Called once per file that reached storage, so the caller can refresh what it is showing. */
		onUploaded?: (fileId: string) => void;
	} = $props();

	type QueuedUpload = {
		key: string;
		name: string;
		sizeBytes: number;
		status: 'waiting' | 'uploading' | 'checking' | 'error';
		progress: number;
		error: string;
		/** A file worth trying again. A refused type or an oversized one is not — it has to be swapped. */
		retryable: boolean;
		file: File;
	};

	let queue = $state<QueuedUpload[]>([]);
	/** How many uploads are in flight. Bounds the pool below without re-deriving it from the queue. */
	let running = $state(0);

	// Three at a time. Enough to keep a broadband connection busy, few enough that a phone on site is not
	// splitting its upstream eight ways and finishing nothing. The contract asks for bounded concurrency;
	// this is where that bound lives.
	const MAX_IN_FLIGHT = 3;

	const active = $derived(queue.filter((item) => item.status !== 'error'));
	const failed = $derived(queue.filter((item) => item.status === 'error'));

	// Queue items live inside a `$state` array, so they are only reactive when reached through it. Patching
	// by key rather than holding a reference is what keeps a progress bar actually moving.
	function patch(key: string, changes: Partial<QueuedUpload>) {
		queue = queue.map((item) => (item.key === key ? { ...item, ...changes } : item));
	}

	function drop(key: string) {
		queue = queue.filter((item) => item.key !== key);
	}

	export function addFiles(fileList: FileList | File[] | null) {
		if (!fileList) return;
		for (const file of Array.from(fileList)) {
			const wrongType = !allowedTypeFor(file.name);
			const tooBig = file.size > MAX_FILE_SIZE_BYTES;
			const empty = file.size === 0;
			queue.push({
				// Two files picked in the same millisecond with the same name are still two uploads.
				key: `${file.name}-${file.size}-${Date.now()}-${Math.random()}`,
				name: file.name,
				sizeBytes: file.size,
				status: wrongType || tooBig || empty ? 'error' : 'waiting',
				progress: 0,
				error: wrongType
					? 'That kind of file cannot be added to the file library.'
					: tooBig
						? 'Files can be up to 100 MB.'
						: empty
							? 'That file is empty.'
							: '',
				retryable: !wrongType && !tooBig && !empty,
				file
			});
		}
		void pump();
	}

	// Starts as many waiting uploads as the pool allows, then lets each finished one call back in. A plain
	// loop over Promise.all would run the whole batch at once, which is the thing the bound exists to stop.
	async function pump() {
		while (running < MAX_IN_FLIGHT) {
			const next = queue.find((item) => item.status === 'waiting');
			if (!next) return;
			// Claimed before the first await, so a second pump() cannot pick up the same file. This is the
			// duplicate-submit protection: one item, one upload, however often this is re-entered.
			patch(next.key, { status: 'uploading', progress: 0, error: '' });
			running += 1;
			void uploadOne(next).finally(() => {
				running -= 1;
				void pump();
			});
		}
	}

	async function uploadOne(item: QueuedUpload) {
		try {
			const started = await startFileUpload(item.file, { originType, originId, folderId });

			// Only when the bar would actually move. Each patch rebuilds the queue array and everything
			// derived from it, and the browser reports progress far more often than a percentage changes.
			let shownPercent = -1;
			await uploadAttachmentFile(started.upload_url, item.file, (fraction) => {
				const percent = Math.round(fraction * 100);
				if (percent === shownPercent) return;
				shownPercent = percent;
				patch(item.key, { progress: fraction });
			});

			// Saying the bytes landed is what makes the File claimable by the worker. Until the worker has
			// read and scanned them the file is in the library but not usable, and the row says so.
			await finishFileUpload(started.file.id);
			patch(item.key, { status: 'checking', progress: 1 });
			onUploaded?.(started.file.id);

			// It has served its purpose on screen; the file itself is now in the library, where its own row
			// shows whether it is still being checked.
			setTimeout(() => drop(item.key), 2500);
		} catch (error) {
			const message = error instanceof Error ? error.message : 'That file could not be uploaded.';
			// A partial batch keeps the files that made it and says which ones did not, rather than
			// reporting one failure as if the whole upload had gone wrong.
			patch(item.key, { status: 'error', error: message, progress: 0 });
		}
	}

	function retry(item: QueuedUpload) {
		if (!item.retryable) return;
		patch(item.key, { status: 'waiting', error: '', progress: 0 });
		void pump();
	}

	function clearFailed() {
		queue = queue.filter((item) => item.status !== 'error');
	}

	function statusLabel(item: QueuedUpload) {
		if (item.status === 'checking') return 'Uploaded — now being checked';
		if (item.status === 'uploading') return `${Math.round(item.progress * 100)}%`;
		return `${formatFileSize(item.sizeBytes)} · Waiting`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if queue.length > 0}
	<section class="file-uploader" aria-label="Uploads">
		<div class="file-uploader__heading">
			<h2 class="file-uploader__title">
				{#if active.length > 0}
					Uploading {active.length}
					{active.length === 1 ? 'file' : 'files'}
				{:else}
					{failed.length}
					{failed.length === 1 ? 'file did not upload' : 'files did not upload'}
				{/if}
			</h2>
			{#if failed.length > 0 && active.length === 0}
				<button type="button" class="file-uploader__clear" onclick={clearFailed}>Clear</button>
			{/if}
		</div>

		<ul class="file-uploader__list">
			{#each queue as item (item.key)}
				<li class="file-uploader__item" class:file-uploader__item--error={item.status === 'error'}>
					{#if item.status === 'error'}
						<span class="file-uploader__item-icon" aria-hidden="true"
							>{@html alertTriangleIcon}</span
						>
					{/if}
					<div class="file-uploader__item-body">
						<span class="file-uploader__item-name">{item.name}</span>
						{#if item.status === 'error'}
							<span class="file-uploader__item-error">{item.error}</span>
						{:else if item.status === 'uploading'}
							<span
								class="file-uploader__progress"
								role="progressbar"
								aria-label={`Uploading ${item.name}`}
								aria-valuenow={Math.round(item.progress * 100)}
								aria-valuemin="0"
								aria-valuemax="100"
							>
								<span
									class="file-uploader__progress-bar"
									style={`width: ${Math.round(item.progress * 100)}%`}
								></span>
							</span>
						{:else}
							<span class="file-uploader__item-meta">{statusLabel(item)}</span>
						{/if}
					</div>

					{#if item.status === 'uploading'}
						<span class="file-uploader__item-meta">{statusLabel(item)}</span>
					{/if}
					{#if item.status === 'error' && item.retryable}
						<button type="button" class="file-uploader__action" onclick={() => retry(item)}>
							Try again
						</button>
					{/if}
					{#if item.status === 'error'}
						<button
							type="button"
							class="file-uploader__remove"
							aria-label={`Remove ${item.name}`}
							onclick={() => drop(item.key)}
						>
							{@html xIcon}
						</button>
					{/if}
				</li>
			{/each}
		</ul>
	</section>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.file-uploader {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);
	}

	.file-uploader__heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}
	.file-uploader__title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 700;
	}
	.file-uploader__clear,
	.file-uploader__action {
		flex: 0 0 auto;
		border: 0;
		color: var(--color-interactive);
		background: transparent;
		font: inherit;
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		cursor: pointer;

		&:hover {
			text-decoration: underline;
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.file-uploader__list {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		list-style: none;
	}
	.file-uploader__item {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-small);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);

		&--error {
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
		}
	}
	.file-uploader__item-icon {
		display: inline-flex;
		flex: 0 0 auto;

		:global(svg) {
			width: 18px;
			height: 18px;
		}
	}
	.file-uploader__item-body {
		display: flex;
		min-width: 0;
		flex: 1 1 auto;
		flex-direction: column;
		gap: 2px;
	}
	.file-uploader__item-name {
		overflow: hidden;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.file-uploader__item--error .file-uploader__item-name {
		color: inherit;
	}
	.file-uploader__item-meta {
		flex: 0 0 auto;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-smaller);
	}
	.file-uploader__item-error {
		font-size: var(--typography--fontSize-smaller);
	}

	.file-uploader__progress {
		display: block;
		height: 6px;
		overflow: hidden;
		border-radius: var(--radius-large);
		background: var(--color-surface--hover);
	}
	.file-uploader__progress-bar {
		display: block;
		height: 100%;
		background: var(--color-interactive);
		transition: width var(--timing-base) ease-out;
	}

	.file-uploader__remove {
		display: grid;
		width: 20px;
		height: 20px;
		flex: 0 0 auto;
		place-items: center;
		border: 0;
		border-radius: var(--radius-circle);
		color: inherit;
		background: transparent;
		cursor: pointer;

		&:hover {
			background: var(--color-surface--hover);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}
	}
</style>
