<script lang="ts">
	import { tick } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		SavedFilterWriteError,
		deleteSavedFilter,
		savedFiltersKey,
		updateSavedFilter,
		type SavedFilter
	} from '$lib/pipeline/api';
	import { SAVED_FILTER_NAME_MAX } from '$lib/pipeline/filters';

	// Rename and delete the saved filters this person may change: their own, and — for owners and
	// administrators — the team's. One row at a time is being renamed or deleted, so each answer lands
	// on the row it belongs to.
	let {
		open,
		filters,
		onClose
	}: {
		open: boolean;
		filters: SavedFilter[];
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let renamingId = $state<string | null>(null);
	let deletingId = $state<string | null>(null);
	let draftName = $state('');
	let rowError = $state('');
	let busy = $state(false);

	const editable = $derived(filters.filter((filter) => filter.can_edit));

	$effect(() => {
		if (!open) return;
		renamingId = null;
		deletingId = null;
		rowError = '';
	});

	function startRename(filter: SavedFilter) {
		renamingId = filter.id;
		deletingId = null;
		draftName = filter.name;
		rowError = '';
		// The field replaces the button that was just pressed, so the keyboard follows it there.
		void tick().then(() => document.getElementById(`rename-filter-${filter.id}`)?.focus());
	}

	function startDelete(filter: SavedFilter) {
		deletingId = filter.id;
		renamingId = null;
		rowError = '';
	}

	function cancelRow() {
		renamingId = null;
		deletingId = null;
		rowError = '';
	}

	async function rename(filter: SavedFilter) {
		if (busy) return;
		if (!draftName.trim()) {
			rowError = 'Give the filter a name.';
			return;
		}
		busy = true;
		rowError = '';
		try {
			await updateSavedFilter(filter.id, { name: draftName });
			await queryClient.invalidateQueries({ queryKey: savedFiltersKey });
			toast.success('Filter renamed');
			renamingId = null;
		} catch (thrown) {
			rowError =
				thrown instanceof SavedFilterWriteError || thrown instanceof Error
					? thrown.message
					: 'That filter could not be renamed.';
		} finally {
			busy = false;
		}
	}

	async function remove(filter: SavedFilter) {
		if (busy) return;
		busy = true;
		rowError = '';
		try {
			await deleteSavedFilter(filter.id);
			await queryClient.invalidateQueries({ queryKey: savedFiltersKey });
			toast.success('Filter deleted');
			deletingId = null;
		} catch (thrown) {
			rowError = thrown instanceof Error ? thrown.message : 'That filter could not be deleted.';
		} finally {
			busy = false;
		}
	}
</script>

<Dialog {open} title="Manage saved filters" onClose={busy ? () => {} : onClose}>
	{#if editable.length === 0}
		<p class="manage-filters__empty">You have no saved filters to change.</p>
	{:else}
		<ul class="manage-filters">
			{#each editable as filter (filter.id)}
				<li class="manage-filters__row">
					{#if renamingId === filter.id}
						<form
							class="manage-filters__rename"
							onsubmit={(event) => {
								event.preventDefault();
								void rename(filter);
							}}
						>
							<Input
								id={`rename-filter-${filter.id}`}
								label="Name"
								bind:value={draftName}
								maxlength={SAVED_FILTER_NAME_MAX}
								invalid={Boolean(rowError)}
								errorMessage={rowError}
								autocomplete="off"
							/>
							<div class="manage-filters__actions">
								<Button variant="secondary" variation="subtle" disabled={busy} onclick={cancelRow}>
									Cancel
								</Button>
								<Button type="submit" variant="primary" loading={busy}>Save</Button>
							</div>
						</form>
					{:else if deletingId === filter.id}
						<div class="manage-filters__confirm" role="group" aria-label={`Delete ${filter.name}`}>
							<p class="manage-filters__question">
								Delete “{filter.name}”?
								{#if filter.shared}
									Everyone on the team loses it.
								{/if}
							</p>
							{#if rowError}<p class="manage-filters__error" role="alert">{rowError}</p>{/if}
							<div class="manage-filters__actions">
								<Button variant="secondary" variation="subtle" disabled={busy} onclick={cancelRow}>
									Cancel
								</Button>
								<Button
									variant="primary"
									variation="destructive"
									loading={busy}
									onclick={() => void remove(filter)}
								>
									Delete
								</Button>
							</div>
						</div>
					{:else}
						<span class="manage-filters__name">{filter.name}</span>
						{#if filter.shared}
							<Badge status="informative" size="small" dot={false}>Shared</Badge>
						{/if}
						<span class="manage-filters__actions">
							<Button
								variant="tertiary"
								size="small"
								disabled={busy}
								onclick={() => startRename(filter)}
							>
								Rename
							</Button>
							<Button
								variant="tertiary"
								variation="destructive"
								size="small"
								disabled={busy}
								onclick={() => startDelete(filter)}
							>
								Delete
							</Button>
						</span>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</Dialog>

<style lang="scss">
	.manage-filters {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;

		&__row {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			min-height: 52px;
			padding: var(--space-small) 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}
		}
		&__name {
			flex: 1 1 auto;
			min-width: 0;
			color: var(--color-heading);
			font-weight: 500;
			overflow-wrap: anywhere;
		}
		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
		&__rename,
		&__confirm {
			display: flex;
			flex: 1 1 100%;
			flex-direction: column;
			gap: var(--space-small);
		}
		&__question {
			margin: 0;
			color: var(--color-heading);
		}
		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
		}
	}
</style>
