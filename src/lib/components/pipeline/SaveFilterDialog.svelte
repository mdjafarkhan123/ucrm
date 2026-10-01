<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		SavedFilterWriteError,
		createSavedFilter,
		savedFiltersKey,
		type SavedFilter
	} from '$lib/pipeline/api';
	import { SAVED_FILTER_NAME_MAX, type BoardFilters } from '$lib/pipeline/filters';

	// Names the board's current controls and keeps them. A personal filter by default; owners and
	// administrators may tick one box to give it to the whole team instead.
	let {
		open,
		filters,
		summary,
		canShare,
		onSaved,
		onClose
	}: {
		open: boolean;
		filters: BoardFilters;
		// What is being saved, in words, so nobody has to guess which controls a filter remembers.
		summary: string;
		canShare: boolean;
		onSaved: (filter: SavedFilter) => void;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let name = $state('');
	let shared = $state(false);
	let saving = $state(false);
	let nameError = $state('');
	let formError = $state('');

	// Each opening starts clean: a name typed and abandoned last time is not this filter's name.
	$effect(() => {
		if (!open) return;
		name = '';
		shared = false;
		nameError = '';
		formError = '';
	});

	async function save() {
		if (saving) return;
		if (!name.trim()) {
			nameError = 'Give the filter a name.';
			return;
		}
		saving = true;
		nameError = '';
		formError = '';
		try {
			const saved = await createSavedFilter({ name, shared: canShare && shared, filters });
			await queryClient.invalidateQueries({ queryKey: savedFiltersKey });
			toast.success(saved.shared ? 'Filter shared with the team' : 'Filter saved');
			onSaved(saved);
		} catch (thrown) {
			if (thrown instanceof SavedFilterWriteError && thrown.fieldErrors.name) {
				nameError = thrown.fieldErrors.name;
			} else {
				formError = thrown instanceof Error ? thrown.message : 'That filter could not be saved.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	{open}
	title="Save filter"
	size="small"
	initialFocusId="save-filter-name"
	onClose={saving ? () => {} : onClose}
>
	<form
		class="save-filter"
		onsubmit={(event) => {
			event.preventDefault();
			void save();
		}}
	>
		<p class="save-filter__summary">{summary}</p>

		<Input
			id="save-filter-name"
			label="Name"
			bind:value={name}
			maxlength={SAVED_FILTER_NAME_MAX}
			invalid={Boolean(nameError)}
			errorMessage={nameError}
			autocomplete="off"
		/>

		{#if canShare}
			<Checkbox
				id="save-filter-shared"
				label="Share with everyone on the team"
				description="Everyone who can see the Pipeline gets this filter. Only owners and administrators can change it."
				bind:checked={shared}
			/>
		{/if}

		{#if formError}<p class="save-filter__error" role="alert">{formError}</p>{/if}

		<div class="save-filter__actions">
			<Button variant="secondary" variation="subtle" disabled={saving} onclick={onClose}>
				Cancel
			</Button>
			<Button type="submit" variant="primary" loading={saving}>Save</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.save-filter {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__summary {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-large);
		}
		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
