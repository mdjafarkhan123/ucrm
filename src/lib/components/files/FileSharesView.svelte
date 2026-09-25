<script lang="ts">
	import { createInfiniteQuery, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import ListLoadMore from '$lib/components/data-display/ListLoadMore.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import SidePanel from '$lib/components/layout/SidePanel.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { activityKey } from '$lib/collaboration/api';
	import FileThumb from './FileThumb.svelte';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import {
		fetchFileShare,
		fetchFileShares,
		fileShareDetailKey,
		fileShareState,
		fileSharesKey,
		turnOffFileShare,
		type FileShareListItem,
		type FileShareListPage,
		type FileShareState
	} from '$lib/files/api';

	// "Shared with customers" in the File Manager rail (behavior contract, "How a selected-file share works"):
	// every link the business has made, newest first -- who it went to, how many files, when it was made and
	// ends, whether the customer has opened it -- with Turn off. Opening a row lists that link's files.
	//
	// The raw link is never stored, so nothing here can show or copy it again. A customer who needs it back
	// gets a new link from the library.

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const sharesQuery = createInfiniteQuery(() => ({
		queryKey: fileSharesKey,
		queryFn: ({ pageParam }: { pageParam: string | undefined }) => fetchFileShares(pageParam),
		initialPageParam: undefined as string | undefined,
		getNextPageParam: (lastPage: FileShareListPage) => lastPage.next_cursor ?? undefined
	}));
	const shares = $derived(sharesQuery.data?.pages.flatMap((page) => page.shares) ?? []);

	let openShareId = $state('');
	let panelOpen = $state(false);
	let turnOffTarget = $state<{ id: string; client_id: string; client_name: string | null } | null>(
		null
	);
	let turningOff = $state(false);
	let turnOffError = $state('');

	// Off until a row is opened. Hovering or focusing a row warms it, so the click normally paints from cache;
	// a click that beats the fetch shows the panel's skeleton.
	const detailQuery = createQuery(() => ({
		queryKey: fileShareDetailKey(openShareId),
		queryFn: () => fetchFileShare(openShareId),
		enabled: Boolean(openShareId)
	}));
	const openRow = $derived(shares.find((share) => share.id === openShareId) ?? null);
	const detail = $derived(detailQuery.data);

	function prefetchShare(share: FileShareListItem) {
		void queryClient.prefetchQuery({
			queryKey: fileShareDetailKey(share.id),
			queryFn: () => fetchFileShare(share.id)
		});
	}

	function openShare(share: FileShareListItem) {
		openShareId = share.id;
		panelOpen = true;
	}

	const columns: DataTableColumn[] = [
		{ key: 'client', label: 'Client' },
		{ key: 'files', label: 'Files' },
		{ key: 'sent', label: 'Sent' },
		{ key: 'ends', label: 'Link ends' },
		{ key: 'opened', label: 'Opened' },
		{ key: 'status', label: 'Status' }
	];

	const STATE_BADGE: Record<
		FileShareState,
		{ label: string; status: 'success' | 'inactive' | 'warning' }
	> = {
		active: { label: 'Active', status: 'success' },
		expired: { label: 'Expired', status: 'inactive' },
		off: { label: 'Turned off', status: 'warning' }
	};

	function formatDate(value: string) {
		return new Date(value).toLocaleDateString(undefined, {
			month: 'short',
			day: 'numeric',
			year: 'numeric'
		});
	}

	function openedLabel(share: { first_viewed_at: string | null; view_count: number }) {
		if (!share.first_viewed_at) return 'Not yet';
		const times = share.view_count === 1 ? 'once' : `${share.view_count} times`;
		return `${formatDate(share.first_viewed_at)} · ${times}`;
	}

	function endsLabel(share: { expires_at: string; revoked_at: string | null }) {
		if (share.revoked_at) return `Turned off ${formatDate(share.revoked_at)}`;
		return formatDate(share.expires_at);
	}

	function clientLabel(name: string | null) {
		return name ?? 'A client you cannot view';
	}

	async function confirmTurnOff() {
		if (!turnOffTarget || turningOff) return;
		turningOff = true;
		turnOffError = '';
		const target = turnOffTarget;
		try {
			await turnOffFileShare(target.id);
			// The list, this link's panel, and every file's "Shared with" line and Trash count can all have
			// changed; the Client's history has a new entry.
			void queryClient.invalidateQueries({ queryKey: ['files', 'shares'] });
			void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
			void queryClient.invalidateQueries({ queryKey: activityKey('client', target.client_id) });
			turnOffTarget = null;
			toast.success('Link turned off');
		} catch (error) {
			turnOffError = error instanceof Error ? error.message : 'That link could not be turned off.';
		} finally {
			turningOff = false;
		}
	}

	function askTurnOff(share: { id: string; client_id: string; client_name: string | null }) {
		turnOffError = '';
		turnOffTarget = {
			id: share.id,
			client_id: share.client_id,
			client_name: share.client_name
		};
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if sharesQuery.isPending}
	<LoadingSkeleton variant="card" label="Loading shared links" rows={4} />
{:else if sharesQuery.isError}
	<ErrorState
		description="Your shared links could not be loaded. Try again."
		retry={() => sharesQuery.refetch()}
	/>
{:else if shares.length === 0}
	<EmptyState
		icon={linkIcon}
		title="No shared links"
		description="Choose files in your library and press Share with customer to send a client a link to them."
	/>
{:else}
	<p class="file-shares__intro">
		Every link you have sent a client. Turning one off stops it straight away; the client sees your
		phone and email instead of the files.
	</p>
	<DataTable
		{columns}
		items={shares}
		rowId={(share) => share.id}
		caption="Links shared with customers"
		onRowActivate={openShare}
	>
		{#snippet row(share)}
			{@const state = fileShareState(share)}
			<th scope="row">
				<button
					type="button"
					class="file-shares__open"
					onclick={() => openShare(share)}
					onmouseenter={() => prefetchShare(share)}
					onfocus={() => prefetchShare(share)}
				>
					{clientLabel(share.client_name)}
				</button>
			</th>
			<td>{share.file_count} {share.file_count === 1 ? 'file' : 'files'}</td>
			<td>
				<span class="file-shares__stack">
					<span>{formatDate(share.issued_at)}</span>
					{#if share.issued_by_name}
						<span class="file-shares__muted">by {share.issued_by_name}</span>
					{/if}
				</span>
			</td>
			<td>{endsLabel(share)}</td>
			<td class:file-shares__muted={!share.first_viewed_at}>{openedLabel(share)}</td>
			<td>
				<Badge size="small" status={STATE_BADGE[state].status}>{STATE_BADGE[state].label}</Badge>
			</td>
		{/snippet}
		{#snippet rowActions(share)}
			{#if fileShareState(share) === 'active'}
				<Button
					variant="secondary"
					variation="subtle"
					size="small"
					class="file-shares__turn-off"
					onclick={() => askTurnOff(share)}>Turn off</Button
				>
			{/if}
		{/snippet}
		{#snippet footer()}
			<ListLoadMore
				hasNextPage={sharesQuery.hasNextPage}
				isFetchingNextPage={sharesQuery.isFetchingNextPage}
				onLoadMore={() => sharesQuery.fetchNextPage()}
				endLabel="That is every link you have shared."
			/>
		{/snippet}
	</DataTable>
{/if}

<SidePanel
	open={panelOpen}
	title={openRow ? `Link for ${clientLabel(openRow.client_name)}` : 'Shared link'}
	subtitle={openRow
		? `${openRow.file_count} ${openRow.file_count === 1 ? 'file' : 'files'} · sent ${formatDate(openRow.issued_at)}`
		: undefined}
	onClose={() => (panelOpen = false)}
>
	{#if !detail}
		{#if detailQuery.isError}
			<ErrorState
				description="This link could not be loaded."
				retry={() => detailQuery.refetch()}
			/>
		{:else}
			<LoadingSkeleton variant="card" label="Loading shared link" />
		{/if}
	{:else}
		{@const state = fileShareState(detail)}
		{@const hiddenCount = detail.files.filter((item) => !item.file || item.file.trashed_at).length}
		<div class="file-shares__panel-status">
			<Badge status={STATE_BADGE[state].status}>{STATE_BADGE[state].label}</Badge>
			{#if state === 'active'}
				<Button variant="secondary" size="small" onclick={() => askTurnOff(detail)}>Turn off</Button
				>
			{/if}
		</div>

		<dl class="file-shares__facts">
			<div class="file-shares__fact">
				<dt>Client</dt>
				<dd>
					{#if detail.client_name}
						<a
							class="file-shares__client-link"
							href={resolve('/(app)/clients/[id=uuid]', { id: detail.client_id })}
							>{detail.client_name}</a
						>
					{:else}
						{clientLabel(null)}
					{/if}
				</dd>
			</div>
			<div class="file-shares__fact">
				<dt>Sent</dt>
				<dd>{formatDate(detail.issued_at)}</dd>
			</div>
			<div class="file-shares__fact">
				<dt>{state === 'active' ? 'Works until' : 'Ended'}</dt>
				<dd>
					{state === 'off' && detail.revoked_at
						? `${formatDate(detail.revoked_at)} (turned off)`
						: formatDate(detail.expires_at)}
				</dd>
			</div>
			<div class="file-shares__fact">
				<dt>Opened</dt>
				<dd>
					{openedLabel(detail)}{detail.last_viewed_at && detail.view_count > 1
						? ` · last ${formatDate(detail.last_viewed_at)}`
						: ''}
				</dd>
			</div>
		</dl>

		<section class="file-shares__files" aria-labelledby="file-shares-files-title">
			<h3 id="file-shares-files-title" class="file-shares__files-title">Files on this link</h3>
			{#if state === 'active' && hiddenCount > 0}
				<p class="file-shares__muted">
					{hiddenCount === 1 ? '1 file is' : `${hiddenCount} files are`} no longer on the customer's page
					because {hiddenCount === 1 ? 'it was' : 'they were'} moved to Trash.
				</p>
			{/if}
			<ul class="file-shares__list">
				{#each detail.files as item (item.file_id)}
					<li
						class="file-shares__row"
						class:file-shares__row--gone={!item.file || item.file.trashed_at}
					>
						{#if item.file}
							<FileThumb
								fileId={item.file.id}
								displayName={item.file.display_name}
								mimeType={item.file.mime_type}
								kind={item.file.kind}
								processingState={item.file.processing_state}
								hasThumbnail={item.file.has_thumbnail}
								size="row"
							/>
						{/if}
						<span class="file-shares__row-text">
							<span class="file-shares__name" title={item.shared_name}>{item.shared_name}</span>
							{#if !item.file}
								<span class="file-shares__muted">You cannot open this file</span>
							{:else if item.file.trashed_at}
								<span class="file-shares__muted">In Trash · hidden from the customer</span>
							{:else if item.file.display_name !== item.shared_name}
								<span class="file-shares__muted">Now called {item.file.display_name}</span>
							{/if}
						</span>
					</li>
				{/each}
			</ul>
			<p class="file-shares__muted">
				The customer sees each file under the name it had when you shared it.
			</p>
		</section>
	{/if}
</SidePanel>

<ConfirmDialog
	open={turnOffTarget !== null}
	title="Turn off this link?"
	tone="critical"
	destructive
	confirmLabel="Turn off link"
	loading={turningOff}
	onConfirm={confirmTurnOff}
	onClose={() => (turnOffTarget = null)}
>
	<p>
		{turnOffTarget?.client_name ?? 'The client'} will no longer be able to open these files. The link
		will show your business phone and email instead.
	</p>
	<p>This cannot be undone. To share the files again, make a new link.</p>
	{#if turnOffError}<p class="file-shares__error" role="alert">{turnOffError}</p>{/if}
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.file-shares__intro {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.file-shares__open {
		padding: 0;
		border: none;
		background: transparent;
		color: var(--color-heading);
		font: inherit;
		font-weight: 600;
		text-align: start;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
			border-radius: var(--radius-small);
		}
	}

	// Button's own class, so it is reached from here with :global.
	:global(.file-shares__turn-off) {
		white-space: nowrap;
	}

	.file-shares__stack {
		display: flex;
		flex-direction: column;
	}

	.file-shares__muted {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.file-shares__error {
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.file-shares__panel-status {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}

	.file-shares__facts {
		display: grid;
		gap: var(--space-small);
	}
	.file-shares__fact {
		display: grid;
		grid-template-columns: 110px 1fr;
		gap: var(--space-small);

		dt {
			color: var(--color-text--secondary);
		}
		dd {
			color: var(--color-text);
		}
	}

	.file-shares__client-link {
		color: var(--color-interactive);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
			border-radius: var(--radius-small);
		}
	}

	.file-shares__files {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}
	.file-shares__files-title {
		color: var(--color-heading);
		font-size: var(--typography--fontSize-large);
		font-weight: 700;
	}

	.file-shares__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
	.file-shares__row {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		padding: var(--space-smaller) var(--space-small);

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		&--gone {
			opacity: 0.6;
		}
	}
	.file-shares__row-text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.file-shares__name {
		overflow: hidden;
		color: var(--color-heading);
		font-weight: 500;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
</style>
