<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import type { MatchAction } from '$lib/imports/api';
	import fileIcon from '@tabler/icons/outline/file-spreadsheet.svg?raw';
	import uploadIcon from '@tabler/icons/outline/upload.svg?raw';
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
<section class="panel">
	<header class="panel__head">
		<h2>{title}</h2>
		<p>{subtitle}</p>
	</header>

	<div class="panel__body">
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
					<span class="file-row__icon" aria-hidden="true">{@html fileIcon}</span>
					<span class="file-row__meta">
						<b>{file.name}</b>
						<span>{fileSize(file.size)}</span>
					</span>
					<button
						type="button"
						class="file-row__remove"
						aria-label="Remove file"
						onclick={() => onFile(null)}
					>
						{@html xIcon}
					</button>
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
					<span class="dropzone__icon" aria-hidden="true">{@html uploadIcon}</span>
					<span class="dropzone__text"><b>Choose a CSV file</b> or drag it here</span>
				</button>
			{/if}

			{#if errorMessage}
				<p class="field__error" role="alert">{errorMessage}</p>
			{/if}
			<p class="hint">
				Not sure about the format?
				<a class="link" href={sampleHref} download>Download our sample file</a>
				· Up to {rowCap.toLocaleString()} rows per import.
			</p>
		</div>
	</div>

	<footer class="panel__foot">
		<span class="foot-hint">Nothing is saved until you finish the last step.</span>
		<Button variant="primary" {loading} disabled={!file} onclick={onContinue}>
			Continue <span class="btn-icon" aria-hidden="true">{@html arrowRightIcon}</span>
		</Button>
	</footer>
</section>

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			padding: var(--space-large);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-slim);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}
	}

	.field {
		margin-bottom: var(--space-large);

		&:last-child {
			margin-bottom: 0;
		}

		&__label {
			display: block;
			font-weight: 600;
			font-size: var(--typography--fontSize-small);
			color: var(--color-heading);
			margin-bottom: var(--space-small);
		}

		&__error {
			margin: var(--space-small) 0 0;
			font-size: var(--typography--fontSize-small);
			color: var(--color-critical--onSurface);
		}
	}

	.hint {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		margin-top: var(--space-small);
	}
	.link {
		color: var(--color-interactive);
		font-weight: 600;
		text-decoration: none;

		&:hover {
			text-decoration: underline;
		}
	}

	.dropzone {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		width: 100%;
		font-family: inherit;
		font-size: var(--typography--fontSize-base);
		color: var(--color-text--secondary);
		background: var(--color-surface--background--subtle);
		border: 1px dashed var(--color-border--interactive);
		border-radius: var(--radius-base);
		padding: var(--space-large);
		cursor: pointer;
		text-align: left;
		transition:
			border-color 0.12s,
			background 0.12s;

		&:hover,
		&--over {
			background: var(--color-surface--hover);
			border-color: var(--color-interactive);
		}
		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}

		&__icon :global(svg) {
			width: 24px;
			height: 24px;
			display: block;
			color: var(--color-icon--secondary);
		}
		&__text b {
			color: var(--color-heading);
			font-weight: 600;
		}
	}

	.file-row {
		display: flex;
		align-items: center;
		gap: var(--space-slim);
		border: 1px solid var(--color-border--interactive);
		border-radius: var(--radius-base);
		padding: var(--space-slim) var(--space-base);
		background: var(--color-surface);

		&__icon {
			flex: none;
			width: 42px;
			height: 42px;
			border-radius: var(--radius-base);
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
			display: grid;
			place-items: center;

			:global(svg) {
				width: 22px;
				height: 22px;
			}
		}

		&__meta {
			flex: 1;
			min-width: 0;

			b {
				display: block;
				font-weight: 600;
				color: var(--color-heading);
				overflow: hidden;
				text-overflow: ellipsis;
				white-space: nowrap;
			}
			span {
				font-size: var(--typography--fontSize-small);
				color: var(--color-text--secondary);
			}
		}

		&__remove {
			flex: none;
			border: none;
			background: transparent;
			color: var(--color-icon--secondary);
			cursor: pointer;
			padding: var(--space-smaller);
			border-radius: var(--radius-small);
			display: grid;
			place-items: center;

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-destructive);
			}
			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}
	}

	.foot-hint {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
	}
</style>
