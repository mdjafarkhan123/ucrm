<script lang="ts">
	import { tick } from 'svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import { SETUP_FILE_KINDS, SETUP_FILE_KIND_LABELS } from '$lib/setup/files';
	import {
		SETUP_LIST_FIELD_KINDS,
		SETUP_LIST_FIELD_KIND_LABELS,
		SETUP_LIST_MAX_FIELDS,
		SETUP_LIST_STARTERS,
		SETUP_MAX_ROWS_CHOICES
	} from '$lib/setup/lists';
	import {
		draftListField,
		newDraftRowId,
		starterListFields,
		type DraftListField
	} from '$lib/jafar/setup-editor';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Client onboarding A5e: the boxes of an add-another list question, the way Jotform's configurable list
	// and Gravity Forms' repeater are set up — each box a name and a type, in the order clients see them —
	// plus how many entries a client may add. A new question can start from a ready-made set of boxes. Once
	// clients have answered, the boxes their entries already fill keep their type and cannot be removed.
	let {
		idPrefix,
		fields = $bindable(),
		maxRows = $bindable(),
		isNew,
		lockedKeys,
		fieldsError = '',
		maxRowsError = ''
	}: {
		idPrefix: string;
		fields: DraftListField[];
		maxRows: number;
		/** Not saved yet, so a starter may replace its boxes. */
		isNew: boolean;
		/** Boxes clients' entries already fill. */
		lockedKeys: ReadonlySet<string>;
		fieldsError?: string;
		maxRowsError?: string;
	} = $props();

	let root = $state<HTMLElement>();

	const kindOptions = SETUP_LIST_FIELD_KINDS.map((kind) => ({
		value: kind,
		label: SETUP_LIST_FIELD_KIND_LABELS[kind]
	}));

	const maxRowsOptions = SETUP_MAX_ROWS_CHOICES.map((count) => ({
		value: String(count),
		label: count === 1 ? 'Just one (shown as a form)' : `Up to ${count}`
	}));

	const locked = (field: DraftListField) => field.key !== null && lockedKeys.has(field.key);

	async function focusBox(rowId: string) {
		await tick();
		root
			?.querySelector<HTMLInputElement>(`#${CSS.escape(`${idPrefix}-box-${rowId}-label`)}`)
			?.focus();
	}

	function useStarter(key: string) {
		fields = starterListFields(key);
	}

	function addBox() {
		const field = draftListField({ label: '', kind: 'text', required: false });
		fields.push(field);
		void focusBox(field.rowId);
	}

	function move(index: number, by: -1 | 1) {
		const target = index + by;
		[fields[index], fields[target]] = [fields[target], fields[index]];
	}

	function setKind(field: DraftListField, value: string) {
		field.kind = value as DraftListField['kind'];
		if (field.kind === 'choice')
			while (field.options.length < 2)
				field.options.push({ rowId: newDraftRowId('choice'), value: null, label: '' });
	}

	async function addChoice(field: DraftListField) {
		const rowId = newDraftRowId('choice');
		field.options.push({ rowId, value: null, label: '' });
		await tick();
		root
			?.querySelector<HTMLInputElement>(
				`#${CSS.escape(`${idPrefix}-box-${field.rowId}-choice-${rowId}`)}`
			)
			?.focus();
	}

	function setFileKind(
		field: DraftListField,
		kind: (typeof SETUP_FILE_KINDS)[number],
		ticked: boolean
	) {
		field.file_kinds = ticked
			? [...field.file_kinds, kind]
			: field.file_kinds.filter((existing) => existing !== kind);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<fieldset class="setup-list-boxes" bind:this={root}>
	<legend>Boxes in each entry</legend>

	{#if isNew}
		<div class="setup-list-boxes__starters">
			<span class="setup-list-boxes__starters-label">Start from</span>
			{#each SETUP_LIST_STARTERS as starter (starter.key)}
				<Button size="small" variant="secondary" onclick={() => useStarter(starter.key)}
					>{starter.label}</Button
				>
			{/each}
		</div>
	{/if}

	<ol class="setup-list-boxes__list">
		{#each fields as field, index (field.rowId)}
			{@const name = field.label.trim() || `box ${index + 1}`}
			<li class="setup-list-boxes__box">
				<div class="setup-list-boxes__line">
					<div class="setup-list-boxes__name">
						<Input
							id={`${idPrefix}-box-${field.rowId}-label`}
							label={`Box ${index + 1} name`}
							maxlength={80}
							bind:value={field.label}
						/>
					</div>
					<div class="setup-list-boxes__type">
						<Select
							id={`${idPrefix}-box-${field.rowId}-kind`}
							label="Type"
							options={kindOptions}
							value={field.kind}
							disabled={locked(field)}
							onchange={(value: string) => setKind(field, value)}
						/>
					</div>
					<div class="setup-list-boxes__actions">
						<button
							type="button"
							class="setup-list-boxes__icon-button"
							aria-label={`Move ${name} earlier`}
							disabled={index === 0}
							onclick={() => move(index, -1)}>{@html arrowUpIcon}</button
						>
						<button
							type="button"
							class="setup-list-boxes__icon-button"
							aria-label={`Move ${name} later`}
							disabled={index === fields.length - 1}
							onclick={() => move(index, 1)}>{@html arrowDownIcon}</button
						>
						<button
							type="button"
							class="setup-list-boxes__icon-button setup-list-boxes__icon-button--danger"
							aria-label={`Remove ${name}`}
							disabled={locked(field) || fields.length === 1}
							onclick={() => fields.splice(index, 1)}>{@html trashIcon}</button
						>
					</div>
				</div>

				<div class="setup-list-boxes__details">
					<Checkbox
						id={`${idPrefix}-box-${field.rowId}-required`}
						label="Required in every entry"
						bind:checked={field.required}
					/>
					{#if locked(field)}
						<span class="setup-list-boxes__locked">
							<span class="setup-list-boxes__icon" aria-hidden="true">{@html lockIcon}</span>Clients
							have answered this list, so this box stays
						</span>
					{/if}
				</div>

				{#if field.kind === 'choice'}
					<div class="setup-list-boxes__choices">
						{#each field.options as option, choiceIndex (option.rowId)}
							<div class="setup-list-boxes__choice">
								<Input
									id={`${idPrefix}-box-${field.rowId}-choice-${option.rowId}`}
									label={`Choice ${choiceIndex + 1}`}
									maxlength={100}
									bind:value={option.label}
								/>
								<button
									type="button"
									class="setup-list-boxes__icon-button setup-list-boxes__icon-button--danger"
									aria-label={`Remove choice ${choiceIndex + 1} of ${name}`}
									disabled={field.options.length <= 2}
									onclick={() => field.options.splice(choiceIndex, 1)}>{@html xIcon}</button
								>
							</div>
						{/each}
						<div>
							<Button
								size="small"
								variant="secondary"
								disabled={field.options.length >= 50}
								onclick={() => addChoice(field)}
								><span class="setup-list-boxes__icon" aria-hidden="true">{@html plusIcon}</span>Add
								choice</Button
							>
						</div>
					</div>
				{:else if field.kind === 'file'}
					<div class="setup-list-boxes__choices">
						{#each SETUP_FILE_KINDS as fileKind (fileKind)}
							<Checkbox
								id={`${idPrefix}-box-${field.rowId}-file-${fileKind}`}
								label={SETUP_FILE_KIND_LABELS[fileKind].label}
								description={SETUP_FILE_KIND_LABELS[fileKind].formats}
								checked={field.file_kinds.includes(fileKind)}
								onchange={(ticked) => setFileKind(field, fileKind, ticked)}
							/>
						{/each}
						<p class="setup-list-boxes__hint">Each entry holds one file, up to 100 MB.</p>
					</div>
				{/if}
			</li>
		{/each}
	</ol>

	{#if fieldsError}
		<p class="setup-list-boxes__error" role="alert">{fieldsError}</p>
	{/if}

	{#if fields.length < SETUP_LIST_MAX_FIELDS}
		<div>
			<Button size="small" variant="secondary" onclick={addBox}
				><span class="setup-list-boxes__icon" aria-hidden="true">{@html plusIcon}</span>Add box</Button
			>
		</div>
	{/if}

	<div class="setup-list-boxes__rows">
		<Select
			id={`${idPrefix}-max-rows`}
			label="How many entries a client can add"
			options={maxRowsOptions}
			value={String(maxRows)}
			onchange={(value: string) => (maxRows = Number(value))}
		/>
		{#if maxRowsError}
			<p class="setup-list-boxes__error" role="alert">{maxRowsError}</p>
		{:else}
			<p class="setup-list-boxes__hint">
				Choose “Just one” for a single person or address. Clients add entries with an “Add another”
				button and can remove them.
			</p>
		{/if}
	</div>
</fieldset>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-list-boxes {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		margin: 0;
		padding: 0;
		border: 0;

		legend {
			margin-bottom: var(--space-small);
			padding: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__starters {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__starters-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__box {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__line {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-start;
			gap: var(--space-small);
		}

		&__name {
			flex: 2 1 20rem;
			min-width: 0;
		}

		&__type {
			flex: 1 1 16rem;
			min-width: 0;
		}

		&__actions {
			display: flex;
			flex: none;
			align-items: center;
			gap: var(--space-smallest);
			padding-top: var(--space-smaller);
		}

		&__details {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-base);
		}

		&__locked {
			display: inline-flex;
			align-items: center;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__choices {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding-left: var(--space-base);
			border-left: var(--border-thick) solid var(--color-border);
		}

		&__choice {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			> :first-child {
				flex: 1 1 auto;
				min-width: 0;
			}
		}

		&__rows {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			max-width: 36rem;
		}

		&__icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 1.6rem;
				height: 1.6rem;
			}
		}

		&__icon-button {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 3.6rem;
			height: 3.6rem;
			padding: 0;
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-text--secondary);
			cursor: pointer;

			:global(svg) {
				width: 1.8rem;
				height: 1.8rem;
			}

			&:hover:not(:disabled) {
				background: var(--color-surface--hover);
				color: var(--color-heading);
			}

			&--danger:hover:not(:disabled) {
				color: var(--color-critical);
			}

			&:disabled {
				opacity: 0.4;
				cursor: not-allowed;
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__hint,
		&__error {
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__hint {
			color: var(--color-text--secondary);
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}
	}
</style>
