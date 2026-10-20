<script lang="ts">
	import { uploadAttachmentFile } from '$lib/collaboration/api';
	import { finishFileUpload, formatFileSize, startFileUpload } from '$lib/files/api';
	import { MAX_FILE_SIZE_BYTES, allowedTypeFor } from '$lib/files/allowlist';
	import Button from '$lib/components/ui/Button.svelte';
	import cloudIcon from '@tabler/icons/outline/cloud-upload.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import refreshIcon from '@tabler/icons/outline/refresh.svg?raw';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
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
	let completed = $state(0);
	const total = $derived(completed + queue.length);
	const batchProgress = $derived(
		total
			? (completed +
					queue.reduce(
						(n, item) =>
							n +
							(item.status === 'checking' ? 1 : item.status === 'uploading' ? item.progress : 0),
						0
					)) /
					total
			: 0
	);
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
		if (!queue.length) completed = 0;
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
			setTimeout(() => {
				completed += 1;
				drop(item.key);
			}, 2500);
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
		if (item.status === 'uploading')
			return `${formatFileSize(item.sizeBytes * item.progress)} of ${formatFileSize(item.sizeBytes)}`;
		return `${formatFileSize(item.sizeBytes)} · Waiting`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if queue.length}
	<section class="file-uploader" aria-label="Uploads">
		<div class="file-uploader__heading">
			<span
				class={[
					'file-uploader__heading-icon',
					!active.length && 'file-uploader__heading-icon--error'
				]}
				aria-hidden="true">{@html active.length ? cloudIcon : alertTriangleIcon}</span
			>
			<div class="file-uploader__heading-body">
				<h2 class="file-uploader__title">
					{active.length
						? `Uploading ${total} ${total === 1 ? 'file' : 'files'}`
						: `${failed.length} ${failed.length === 1 ? 'file did' : 'files did'} not upload`}
				</h2>
				<p class="file-uploader__summary">
					{active.length
						? `${completed + queue.filter((item) => item.status === 'checking').length} of ${total} uploaded${failed.length ? ` · ${failed.length} did not upload` : ''}`
						: 'Try again, or clear them'}
				</p>
			</div>
			{#if failed.length && !active.length}<Button
					variant="quiet"
					size="small"
					onclick={clearFailed}>Clear</Button
				>{/if}
		</div>
		{#if active.length}<div class="file-uploader__batch">
				<div
					class="file-uploader__track"
					role="progressbar"
					aria-label="Batch upload progress"
					aria-valuenow={Math.round(batchProgress * 100)}
					aria-valuemin="0"
					aria-valuemax="100"
				>
					<span style:width={`${batchProgress * 100}%`}></span>
				</div>
			</div>{/if}
		<ul class="file-uploader__list">
			{#each queue as item (item.key)}
				<li
					class={['file-uploader__item', item.status === 'error' && 'file-uploader__item--error']}
				>
					<span
						class="file-uploader__ring"
						style:--progress={`${item.status === 'uploading' ? item.progress * 360 : 0}deg`}
						><span class="file-uploader__item-icon" aria-hidden="true"
							>{@html item.status === 'error' ? alertTriangleIcon : fileIcon}</span
						></span
					>
					<div class="file-uploader__item-body">
						<span class="file-uploader__item-name" title={item.name}>{item.name}</span><span
							class={item.status === 'error'
								? 'file-uploader__item-error'
								: 'file-uploader__item-meta'}
							>{item.status === 'error' ? item.error : statusLabel(item)}</span
						>
					</div>
					<StatusBadge
						status={item.status === 'error'
							? 'critical'
							: item.status === 'checking'
								? 'warning'
								: item.status === 'uploading'
									? 'informative'
									: 'inactive'}
						>{#if item.status === 'uploading'}<span
								class="file-uploader__spinner"
								aria-hidden="true"
							></span>{/if}{item.status === 'error'
							? 'Failed'
							: item.status === 'checking'
								? 'Checking'
								: item.status === 'uploading'
									? `${Math.round(item.progress * 100)}%`
									: 'Waiting'}</StatusBadge
					>
					{#if item.status === 'error' && item.retryable}<Button
							variant="secondary"
							size="small"
							onclick={() => retry(item)}
							><span class="file-uploader__retry-icon" aria-hidden="true">{@html refreshIcon}</span
							>Try again</Button
						>{/if}
					{#if item.status === 'error'}<Button
							variant="quiet"
							size="small"
							iconOnly
							label={`Remove ${item.name}`}
							onclick={() => drop(item.key)}>{@html xIcon}</Button
						>{/if}
				</li>{/each}
		</ul>
	</section>{/if}

<!-- eslint-enable svelte/no-at-html-tags -->
<style lang="scss">
	.file-uploader {
		overflow: hidden;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		&__heading {
			display: flex;
			align-items: center;
			gap: 12px;
			padding: 16px 16px 12px 20px;
		}
		&__heading-icon {
			display: grid;
			place-items: center;
			flex: 0 0 32px;
			height: 32px;
			border-radius: var(--radius-base);
			color: var(--color-inactive);
			background: var(--color-inactive--surface);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
			&--error {
				color: var(--color-critical);
				background: var(--color-critical--surface);
			}
		}
		&__heading-body {
			flex: 1;
			min-width: 0;
		}
		&__title {
			margin: 0;
			font-size: 16px;
			font-weight: 600;
			color: var(--color-heading);
		}
		&__summary {
			margin: 4px 0 0;
			font-size: var(--typography--fontSize-small);
			color: var(--color-text--secondary);
		}
		&__batch {
			padding: 0 20px 16px;
		}
		&__track {
			height: 8px;
			overflow: hidden;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			span {
				display: block;
				height: 100%;
				background: var(--color-interactive);
				transition: width var(--timing-base);
			}
		}
		&__list {
			list-style: none;
			padding: 0;
			margin: 0;
		}
		&__item {
			display: flex;
			align-items: center;
			gap: 14px;
			padding: 12px 16px 12px 20px;
			border-top: 1px solid var(--color-border);
		}
		&__ring {
			display: grid;
			place-items: center;
			flex: 0 0 44px;
			height: 44px;
			border-radius: var(--radius-circle);
			background: conic-gradient(
				var(--color-interactive) var(--progress),
				var(--color-surface--background) 0
			);
			position: relative;
			&::before {
				content: '';
				position: absolute;
				inset: 4px;
				border-radius: inherit;
				background: var(--color-surface);
			}
		}
		&__item-icon {
			position: relative;
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			color: var(--color-icon);
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__item--error &__item-icon {
			color: var(--color-critical);
			background: var(--color-critical--surface);
		}
		&__item-body {
			flex: 1;
			min-width: 0;
			display: flex;
			flex-direction: column;
			gap: 4px;
		}
		&__item-name {
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__item-meta {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__item-error {
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}
		&__retry-icon {
			display: flex;
			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
		&__spinner {
			display: inline-block;
			vertical-align: middle;
			width: 12px;
			height: 12px;
			border: 2px solid currentColor;
			border-right-color: transparent;
			border-radius: var(--radius-circle);
			animation: upload-spin var(--timing-loading) linear infinite;
		}
		@media (max-width: 600px) {
			&__item {
				flex-wrap: wrap;
				gap: 8px;
			}
			&__item-body {
				min-width: 140px;
			}
		}
	}
	@keyframes upload-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
