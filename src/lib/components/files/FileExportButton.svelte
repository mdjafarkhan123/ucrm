<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		downloadFileExport,
		fetchFileExports,
		fileExportsKey,
		formatFileSize,
		requestFileExport
	} from '$lib/files/api';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let starting = $state(false);
	let downloading = $state(false);

	// Owner-only (files.export), so this poll only ever runs for someone who could have started the job.
	// Keeps refetching every 5s while a job is in flight; stops itself the moment it settles, matching the
	// bounded-poll shape used for photo processing (RecordFilesCard) and imports (ImportDoneStep).
	const exportsQuery = createQuery(() => ({
		queryKey: fileExportsKey,
		queryFn: fetchFileExports,
		refetchInterval: (query) => {
			const latest = query.state.data?.[0];
			return latest && (latest.status === 'queued' || latest.status === 'processing')
				? 5000
				: false;
		}
	}));

	const latest = $derived(exportsQuery.data?.[0] ?? null);
	const running = $derived(latest?.status === 'queued' || latest?.status === 'processing');

	function formatDate(value: string) {
		return new Date(value).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}

	async function startExport() {
		if (starting || running) return;
		starting = true;
		try {
			await requestFileExport();
			await queryClient.invalidateQueries({ queryKey: fileExportsKey });
			toast.success('Export started', "We'll email you when your download is ready.");
		} catch (error) {
			toast.error(
				'Could not start that export',
				error instanceof Error ? error.message : undefined
			);
		} finally {
			starting = false;
		}
	}

	async function download() {
		if (!latest || downloading) return;
		downloading = true;
		try {
			await downloadFileExport(latest.id);
		} catch (error) {
			toast.error(
				'Could not download that export',
				error instanceof Error ? error.message : undefined
			);
		} finally {
			downloading = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="file-export">
	<Button
		size="small"
		variant="secondary"
		loading={starting}
		disabled={starting || running}
		onclick={startExport}
	>
		{running ? 'Preparing export…' : 'Export everything'}
	</Button>

	{#if latest?.status === 'available'}
		<Button size="small" variant="tertiary" loading={downloading} onclick={download}>
			<span class="file-export__button-icon" aria-hidden="true">{@html downloadIcon}</span>
			Download
		</Button>
		<span class="file-export__note">
			{formatFileSize(latest.total_bytes)} · {latest.file_count}
			{latest.file_count === 1 ? 'file' : 'files'} · ready {formatDate(
				latest.completed_at ?? latest.requested_at
			)}
		</span>
	{:else if latest?.status === 'failed'}
		<span class="file-export__note file-export__note--error">
			Your last export failed. {latest.error ?? 'Try again.'}
		</span>
	{/if}
</div>

<style lang="scss">
	.file-export {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
	}
	.file-export__button-icon {
		display: inline-flex;
		margin-right: var(--space-smaller);

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}
	.file-export__note {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
	.file-export__note--error {
		color: var(--color-critical);
	}
</style>
