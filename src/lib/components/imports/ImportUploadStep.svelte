<script lang="ts">
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import ImportStepCard from './ImportStepCard.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import type { MatchAction } from '$lib/imports/api';
	import fileIcon from '@tabler/icons/outline/file-spreadsheet.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
	import downloadIcon from '@tabler/icons/outline/download.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';

	let {
		file,
		matchAction = $bindable(),
		errorMessage = '',
		loading = false,
		title = 'Upload your client list',
		subtitle = 'A spreadsheet saved as CSV, with one client per row.',
		showMatchAction = true,
		matchActionLabel = 'How should we handle clients you already have?',
		matchHint = 'We recognise an existing client by a matching email or phone number.',
		matchOptions = [
			{ value: 'update', label: 'Add new clients and update the ones I already have' },
			{ value: 'skip', label: 'Add new clients only — leave my existing ones untouched' }
		],
		sampleHref = '/samples/client-import-sample.csv',
		rowCap = 5000,
		tone = 'client',
		onFile,
		onContinue
	}: {
		file: File | null;
		matchAction: MatchAction;
		errorMessage?: string;
		loading?: boolean;
		title?: string;
		subtitle?: string;
		// Some imports (opening balances) have no skip/update choice -- a match always resolves the same way,
		// so there is nothing to ask.
		showMatchAction?: boolean;
		matchActionLabel?: string;
		matchHint?: string;
		matchOptions?: { value: string; label: string }[];
		sampleHref?: string;
		rowCap?: number;
		/** The import's colour family, for the card header tile. */
		tone?: string;
		onFile: (file: File | null) => void;
		onContinue: () => void;
	} = $props();

	let dragOver = $state(false);
	let inputEl = $state<HTMLInputElement>();

	function pick(files: FileList | null) {
		onFile(files && files.length > 0 ? files[0] : null);
	}

	function onDrop(event: DragEvent) {
		event.preventDefault();
		dragOver = false;
		pick(event.dataTransfer?.files ?? null);
	}

	function fileSize(bytes: number): string {
		if (bytes < 1024) return `${bytes} B`;
		if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
		return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ImportStepCard {title} hint={subtitle} icon={uploadIcon} {tone}>
	{#if showMatchAction}
		<div class="field">
			<Select
				id="import-match-action"
				label={matchActionLabel}
				value={matchAction}
				options={matchOptions}
				onchange={(value) => (matchAction = value as MatchAction)}
			/>
			<p class="hint">{matchHint}</p>
		</div>
	{/if}

	<div class="field">
		<label class="field__label" for="import-file">Your file</label>
		<input
			bind:this={inputEl}
			id="import-file"
			type="file"
			accept=".csv,text/csv,application/vnd.ms-excel"
			class="visually-hidden"
			onchange={(event) => pick(event.currentTarget.files)}
		/>

		{#if file}
			<div class="file-row">
				<IconTile icon={fileIcon} tone="success" />
				<span class="file-row__meta">
					<b>{file.name}</b>
					<span>{fileSize(file.size)}</span>
				</span>
				<Button
					variant="secondary"
					size="small"
					iconOnly
					label="Remove file"
					onclick={() => onFile(null)}
				>
					{@html xIcon}
				</Button>
			</div>
		{:else}
			<button
				type="button"
				class="dropzone"
				class:dropzone--over={dragOver}
				onclick={() => inputEl?.click()}
				ondragover={(event) => {
					event.preventDefault();
					dragOver = true;
				}}
				ondragleave={() => (dragOver = false)}
				ondrop={onDrop}
			>
				<IconTile icon={fileIcon} tone="success" />
				<span class="dropzone__text">
					<b>Choose a CSV file or drag it here</b>
					<span>Up to {rowCap.toLocaleString()} rows per import</span>
				</span>
			</button>
		{/if}

		<a class="sample-link" href={sampleHref} download>
			<span aria-hidden="true">{@html downloadIcon}</span>
			Not sure about the format? Download our sample file
		</a>
	</div>

	{#if errorMessage}
		<Banner type="error">{errorMessage}</Banner>
	{/if}

	{#snippet footer()}
		<span class="foot-hint">Nothing is saved until you finish the last step.</span>
		<Button variant="primary" {loading} disabled={!file} onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	{/snippet}
</ImportStepCard>

<style lang="scss">
	.field {
		display: flex;
		flex-direction: column;
		gap: 6px;

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}
	}

	.hint {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.sample-link {
		display: inline-flex;
		align-self: flex-start;
		align-items: center;
		gap: 6px;
		margin-top: 4px;
		color: var(--color-interactive);
		font-size: var(--typography--fontSize-label);
		font-weight: 600;
		text-decoration: none;

		:global(svg) {
			display: block;
			width: 14px;
			height: 14px;
		}
		&:hover {
			text-decoration: underline;
		}
		&:focus-visible {
			border-radius: var(--radius-small);
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.dropzone {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-slim);
		width: 100%;
		padding: 28px var(--space-medium);
		border: 1.5px solid var(--color-border--interactive);
		border-radius: var(--radius-large);
		background: var(--color-surface--background);
		font-family: inherit;
		text-align: center;
		cursor: pointer;
		transition:
			border-color 0.12s,
			background 0.12s;

		&:hover,
		&--over {
			border-color: var(--color-interactive);
			background: var(--color-surface--hover);
		}
		&:active {
			background: var(--color-surface--active);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&__text {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);

			b {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}
	}

	.file-row {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		padding: var(--space-slim) var(--space-base);
		border: var(--border-base) solid var(--color-border--interactive);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&__meta {
			flex: 1;
			min-width: 0;

			b {
				display: block;
				overflow: hidden;
				color: var(--color-heading);
				font-weight: 600;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}
	}

	.foot-hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.btn-icon :global(svg) {
		display: block;
		width: 16px;
		height: 16px;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		border: 0;
		white-space: nowrap;
	}
</style>
