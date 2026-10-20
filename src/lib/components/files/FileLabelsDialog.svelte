<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import TagSelect from '$lib/components/ui/TagSelect.svelte';
	import tagIcon from '@tabler/icons/outline/tag.svg?raw';
	import tagsIcon from '@tabler/icons/outline/tags.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import {
		createFileLabel,
		deleteFileLabel,
		fetchFileLabels,
		fileLabelsKey,
		renameFileLabel,
		type FileLabel
	} from '$lib/files/api';

	// The organization's one photo label list (behavior contract, Part 7B). Only files.manage holders reach
	// this; the server re-checks every write. Photos point at a label rather than copying its name, so a
	// rename shows everywhere at once and a removal takes the label off every photo that had it.
	let { open, onClose }: { open: boolean; onClose: () => void } = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const uid = $props.id();

	const labelsQuery = createQuery(() => ({
		queryKey: fileLabelsKey,
		queryFn: fetchFileLabels,
		enabled: open
	}));
	const labels = $derived(labelsQuery.data ?? []);

	let newName = $state('');
	let editingId = $state<string | null>(null);
	let editName = $state('');
	let removing = $state<FileLabel | null>(null);
	let busy = $state(false);
	let error = $state('');

	// A label's name shows on photo details, library tiles and work report editors, so each is refetched
	// after a change; a removed label also empties the rail's view of it.
	function refresh() {
		void queryClient.invalidateQueries({ queryKey: fileLabelsKey });
		void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
		void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
		void queryClient.invalidateQueries({ queryKey: ['jobs', 'report'] });
	}

	async function run(action: () => Promise<unknown>, done: () => void) {
		if (busy) return;
		busy = true;
		error = '';
		try {
			await action();
			refresh();
			done();
		} catch (actionError) {
			error = actionError instanceof Error ? actionError.message : 'That did not save.';
		} finally {
			busy = false;
		}
	}

	function add() {
		const name = newName.trim();
		if (!name) return;
		void run(
			() => createFileLabel(name),
			() => {
				newName = '';
				toast.success(`Label "${name}" added`);
			}
		);
	}

	function startEdit(label: FileLabel) {
		editingId = label.id;
		editName = label.name;
		error = '';
	}

	function saveEdit() {
		const id = editingId;
		const name = editName.trim();
		if (!id || !name) return;
		void run(
			() => renameFileLabel(id, name),
			() => {
				editingId = null;
				toast.success('Label renamed');
			}
		);
	}

	function confirmRemove() {
		const label = removing;
		if (!label) return;
		void run(
			() => deleteFileLabel(label.id),
			() => {
				removing = null;
				toast.success(`Label "${label.name}" removed`);
			}
		);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title="Photo labels"
	icon={tagIcon}
	iconTone="inactive"
	size="small"
	initialFocusId={`${uid}-new`}
	onClose={() => {
		editingId = null;
		error = '';
		onClose();
	}}
>
	<div class="file-labels">
		<p class="file-labels__intro">
			Your team picks from these when they label a photo, like Before, After or Damage.
		</p>

		<form
			class="file-labels__add"
			onsubmit={(event) => {
				event.preventDefault();
				add();
			}}
		>
			<Input
				id={`${uid}-new`}
				label="New label"
				placeholder="e.g. Kitchen"
				maxlength={40}
				bind:value={newName}
				disabled={busy}
			/>
			<Button
				type="submit"
				size="small"
				loading={busy && !editingId && !removing}
				disabled={busy || !newName.trim()}>{@html plusIcon}Add</Button
			>
		</form>

		{#if error && !removing}<p class="file-labels__error" role="alert">{error}</p>{/if}

		{#if labelsQuery.isPending}
			<LoadingSkeleton variant="text" label="Loading labels" rows={4} />
		{:else if labelsQuery.isError}
			<ErrorState
				description="Your labels could not be loaded."
				retry={() => labelsQuery.refetch()}
			/>
		{:else if labels.length === 0}
			<div class="file-labels__empty">
				<span aria-hidden="true">{@html tagsIcon}</span><strong>No labels yet</strong><span
					>Add your first one above.</span
				>
			</div>
		{:else}
			<ul class="file-labels__list">
				{#each labels as label (label.id)}
					<li class="file-labels__row">
						{#if editingId === label.id}
							<!-- The pencil that opened this is gone, so the cursor moves into the box it became. -->
							<form
								class="file-labels__edit"
								{@attach (form) => form.querySelector('input')?.focus()}
								onsubmit={(event) => {
									event.preventDefault();
									saveEdit();
								}}
							>
								<Input
									id={`${uid}-edit-${label.id}`}
									label={`Rename ${label.name}`}
									maxlength={40}
									bind:value={editName}
									disabled={busy}
								/>
								<div class="file-labels__edit-actions">
									<Button
										variant="secondary"
										variation="subtle"
										size="small"
										disabled={busy}
										onclick={() => (editingId = null)}>Cancel</Button
									>
									<Button type="submit" size="small" loading={busy} disabled={!editName.trim()}
										>Save</Button
									>
								</div>
							</form>
						{:else}
							<span class="file-labels__name">
								<TagSelect
									tagIds={[label.id]}
									catalog={[label]}
									noun="label"
									searchId={`${uid}-view-${label.id}`}
									readonly
								/>
							</span>
							<Button
								variant="secondary"
								size="small"
								iconOnly
								label={`Rename ${label.name}`}
								disabled={busy}
								onclick={() => startEdit(label)}
							>
								{@html pencilIcon}
							</Button>
							<Button
								variant="secondary"
								size="small"
								variation="destructive"
								iconOnly
								label={`Remove ${label.name}`}
								disabled={busy}
								onclick={() => {
									error = '';
									removing = label;
								}}
							>
								{@html trashIcon}
							</Button>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</div>
</Dialog>

{#if removing}
	<ConfirmDialog
		open={Boolean(removing)}
		title="Remove label"
		icon={trashIcon}
		confirmLabel="Remove label"
		destructive
		loading={busy}
		onConfirm={confirmRemove}
		onClose={() => (removing = null)}
	>
		<p>
			This takes the label off every photo that has it. The photos themselves stay exactly as they
			are.
		</p>
		{#if error}<p class="file-labels__error" role="alert">{error}</p>{/if}
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.file-labels {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__intro,
		&__empty {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__add {
			display: flex;
			align-items: flex-end;
			gap: var(--space-small);

			:global(.input) {
				flex: 1 1 auto;
			}
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__list {
			display: flex;
			max-height: 320px;
			flex-direction: column;
			overflow-y: auto;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			min-height: 44px;
			padding: var(--space-smaller) var(--space-small);
			border-bottom: var(--border-base) solid var(--color-border);

			&:last-child {
				border-bottom: 0;
			}
		}

		&__name {
			flex: 1 1 auto;
			min-width: 0;
		}
		&__edit {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-small) 0;
		}

		&__edit-actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	.file-labels__intro {
		font-size: var(--typography--fontSize-base);
		line-height: 1.5;
	}
	.file-labels__row {
		padding: 10px 0;
		gap: 6px;
	}
	.file-labels__empty {
		display: grid;
		justify-items: center;
		gap: var(--space-small);
		padding: var(--space-large);
		background: var(--color-surface--background--subtle);
		border: 1.5px dashed var(--color-border--interactive--hover);
		border-radius: var(--radius-base);
		strong {
			font-size: var(--typography--fontSize-label);
			color: var(--color-heading);
		}
		:global(svg) {
			width: 22px;
			height: 22px;
			color: var(--color-icon--secondary);
		}
	}
</style>
