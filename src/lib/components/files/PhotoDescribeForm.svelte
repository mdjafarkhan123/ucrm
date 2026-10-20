<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import TagSelect from '$lib/components/ui/TagSelect.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import settingsIcon from '@tabler/icons/outline/adjustments.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import alertCircleIcon from '@tabler/icons/outline/alert-circle.svg?raw';
	import quoteIcon from '@tabler/icons/outline/quote.svg?raw';
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
		inDialog = false,
		onSaved
	}: {
		detail: FileDetail;
		/** Inside the Caption and labels pop-up: no card of its own, a LABELS caption row, and the save strip
		 *  as the pop-up's footer. */
		inDialog?: boolean;
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

	// The caption box is one line until the words need more.
	function growWithText(element: HTMLTextAreaElement) {
		const fit = () => {
			element.style.height = 'auto';
			element.style.height = `${element.scrollHeight}px`;
		};
		fit();
		element.addEventListener('input', fit);
		return () => element.removeEventListener('input', fit);
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

<!-- eslint-disable svelte/no-at-html-tags -->
<div
	class="photo-describe"
	class:photo-describe--readonly={!canEdit}
	class:photo-describe--dialog={inDialog}
>
	{#if canEdit && !inDialog}<header class="photo-describe__header">
			<IconTile icon={photoIcon} size={32} />
			<h3>Caption and labels</h3>
			{#if canCurate}<Button variant="quiet" size="small" onclick={() => (manageOpen = true)}
					>{@html settingsIcon}Manage labels</Button
				>{/if}
		</header>{/if}
	{#if canEdit}
		<form
			class="photo-describe__form"
			onsubmit={(event) => {
				event.preventDefault();
				void save();
			}}
		>
			{#if inDialog}
				<label class="photo-describe__caption-box" class:photo-describe__caption-box--busy={saving}>
					<span class="photo-describe__sr">Caption</span>
					<span class="photo-describe__quote" aria-hidden="true">{@html quoteIcon}</span>
					<textarea
						id={`${uid}-caption`}
						rows={1}
						maxlength={500}
						disabled={saving}
						placeholder="e.g. Water damage under the sink"
						value={caption}
						oninput={(event) => (captionDraft = event.currentTarget.value)}
						{@attach growWithText}
					></textarea>
				</label>
			{:else}
				<Textarea
					disabled={saving}
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
			{/if}

			<div class="photo-describe__labels">
				{#if inDialog}
					<div class="photo-describe__labels-head">
						<span class="photo-describe__caption-label">Labels</span>
						{#if canCurate}<Button variant="quiet" size="small" onclick={() => (manageOpen = true)}
								>{@html settingsIcon}Manage labels</Button
							>{/if}
					</div>
				{/if}
				{#if labelsQuery.isPending && detail.file.labels.length === 0}
					<LoadingSkeleton variant="text" label="Loading labels" rows={1} />
				{:else}
					<TagSelect
						tagIds={labelIds}
						readonly={saving}
						onChange={(next) => (labelDraft = next)}
						{catalog}
						onCreate={canCurate ? createLabel : undefined}
						noun="label"
						addLabel="Add labels"
						searchId={`${uid}-label-search`}
					/>
				{/if}
			</div>

			{#if error}
				<p class="photo-describe__error" role="alert">
					<span aria-hidden="true">{@html alertCircleIcon}</span>{error}
				</p>
			{/if}

			{#if dirty}
				<div class="photo-describe__actions">
					<span class="photo-describe__unsaved">{saving ? 'Saving…' : 'Not saved'}</span>
					<Button
						variant="secondary"
						variation="subtle"
						size="small"
						disabled={saving}
						onclick={reset}
					>
						Cancel
					</Button>
					<Button type="submit" size="small" loading={saving}>{@html checkIcon}Save</Button>
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

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}

		&__error {
			display: flex;
			align-items: center;
			gap: 6px;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__labels-head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			min-height: 28px;
		}

		&__caption-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			letter-spacing: 0.6px;
			text-transform: uppercase;
		}

		&__caption {
			color: var(--color-text);
			white-space: pre-line;
		}
	}

	.photo-describe {
		gap: 0;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		overflow: hidden;
	}
	.photo-describe__header {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-base) var(--space-base) var(--space-slim) var(--space-medium);
		h3 {
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
			color: var(--color-heading);
			flex: 1;
		}
	}
	.photo-describe__form {
		gap: 14px;
		padding: 0 var(--space-medium) var(--space-medium);
	}
	.photo-describe__form :global(.textarea__control) {
		background: var(--color-surface--background--subtle);
	}
	.photo-describe__form :global(.textarea__control:focus-within) {
		background: var(--color-surface);
		border-color: var(--color-interactive);
	}
	.photo-describe__actions {
		align-items: center;
		margin: 0 calc(-1 * var(--space-medium)) calc(-1 * var(--space-medium));
		padding: var(--space-slim) var(--space-base) var(--space-slim) var(--space-medium);
		border-top: var(--border-base) solid var(--color-border);
		background: var(--color-surface--background--subtle);
	}
	.photo-describe__unsaved {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-right: auto;
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		color: var(--color-warning--onSurface);
		&::before {
			content: '';
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-warning);
		}
	}
	// The caption box (`files.md` → Photo details): a quote mark and the words, growing with them.
	.photo-describe__caption-box {
		display: flex;
		align-items: flex-start;
		gap: 10px;
		padding: var(--space-slim) 14px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
		cursor: text;

		&:focus-within {
			border-color: var(--color-interactive);
			background: var(--color-surface);
			box-shadow: inset 0 0 0 0.5px var(--color-interactive);
		}

		&--busy {
			opacity: 0.6;
		}

		textarea {
			width: 100%;
			min-width: 0;
			min-height: 0;
			flex: 1 1 auto;
			margin: 0;
			padding: 0;
			border: 0;
			outline: none;
			resize: none;
			overflow: hidden;

			&:focus,
			&:focus-visible {
				outline: none;
				box-shadow: none;
			}
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			line-height: 1.45;

			&::placeholder {
				padding-top: 0;
				color: var(--color-text--secondary);
			}
		}
	}

	.photo-describe__quote {
		display: inline-flex;
		flex: 0 0 auto;
		padding-top: 2px;
		color: var(--color-icon--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	.photo-describe__sr {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
	}

	.photo-describe__labels-head :global(button) {
		color: var(--color-interactive);
	}

	// Inside the pop-up: no card; the save strip runs edge to edge as the pop-up's footer.
	.photo-describe--dialog {
		border: 0;
		border-radius: 0;
		overflow: visible;

		.photo-describe__form {
			padding: 0;
		}

		.photo-describe__actions {
			position: sticky;
			bottom: calc(-1 * var(--space-medium));
			margin: var(--space-smaller) calc(-1 * var(--space-medium)) calc(-1 * var(--space-medium));
			padding: var(--space-base) var(--space-medium);
		}
	}

	.photo-describe--readonly {
		border: 0;
		border-radius: 0;
		gap: var(--space-small);
	}
	@media (max-width: 479px) {
		.photo-describe__header {
			flex-wrap: wrap;
		}
		.photo-describe__actions {
			flex-wrap: wrap;
		}
	}
	.photo-describe__form :global(.textarea textarea) {
		background: var(--color-surface--background--subtle);
	}
	.photo-describe__form :global(.textarea textarea:focus),
	.photo-describe__form:has(.photo-describe__actions) :global(.textarea textarea) {
		background: var(--color-surface);
		border-color: var(--color-interactive);
	}
	.photo-describe__header :global(button) {
		color: var(--color-interactive);
	}
</style>
