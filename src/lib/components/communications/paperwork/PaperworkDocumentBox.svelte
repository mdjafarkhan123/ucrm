<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import {
		PAPERWORK_FILE_ACCEPT,
		type FormField,
		type FormRequirement,
		type PaperworkDocument
	} from '$lib/communications/number-paperwork';
	import PaperworkField from './PaperworkField.svelte';
	import type { LocalUpload, PaperworkDraft } from './paperwork-draft.svelte';
	import { fileSize } from './paperwork-ui';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import fileCheckIcon from '@tabler/icons/outline/file-check.svg?raw';
	import fileIcon from '@tabler/icons/outline/file.svg?raw';
	import uploadIcon from '@tabler/icons/outline/cloud-upload.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/upload.svg?raw';
	import loaderIcon from '@tabler/icons/outline/loader-2.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';

	// One document the country asks for (`concept.pen` board `A0URqF`, Documents step and "Every state"): what
	// it must show, the kinds that count (pressing one picks it), and the file in each of its states.
	let {
		draft,
		requirement,
		chosenType,
		coveredBy,
		fields,
		document,
		errors,
		uploaded
	}: {
		draft: PaperworkDraft;
		requirement: FormRequirement;
		chosenType: string;
		/** The name of a box above whose document already proves this one. */
		coveredBy: string | null;
		/** Every fact typed about the chosen document, across all the places it is asked for. */
		fields: FormField[];
		document: PaperworkDocument | null;
		/** What to correct, once Continue was pressed or the phone company sent it back: the file, and each fact. */
		errors: { file: string | null; fields: Record<string, string> };
		uploaded: () => Promise<unknown>;
	} = $props();

	const kind = $derived(
		requirement.kinds.find((candidate) => candidate.documentType === chosenType) ??
			requirement.kinds[0]
	);
	const local = $derived<LocalUpload | undefined>(draft.uploads[chosenType]);
	const file = $derived(document?.file && document.file.state !== 'deleted' ? document.file : null);

	type BoxState = 'covered' | 'address' | 'needed' | 'uploading' | 'checking' | 'refused' | 'added';
	const boxState = $derived<BoxState>(
		coveredBy
			? 'covered'
			: !kind?.needsFile
				? 'address'
				: local?.problem
					? 'refused'
					: local
						? 'uploading'
						: file?.state === 'checking'
							? 'checking'
							: file?.state === 'ready'
								? 'added'
								: file?.state === 'refused'
									? 'refused'
									: 'needed'
	);
	const percent = $derived(local?.progress != null ? Math.round(local.progress * 100) : null);

	const PILLS: Record<
		BoxState,
		{ tone: 'warning' | 'informative' | 'critical' | 'success'; label: string }
	> = {
		covered: { tone: 'success', label: 'Covered' },
		address: { tone: 'success', label: 'Added' },
		needed: { tone: 'warning', label: 'Needed' },
		uploading: { tone: 'informative', label: 'Sending' },
		checking: { tone: 'warning', label: 'Checking' },
		refused: { tone: 'critical', label: 'Didn’t upload' },
		added: { tone: 'success', label: 'Added' }
	};

	let input = $state<HTMLInputElement>();
	let dragOver = $state(false);

	function pick(files: FileList | null | undefined) {
		const chosen = files?.[0];
		if (input) input.value = '';
		if (chosen) void draft.upload(chosenType, chosen, uploaded);
	}

	function drop(event: DragEvent) {
		event.preventDefault();
		dragOver = false;
		pick(event.dataTransfer?.files);
	}

	function choose() {
		draft.clearUpload(chosenType);
		input?.click();
	}

	// The 40 ring around the file's tile fills as the bytes go up.
	const RING = 2 * Math.PI * 18;
</script>

<!-- The inline SVG strings are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->
<section
	class={[
		'document-box',
		(errors.file || Object.keys(errors.fields).length) && 'document-box--error'
	]}
	id={`document-${requirement.requirementName}`}
	aria-labelledby={`document-${requirement.requirementName}-title`}
