<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import TagSelect from '$lib/components/ui/TagSelect.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import FileLabelsDialog from './FileLabelsDialog.svelte';
	import {
		createFileLabel,
		describeFile,
		fetchFileLabels,
		fileDetailKey,
		fileLabelsKey,
		type FileDetail,
		type FileLabel
	} from '$lib/files/api';

	// A photo's caption and labels (behavior contract, Part 7B). Written once on the File, so the same words
	// show wherever the photo appears. It carries its own Save, like the rename dialog beside it: this is a
	// side panel or a dialog, never a detail page with a save bar.
	let {
		detail,
		onSaved
	}: {
		detail: FileDetail;
		onSaved?: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const uid = $props.id();

	const canEdit = $derived(detail.can_describe);
	// Curating the list is files.manage; everyone else picks from it.
	const canCurate = $derived(detail.can_manage);

	// The list is small and shared by every photo, so it is cached once and reopening any photo is instant.
	const labelsQuery = createQuery(() => ({
		queryKey: fileLabelsKey,
		queryFn: fetchFileLabels,
		enabled: canEdit
	}));

	const savedCaption = $derived(detail.file.caption ?? '');
	const savedLabelIds = $derived(detail.file.labels.map((label) => label.id));

	// Drafts start from what is saved and follow it while untouched, so a save elsewhere (or this one) lands
	// without leaving a stale draft behind.
	let captionDraft = $state<string | null>(null);
	let labelDraft = $state<string[] | null>(null);
	const caption = $derived(captionDraft ?? savedCaption);
	const labelIds = $derived(labelDraft ?? savedLabelIds);

	const dirty = $derived(
		caption.trim() !== savedCaption.trim() ||
			labelIds.length !== savedLabelIds.length ||
			labelIds.some((id) => !savedLabelIds.includes(id))
	);

	let saving = $state(false);
	let error = $state('');
	let manageOpen = $state(false);

	// A photo's saved labels are drawn from the detail, so they show even before the catalog loads; a label
	// created a moment ago joins from the catalog.
	const catalog = $derived(
		// The live list first, so a label renamed a moment ago shows its new name.
		[...(labelsQuery.data ?? []), ...detail.file.labels]
			.filter((label, index, all) => all.findIndex((entry) => entry.id === label.id) === index)
			.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }))
	);

	async function createLabel(name: string) {
		const label = await createFileLabel(name);
		queryClient.setQueryData<FileLabel[]>(fileLabelsKey, (current) =>
			current?.some((entry) => entry.id === label.id) ? current : [...(current ?? []), label]
		);
		return label;
	}

	function reset() {
		captionDraft = null;
		labelDraft = null;
		error = '';
	}

	async function save() {
		if (saving || !dirty) return;
		saving = true;
		error = '';
		try {
			await describeFile(detail.file.id, caption.trim(), labelIds);
			// The refetch replaces what is saved; dropping the drafts only after it lands keeps the form from
			// flashing back to the old words in between.
			await queryClient.invalidateQueries({ queryKey: fileDetailKey(detail.file.id) });
			void queryClient.invalidateQueries({ queryKey: ['files', 'list'] });
			// Every work report editor that offers this photo shows its caption and labels.
			void queryClient.invalidateQueries({ queryKey: ['jobs', 'report'] });
			reset();
			toast.success('Photo details saved');
			onSaved?.();
		} catch (saveError) {
			error = saveError instanceof Error ? saveError.message : 'That did not save.';
			// A label a colleague just removed: refresh the list so the picker stops offering it.
			void queryClient.invalidateQueries({ queryKey: fileLabelsKey });
		} finally {
			saving = false;
		}
	}
</script>

<div class="photo-describe">
	{#if canEdit}
		<form
			class="photo-describe__form"
			onsubmit={(event) => {
				event.preventDefault();
				void save();
			}}
		>
			<Textarea
				id={`${uid}-caption`}
				label="Caption"
				rows={2}
				maxlength={500}
				showCount={caption.length > 400}
				placeholder="e.g. Water damage under the sink"
				value={caption}
				oninput={(event: Event) =>
					(captionDraft = (event.currentTarget as HTMLTextAreaElement).value)}
			/>

			<div class="photo-describe__labels">
				<div class="photo-describe__labels-head">
					<span class="photo-describe__label">Labels</span>
					{#if canCurate}
						<button
							type="button"
							class="photo-describe__manage"
							onclick={() => (manageOpen = true)}
						>
							Manage labels
						</button>
					{/if}
				</div>
				{#if labelsQuery.isPending && detail.file.labels.length === 0}
					<LoadingSkeleton variant="text" label="Loading labels" rows={1} />
				{:else}
					<TagSelect
						tagIds={labelIds}
						onChange={(next) => (labelDraft = next)}
						{catalog}
						onCreate={canCurate ? createLabel : undefined}
						noun="label"
						addLabel="Add labels"
						searchId={`${uid}-label-search`}
					/>
				{/if}
			</div>

			{#if error}<p class="photo-describe__error" role="alert">{error}</p>{/if}

			{#if dirty}
				<div class="photo-describe__actions">
					<Button variant="secondary" variation="subtle" size="small" onclick={reset}>
						Cancel
					</Button>
					<Button type="submit" size="small" loading={saving}>Save</Button>
				</div>
			{/if}
		</form>
	{:else if detail.file.caption || detail.file.labels.length > 0}
		<!-- Read-only for anyone who may see the photo but not describe it. -->
		{#if detail.file.caption}<p class="photo-describe__caption">{detail.file.caption}</p>{/if}
		{#if detail.file.labels.length > 0}
			<TagSelect
				tagIds={savedLabelIds}
				catalog={detail.file.labels}
				noun="label"
				searchId={`${uid}-label-view`}
				readonly
			/>
		{/if}
	{/if}
</div>

{#if canCurate}
	<FileLabelsDialog open={manageOpen} onClose={() => (manageOpen = false)} />
{/if}

<style lang="scss">
	.photo-describe {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__form {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__labels {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__labels-head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__manage {
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: transparent;
			font-size: var(--typography--fontSize-small);
			cursor: pointer;

			&:hover {
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				border-radius: var(--radius-small);
				box-shadow: var(--shadow-focus);
			}
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__caption {
			color: var(--color-text);
			white-space: pre-line;
		}
	}
</style>
