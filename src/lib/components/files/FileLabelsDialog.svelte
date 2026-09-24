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

	// A label's name shows on photo details everywhere, so every open detail is refetched after a change.
	function refresh() {
		void queryClient.invalidateQueries({ queryKey: fileLabelsKey });
		void queryClient.invalidateQueries({ queryKey: ['files', 'detail'] });
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
			/>
			<Button
				type="submit"
				size="small"
				loading={busy && !editingId && !removing}
				disabled={!newName.trim()}>Add</Button
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
			<p class="file-labels__empty">No labels yet. Add your first one above.</p>
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
								/>
								<div class="file-labels__edit-actions">
									<Button
										variant="secondary"
										variation="subtle"
										size="small"
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
							<button
								type="button"
								class="file-labels__icon"
								aria-label={`Rename ${label.name}`}
								onclick={() => startEdit(label)}
							>
								{@html pencilIcon}
							</button>
							<button
								type="button"
								class="file-labels__icon file-labels__icon--danger"
								aria-label={`Remove ${label.name}`}
								onclick={() => {
									error = '';
									removing = label;
								}}
							>
								{@html trashIcon}
							</button>
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
		title={`Remove the "${removing.name}" label?`}
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

		&__icon {
			display: grid;
			width: 32px;
			height: 32px;
			place-items: center;
			border: 0;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: transparent;
			cursor: pointer;

			&:hover {
				color: var(--color-heading);
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
			&--danger:hover {
				color: var(--color-critical);
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}
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
</style>