>
	<header class="document-box__head">
		<IconTile
			icon={kind?.needsFile === false ? mapPinIcon : fileTextIcon}
			tone="client"
			size={32}
		/>
		<span class="document-box__title">
			<strong id={`document-${requirement.requirementName}-title`}>{requirement.label}</strong>
			{#if requirement.hint || requirement.kinds.length === 1}
				<span>{requirement.hint || `Your ${kind?.label.toLowerCase()}`}</span>
			{/if}
		</span>
		<StatusBadge status={PILLS[boxState].tone}
			>{boxState === 'uploading' && percent !== null ? `${percent}%` : PILLS[boxState].label}</StatusBadge
		>
	</header>

	{#if requirement.kinds.length > 1}
		<div class="document-box__kinds" role="group" aria-label="What counts">
			<span class="document-box__kinds-label">What counts:</span>
			{#each requirement.kinds as option (option.documentType)}
				<button
					type="button"
					class={[
						'document-box__kind',
						option.documentType === chosenType && 'document-box__kind--chosen'
					]}
					aria-pressed={option.documentType === chosenType}
					disabled={boxState === 'uploading'}
					onclick={() => draft.chooseDocument(requirement.requirementName, option.documentType)}
				>
					<span aria-hidden="true">{@html checkIcon}</span>
					{option.label}
				</button>
			{/each}
		</div>
	{/if}

	{#if boxState === 'covered'}
		<p class="document-box__note">
			<span aria-hidden="true">{@html checkIcon}</span>
			The {kind?.label.toLowerCase()} you add for “{coveredBy}” covers this too.
		</p>
	{:else if boxState === 'address'}
		<p class="document-box__note">
			<span aria-hidden="true">{@html checkIcon}</span>
			The address you gave in Business details covers this. Nothing to upload.
		</p>
	{:else}
		<input
			bind:this={input}
			class="document-box__input"
			type="file"
			accept={PAPERWORK_FILE_ACCEPT}
			aria-label={`Choose a file for ${requirement.label}`}
			onchange={(event) => pick(event.currentTarget.files)}
		/>
		{#if boxState === 'needed'}
			<button
				type="button"
				class={['document-box__drop', dragOver && 'document-box__drop--over']}
				onclick={choose}
				ondragover={(event) => {
					event.preventDefault();
					dragOver = true;
				}}
				ondragleave={() => (dragOver = false)}
				ondrop={drop}
			>
				<IconTile icon={uploadIcon} tone="conversation" />
				<strong>Choose a PDF or photo, or drag it here</strong>
				<span>PDF, JPG or PNG · up to 5 MB</span>
			</button>
		{:else if boxState === 'uploading' && local}
			<div class="document-box__file">
				<span class="document-box__ring" aria-hidden="true">
					<svg viewBox="0 0 40 40">
						<circle cx="20" cy="20" r="18" class="document-box__ring-track" />
						<circle
							cx="20"
							cy="20"
							r="18"
							class="document-box__ring-fill"
							stroke-dasharray={RING}
							stroke-dashoffset={RING * (1 - (local.progress ?? 1))}
						/>
					</svg>
					<span class="document-box__ring-tile">{@html fileIcon}</span>
				</span>
				<span class="document-box__file-copy">
					<strong>{local.name}</strong>
					<span
						>{local.progress === null
							? 'Finishing…'
							: `${fileSize(local.size * local.progress)} of ${fileSize(local.size)}`}</span
					>
				</span>
				<Button
					variant="secondary"
					size="small"
					iconOnly
					label="Stop sending this file"
					onclick={() => draft.cancelUpload(chosenType)}
				>
					{@html xIcon}
				</Button>
			</div>
		{:else if boxState === 'checking' && file}
			<div class="document-box__file">
				<span class="document-box__spinner" aria-hidden="true">{@html loaderIcon}</span>
				<span class="document-box__file-copy">
					<strong>{file.name}</strong>
					<span>Uploaded, now being checked for safety</span>
				</span>
			</div>
		{:else if boxState === 'refused'}
			<div class="document-box__file document-box__file--refused">
				<span class="document-box__refused-tile" aria-hidden="true">{@html alertIcon}</span>
				<span class="document-box__file-copy">
					<strong>{local?.name ?? file?.name}</strong>
					<span role="alert"
						>{local?.problem ??
							file?.problem ??
							'This file couldn’t be used. Choose another.'}</span
					>
				</span>
				<Button variant="secondary" size="small" onclick={choose}>
					<span aria-hidden="true">{@html arrowUpIcon}</span>
					Choose another
				</Button>
			</div>
		{:else if boxState === 'added' && file}
			<div class="document-box__file">
				<IconTile icon={fileCheckIcon} tone="success" size={32} class="document-box__round" />
				<span class="document-box__file-copy">
					<strong>{file.name}</strong>
					<span>{fileSize(file.size_bytes)} · added</span>
				</span>
				<Button variant="quiet" size="small" onclick={choose}>Replace</Button>
			</div>
		{/if}
	{/if}

	{#if kind && fields.length && boxState !== 'covered'}
		<div class="document-box__fields">
			{#each fields as field (field.name)}
				<PaperworkField
					{field}
					idPrefix={`document-${kind.documentType}`}
					value={draft.documentFields[kind.documentType]?.[field.name] ?? ''}
					error={errors.fields[field.name]}
					onchange={(value) => draft.setDocumentField(kind.documentType, field.name, value)}
				/>
			{/each}
		</div>
	{/if}

	{#if errors.file}
		<p class="document-box__error" role="alert">
			<span aria-hidden="true">{@html alertIcon}</span>{errors.file}
		</p>
	{/if}
</section>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.document-box {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);

		&--error {
			border-color: var(--color-critical);
		}

		&__head {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
		}

		&__title,
		&__file-copy {
			display: grid;
			flex: 1;
			gap: 2px;
			min-width: 0;

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
				overflow-wrap: anywhere;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
				line-height: var(--typography--lineHeight-large);
			}
		}

		&__kinds {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__kinds-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
		}

		&__kind {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			height: 28px;
			padding: 0 10px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-heading);
			font: inherit;
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;
			cursor: pointer;

			span {
				display: none;
				color: var(--color-success);
			}

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}

			&:hover {
				background: var(--color-surface--background--subtle--hover);
			}

			&:focus-visible {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}

			&:disabled {
				opacity: 0.55;
				cursor: not-allowed;
			}

			&--chosen {
				border-color: var(--color-interactive);
				background: var(--color-surface);
				box-shadow: inset 0 0 0 0.5px var(--color-interactive);
				font-weight: 600;

				span {
					display: block;
				}
			}
		}

		&__input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}

		&__drop {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: var(--space-small);
			width: 100%;
			padding: 28px var(--space-medium);
			border: 1.5px solid var(--color-border--interactive);
			border-radius: var(--radius-large);
			background: var(--color-surface--background);
			font: inherit;
			text-align: center;
			cursor: pointer;

			strong {
				margin-top: var(--space-smaller);
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-smaller);
			}

			&:hover,
			&--over {
				border-color: var(--color-interactive);
				background: var(--color-surface--background--hover);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__file {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);

			&--refused {
				border-color: var(--color-critical--surface-edge);
				background: var(--color-critical--surface);

				.document-box__file-copy span {
					color: var(--color-critical--onSurface);
				}
			}
		}

		:global(.document-box__round) {
			border-radius: var(--radius-circle);
		}

		&__ring {
			position: relative;
			display: grid;
			flex: none;
			place-items: center;
			width: 40px;
			height: 40px;

			svg {
				position: absolute;
				inset: 0;
				transform: rotate(-90deg);
			}
		}

		&__ring-track,
		&__ring-fill {
			fill: none;
			stroke-width: 2;
		}

		&__ring-track {
			stroke: var(--color-border);
		}

		&__ring-fill {
			stroke: var(--color-interactive);
			stroke-linecap: round;
			transition: stroke-dashoffset var(--timing-quick) linear;
		}

		&__ring-tile,
		&__spinner,
		&__refused-tile {
			display: grid;
			flex: none;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-circle);
			background: var(--color-surface);
			color: var(--color-icon);

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		&__spinner :global(svg) {
			animation: document-box-spin 1s linear infinite;
		}

		&__refused-tile {
			color: var(--color-critical);
		}

		&__note {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 500;

			span {
				color: var(--color-success);
			}

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__fields {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__error {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-smaller);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}
	}

	@keyframes document-box-spin {
		to {
			transform: rotate(360deg);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.document-box__spinner :global(svg) {
			animation: none;
		}
	}
</style>
