<script lang="ts">
	import { tick } from 'svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import SetupListBoxes from '$lib/components/jafar/setup/SetupListBoxes.svelte';
	import SetupShowIf from '$lib/components/jafar/setup/SetupShowIf.svelte';
	import { SETUP_QUESTION_KINDS } from '$lib/setup/catalogue';
	import {
		SETUP_FILE_KINDS,
		SETUP_FILE_KIND_LABELS,
		SETUP_MAX_FILES_CHOICES,
		type SetupFileKind
	} from '$lib/setup/files';
	import {
		SETUP_QUESTION_KIND_LABELS,
		isChoiceKind,
		pickSources,
		reuseSources,
		showIfSources,
		type DraftItem,
		type SetupEditor,
		type SetupEditorStage
	} from '$lib/jafar/setup-editor';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
	import gitBranchIcon from '@tabler/icons/outline/git-branch.svg?raw';
	import headingIcon from '@tabler/icons/outline/heading.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';

	// Client onboarding A5 (plan §2.1): one stage's headings and questions in the order clients see them, as
	// cards the way Google Forms and Tally lay out a form builder — one card open for editing, the rest
	// summarised. The page owns the list and the saving. A built-in question can be reworded and moved, never
	// removed or given another answer type; a question clients have answered keeps its answer type.
	let {
		items = $bindable(),
		answered,
		earlierStages,
		services,
		errors = {}
	}: {
		items: DraftItem[];
		/** Questions clients have answered, by key. */
		answered: ReadonlySet<string>;
		/** The stages before this one, as saved, for "show only if" rules. */
		earlierStages: SetupEditorStage[];
		services: SetupEditor['services'];
		/** What is wrong with a row's field, keyed `<rowId>.<field>`. */
		errors?: Record<string, string>;
	} = $props();

	let list = $state<HTMLOListElement>();
	let openRow = $state<string | null>(null);
	let newChoices = 0;

	const kindOptions = SETUP_QUESTION_KINDS.map((kind) => ({
		value: kind,
		label: SETUP_QUESTION_KIND_LABELS[kind]
	}));

	const maxFilesOptions = SETUP_MAX_FILES_CHOICES.map((count) => ({
		value: String(count),
		label: count === 1 ? '1 file' : `Up to ${count} files`
	}));

	function setFileKind(item: DraftItem, kind: SetupFileKind, ticked: boolean) {
		item.file_kinds = ticked
			? [...item.file_kinds, kind]
			: item.file_kinds.filter((existing) => existing !== kind);
	}

	function kindLocked(item: DraftItem) {
		return item.built_in || (item.fact_key !== null && answered.has(item.fact_key));
	}

	/** A list clients have answered keeps every box it was saved with. */
	function lockedBoxes(item: DraftItem): ReadonlySet<string> {
		if (item.fact_key === null || !answered.has(item.fact_key)) return new Set();
		return new Set(item.list_fields.flatMap((field) => (field.key ? [field.key] : [])));
	}

	/** A pick or reuse clients have answered keeps its list or question: their answers name it. */
	function sourceLocked(item: DraftItem) {
		return item.fact_key !== null && answered.has(item.fact_key);
	}

	/** The list a pick names when it is no longer one it can pick from — moved below it, or retyped. */
	function strayPickList(item: DraftItem, sources: { id: string }[]) {
		if (!item.pick_from || sources.some((source) => source.id === item.pick_from)) return null;
		const here = items.find((each) => each.rowId === item.pick_from);
		return here?.label.trim() || 'Its list';
	}

	/** A5g: the question a reuse names when it can no longer reuse it — moved below it, or given a rule. */
	function strayReuse(item: DraftItem, sources: { id: string }[]) {
		if (!item.reuse_from || sources.some((source) => source.id === item.reuse_from)) return null;
		const here = items.find((each) => each.rowId === item.reuse_from);
		return here?.label.trim() || 'Its question';
	}

	const pickNumber = (item: DraftItem, field: 'min_choices' | 'max_choices') => ({
		get: () => item[field],
		set: (value: unknown) => (item[field] = typeof value === 'number' ? value : null)
	});

	function kindName(item: DraftItem) {
		return item.kind ? SETUP_QUESTION_KIND_LABELS[item.kind] : 'No answer type';
	}

	function move(index: number, by: -1 | 1) {
		const target = index + by;
		[items[index], items[target]] = [items[target], items[index]];
	}

	function remove(index: number) {
		if (items[index].rowId === openRow) openRow = null;
		items.splice(index, 1);
	}

	function toggle(rowId: string) {
		openRow = openRow === rowId ? null : rowId;
	}

	function setKind(item: DraftItem, value: string) {
		item.kind = value as DraftItem['kind'];
		if (isChoiceKind(item.kind) && item.options.length === 0) {
			addChoice(item);
			addChoice(item);
		}
	}

	function addChoice(item: DraftItem) {
		newChoices += 1;
		item.options.push({ rowId: `new-choice-${newChoices}`, value: null, label: '' });
	}

	/** Adds a choice and puts the cursor in it, so the next one can be typed straight away. */
	async function addAndFocusChoice(item: DraftItem) {
		addChoice(item);
		const id = `setup-item-${item.rowId}-choice-new-choice-${newChoices}`;
		await tick();
		list?.querySelector<HTMLInputElement>(`#${CSS.escape(id)}`)?.focus();
	}

	/** Opens a newly added row and puts the cursor in its first box. */
	export async function openNew(rowId: string) {
		openRow = rowId;
		await tick();
		list?.querySelector<HTMLInputElement>(`#setup-item-${rowId}-label`)?.focus();
	}

	/** Opens the first row with a problem so its message is on screen. */
	export function openFirstError() {
		// A saved question's row id is its key, which has dots of its own; the field is after the last one.
		const key = Object.keys(errors)[0];
		if (key) openRow = key.slice(0, key.lastIndexOf('.'));
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if items.length === 0}
	<p class="setup-questions__empty">
		No questions yet. Clients won't see this stage until it has at least one question.
	</p>
{/if}

<ol class="setup-questions" bind:this={list}>
	{#each items as item, index (item.rowId)}
		{@const isOpen = openRow === item.rowId}
		{@const name =
			item.label.trim() || (item.type === 'heading' ? 'this heading' : 'this question')}
		{@const rowHasError = Object.keys(errors).some((key) => key.startsWith(`${item.rowId}.`))}
		<li
			class="setup-questions__row"
			class:setup-questions__row--heading={item.type === 'heading'}
			class:setup-questions__row--open={isOpen}
			class:setup-questions__row--invalid={rowHasError}
		>
			<div class="setup-questions__summary">
				<button
					type="button"
					class="setup-questions__toggle"
					aria-expanded={isOpen}
					aria-controls={`setup-item-${item.rowId}-editor`}
					onclick={() => toggle(item.rowId)}
				>
					{#if item.type === 'heading'}
						<span class="setup-questions__heading-icon" aria-hidden="true">{@html headingIcon}</span
						>
					{/if}
					<span class="setup-questions__text">
						<span class="setup-questions__label">
							{item.label.trim() || (item.type === 'heading' ? 'New heading' : 'New question')}
						</span>
						{#if item.type === 'question'}
							<span class="setup-questions__meta">
								{#if !item.built_in}<span>{kindName(item)}</span>{/if}
								{#if item.required}<Badge status="informative" size="small">Required</Badge>{/if}
								{#if item.can_defer}<span>Can be skipped for now</span>{/if}
								{#if item.show_if.length}
									<span class="setup-questions__lock">
										<span class="setup-questions__meta-icon" aria-hidden="true"
											>{@html gitBranchIcon}</span
										>Shown only when its rules match
									</span>
								{/if}
								{#if item.built_in}
									<span class="setup-questions__lock">
										<span class="setup-questions__meta-icon" aria-hidden="true"
											>{@html lockIcon}</span
										>Built in
									</span>
								{/if}
								{#if item.fact_key === null}
									<Badge status="informative" size="small">New</Badge>
								{/if}
							</span>
						{:else}
							<span class="setup-questions__meta"><span>Heading</span></span>
						{/if}
					</span>
					<span class="setup-questions__chevron" aria-hidden="true">{@html chevronDownIcon}</span>
				</button>

				<div class="setup-questions__actions">
					<button
						type="button"
						class="setup-questions__icon-button"
						aria-label={`Move ${name} earlier`}
						disabled={index === 0}
						onclick={() => move(index, -1)}>{@html arrowUpIcon}</button
					>
					<button
						type="button"
						class="setup-questions__icon-button"
						aria-label={`Move ${name} later`}
						disabled={index === items.length - 1}
						onclick={() => move(index, 1)}>{@html arrowDownIcon}</button
					>
					{#if !item.built_in}
						<button
							type="button"
							class="setup-questions__icon-button setup-questions__icon-button--danger"
							aria-label={`Remove ${name}`}
							onclick={() => remove(index)}>{@html trashIcon}</button
						>
					{/if}
				</div>
			</div>

			{#if isOpen}
				<div class="setup-questions__editor" id={`setup-item-${item.rowId}-editor`}>
					{#if item.type === 'heading'}
						<Input
							id={`setup-item-${item.rowId}-label`}
							label="Heading"
							maxlength={200}
							bind:value={item.label}
							invalid={Boolean(errors[`${item.rowId}.label`])}
							errorMessage={errors[`${item.rowId}.label`] ?? ''}
						/>
						<Input
							id={`setup-item-${item.rowId}-hint`}
							label="Line under the heading (optional)"
							maxlength={300}
							bind:value={item.hint}
							invalid={Boolean(errors[`${item.rowId}.hint`])}
							errorMessage={errors[`${item.rowId}.hint`] ?? ''}
						/>
					{:else}
						<Input
							id={`setup-item-${item.rowId}-label`}
							label="Question"
							maxlength={200}
							bind:value={item.label}
							invalid={Boolean(errors[`${item.rowId}.label`])}
							errorMessage={errors[`${item.rowId}.label`] ?? ''}
						/>
						<Input
							id={`setup-item-${item.rowId}-hint`}
							label="Help line (optional)"
							maxlength={300}
							bind:value={item.hint}
							invalid={Boolean(errors[`${item.rowId}.hint`])}
							errorMessage={errors[`${item.rowId}.hint`] ?? ''}
						/>

						{#if item.built_in}
							<p class="setup-questions__note">
								<span class="setup-questions__meta-icon" aria-hidden="true">{@html lockIcon}</span>
								The CRM copies this answer into the client's settings, so you can reword and move it but
								not remove it or change its answer type.
							</p>
						{:else}
							<div class="setup-questions__kind">
								<Select
									id={`setup-item-${item.rowId}-kind`}
									label="Answer type"
									placeholder="Choose an answer type"
									options={kindOptions}
									value={item.kind ?? ''}
									disabled={kindLocked(item)}
									onchange={(value: string) => setKind(item, value)}
								/>
								{#if errors[`${item.rowId}.kind`]}
									<p class="setup-questions__error" role="alert">{errors[`${item.rowId}.kind`]}</p>
								{:else if kindLocked(item)}
									<p class="setup-questions__hint">
										Clients have answered this, so its answer type stays. To ask it another way, add
										a new question.
									</p>
								{/if}
							</div>

							{#if isChoiceKind(item.kind)}
								<fieldset class="setup-questions__choices">
									<legend>Choices</legend>
									{#each item.options as option, choiceIndex (option.rowId)}
										<div class="setup-questions__choice">
											<Input
												id={`setup-item-${item.rowId}-choice-${option.rowId}`}
												label={`Choice ${choiceIndex + 1}`}
												maxlength={100}
												bind:value={option.label}
											/>
											<button
												type="button"
												class="setup-questions__icon-button setup-questions__icon-button--danger"
												aria-label={`Remove choice ${choiceIndex + 1}`}
												disabled={item.options.length <= 2}
												onclick={() => item.options.splice(choiceIndex, 1)}>{@html xIcon}</button
											>
										</div>
									{/each}
									{#if errors[`${item.rowId}.options`]}
										<p class="setup-questions__error" role="alert">
											{errors[`${item.rowId}.options`]}
										</p>
									{/if}
									<div>
										<Button
											size="small"
											variant="secondary"
											disabled={item.options.length >= 50}
											onclick={() => addAndFocusChoice(item)}
											><span class="setup-questions__button-icon" aria-hidden="true"
												>{@html plusIcon}</span
											>Add choice</Button
										>
									</div>
									<Toggle
										id={`setup-item-${item.rowId}-other`}
										label="Add “Other”"
										description="Clients can pick “Other” and type their own answer."
										bind:checked={item.allow_other}
									/>
									{#if item.kind === 'multi_choice'}
										<div class="setup-questions__most">
											<Input
												id={`setup-item-${item.rowId}-most`}
												label="Most ticks allowed (optional)"
												type="number"
												inputmode="numeric"
												min={1}
												max={item.options.length + (item.allow_other ? 1 : 0)}
												bind:value={
													() => item.max_choices,
													(value) => (item.max_choices = typeof value === 'number' ? value : null)
												}
												invalid={Boolean(errors[`${item.rowId}.max_choices`])}
												errorMessage={errors[`${item.rowId}.max_choices`] ?? ''}
											/>
											{#if !errors[`${item.rowId}.max_choices`]}
												<p class="setup-questions__hint">
													Leave empty to let clients tick as many as apply. For “Choose up to
													three”, enter 3.
												</p>
											{/if}
										</div>
									{/if}
								</fieldset>
							{/if}

							{#if item.kind === 'file'}
								<fieldset class="setup-questions__choices">
									<legend>Clients can add</legend>
									{#each SETUP_FILE_KINDS as fileKind (fileKind)}
										<Checkbox
											id={`setup-item-${item.rowId}-file-${fileKind}`}
											label={SETUP_FILE_KIND_LABELS[fileKind].label}
											description={SETUP_FILE_KIND_LABELS[fileKind].formats}
											checked={item.file_kinds.includes(fileKind)}
											invalid={Boolean(errors[`${item.rowId}.file_kinds`])}
											onchange={(ticked) => setFileKind(item, fileKind, ticked)}
										/>
									{/each}
									{#if errors[`${item.rowId}.file_kinds`]}
										<p class="setup-questions__error" role="alert">
											{errors[`${item.rowId}.file_kinds`]}
										</p>
									{/if}
									<div class="setup-questions__most">
										<Select
											id={`setup-item-${item.rowId}-max-files`}
											label="How many files"
											options={maxFilesOptions}
											value={String(item.max_files)}
											onchange={(value: string) => (item.max_files = Number(value))}
										/>
										{#if errors[`${item.rowId}.max_files`]}
											<p class="setup-questions__error" role="alert">
												{errors[`${item.rowId}.max_files`]}
											</p>
										{:else}
											<p class="setup-questions__hint">
												Each file can be up to 100 MB. Clients can also take a photo on their phone.
											</p>
										{/if}
									</div>
								</fieldset>
							{/if}

							{#if item.kind === 'list'}
								<SetupListBoxes
									idPrefix={`setup-item-${item.rowId}`}
									bind:fields={item.list_fields}
									bind:maxRows={item.max_rows}
									isNew={item.fact_key === null}
									lockedKeys={lockedBoxes(item)}
									fieldsError={errors[`${item.rowId}.list_fields`] ?? ''}
									maxRowsError={errors[`${item.rowId}.max_rows`] ?? ''}
								/>
							{/if}

							{#if item.kind === 'pick'}
								{@const sources = pickSources(earlierStages, items, index)}
								{@const fewest = pickNumber(item, 'min_choices')}
								{@const most = pickNumber(item, 'max_choices')}
								{@const stray = strayPickList(item, sources)}
								<fieldset class="setup-questions__choices">
									<legend>Clients pick from</legend>
									{#if sources.length === 0 && !item.pick_from}
										<p class="setup-questions__hint">
											There's no add-another list above this question yet. Add one first — for
											example “Add every service you offer” — then choose it here.
										</p>
									{:else}
										<div class="setup-questions__most">
											<Select
												id={`setup-item-${item.rowId}-pick-from`}
												label="Their answers to"
												placeholder="Choose a list"
												options={sources.map((source) => ({
													value: source.id,
													label: source.stageTitle
														? `${source.label} (${source.stageTitle})`
														: source.label
												}))}
												value={item.pick_from ?? ''}
												disabled={sourceLocked(item)}
												onchange={(value: string) => (item.pick_from = value || null)}
											/>
											{#if errors[`${item.rowId}.pick_from`]}
												<p class="setup-questions__error" role="alert">
													{errors[`${item.rowId}.pick_from`]}
												</p>
											{:else if stray}
												<p class="setup-questions__error">
													“{stray}” is no longer an add-another list above this question. Move this
													question back below it, or choose another list.
												</p>
											{:else if sourceLocked(item)}
												<p class="setup-questions__hint">
													Clients have answered this, so it keeps its list.
												</p>
											{:else}
												<p class="setup-questions__hint">
													Each client sees the entries they added there, named by the list's first
													box.
												</p>
											{/if}
										</div>
									{/if}
									<div class="setup-questions__range">
										<Input
											id={`setup-item-${item.rowId}-fewest`}
											label="Fewest (optional)"
											type="number"
											inputmode="numeric"
											min={1}
											max={50}
											bind:value={fewest.get, fewest.set}
											invalid={Boolean(errors[`${item.rowId}.min_choices`])}
											errorMessage={errors[`${item.rowId}.min_choices`] ?? ''}
										/>
										<Input
											id={`setup-item-${item.rowId}-most`}
											label="Most (optional)"
											type="number"
											inputmode="numeric"
											min={1}
											max={50}
											bind:value={most.get, most.set}
											invalid={Boolean(errors[`${item.rowId}.max_choices`])}
											errorMessage={errors[`${item.rowId}.max_choices`] ?? ''}
										/>
									</div>
									<p class="setup-questions__hint">
										For “Choose 3 to 5”, enter 3 and 5. A client with fewer entries than the fewest
										picks all of them.
									</p>
									<Toggle
										id={`setup-item-${item.rowId}-ordered`}
										label="Clients put them in order"
										description="Their picks show numbered, with buttons to move each one up or down."
										bind:checked={item.ordered}
									/>
								</fieldset>
							{/if}

							{#if item.kind === 'reuse'}
								{@const sources = reuseSources(earlierStages, items, index)}
								{@const stray = strayReuse(item, sources)}
								<fieldset class="setup-questions__choices">
									<legend>Clients confirm their answer to</legend>
									{#if sources.length === 0 && !item.reuse_from}
										<p class="setup-questions__hint">
											There's no question above this one whose answer can be shown back. Add one
											first — for example a phone number — then choose it here.
										</p>
									{:else}
										<div class="setup-questions__most">
											<Select
												id={`setup-item-${item.rowId}-reuse-from`}
												label="Earlier question"
												placeholder="Choose a question"
												options={sources.map((source) => ({
													value: source.id,
													label: source.stageTitle
														? `${source.label} (${source.stageTitle})`
														: source.label
												}))}
												value={item.reuse_from ?? ''}
												disabled={sourceLocked(item)}
												onchange={(value: string) => (item.reuse_from = value || null)}
											/>
											{#if errors[`${item.rowId}.reuse_from`]}
												<p class="setup-questions__error" role="alert">
													{errors[`${item.rowId}.reuse_from`]}
												</p>
											{:else if stray}
												<p class="setup-questions__error">
													“{stray}” can no longer be reused here: it must sit above this question
													and be asked of everyone. Move it back, or choose another question.
												</p>
											{:else if sourceLocked(item)}
												<p class="setup-questions__hint">
													Clients have answered this, so it keeps its question.
												</p>
											{:else}
												<p class="setup-questions__hint">
													Clients see what they told you there and pick “Yes, use this” or “Use a
													different one here”. A client who hasn't answered it is simply asked.
												</p>
											{/if}
										</div>
									{/if}
								</fieldset>
							{/if}
						{/if}

						<SetupShowIf
							bind:conditions={item.show_if}
							sources={showIfSources(earlierStages, items, index)}
							{services}
							idPrefix={`setup-item-${item.rowId}`}
							error={errors[`${item.rowId}.show_if`] ?? ''}
						/>

						<div class="setup-questions__switches">
							<Toggle
								id={`setup-item-${item.rowId}-required`}
								label="Required"
								description="The stage can't be marked done until this has an answer."
								bind:checked={item.required}
							/>
							<Toggle
								id={`setup-item-${item.rowId}-defer`}
								label="Offer “I don't have this yet” and “I need Uplift's help”"
								description="Either one counts as an answer, and asking for help lets Uplift know."
								bind:checked={item.can_defer}
							/>
						</div>

						{#if item.fact_key !== null && answered.has(item.fact_key)}
							<p class="setup-questions__hint">
								Removing this question hides it from clients. Answers already given are kept.
							</p>
						{/if}
					{/if}
				</div>
			{/if}
		</li>
	{/each}
</ol>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-questions {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;

		&__empty {
			margin: 0 0 var(--space-base);
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__row {
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			transition: border-color var(--timing-quick) ease-out;

			&--heading {
				margin-top: var(--space-small);
				background: var(--color-surface--background);
			}

			&--open {
				border-color: var(--color-border--interactive);
			}

			&--invalid {
				border-color: var(--color-critical);
			}
		}

		&__summary {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-small) var(--space-small) 0;
		}

		&__toggle {
			display: flex;
			flex: 1 1 auto;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
			padding: var(--space-smallest) var(--space-base);
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: inherit;
			font: inherit;
			text-align: left;
			cursor: pointer;

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:hover .setup-questions__label {
				color: var(--color-interactive);
			}
		}

		&__heading-icon,
		&__chevron,
		&__meta-icon {
			display: inline-grid;
			flex: 0 0 auto;
			place-items: center;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__chevron {
			margin-left: auto;
			transition: transform var(--timing-quick) ease-out;
		}

		&__row--open &__chevron {
			transform: rotate(180deg);
		}

		&__text {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			min-width: 0;
		}

		&__label {
			color: var(--color-heading);
			font-weight: 600;
			line-height: var(--typography--lineHeight-tight);
			overflow-wrap: anywhere;
			transition: color var(--timing-quick) ease-out;
		}

		&__row--heading &__label {
			font-size: var(--typography--fontSize-large);
		}

		&__meta {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-smallest) var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__lock {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smallest);
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			gap: var(--space-smallest);
		}

		&__editor {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			padding: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__kind {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			max-width: 320px;
		}

		&__choices {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			border: 0;

			legend {
				margin-bottom: var(--space-small);
				color: var(--color-heading);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}
		}

		&__choice {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			max-width: 480px;

			> :global(:first-child) {
				flex: 1 1 auto;
			}
		}

		&__most {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			max-width: 32rem;
		}

		&__range {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-small);
			max-width: 32rem;
		}

		&__switches {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__note,
		&__hint,
		&__error {
			margin: 0;
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
			color: var(--color-text--secondary);
		}

		&__hint {
			color: var(--color-text--secondary);
		}

		&__error {
			color: var(--color-critical--onSurface);
			font-weight: 600;
		}

		&__icon-button {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: var(--border-base) solid transparent;
			border-radius: var(--radius-base);
			color: var(--color-icon--secondary);
			background: none;
			cursor: pointer;
			transition: all var(--timing-quick) ease-out;

			&:hover:not(:disabled),
			&:focus-visible:not(:disabled) {
				border-color: var(--color-border--interactive);
				color: var(--color-interactive);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}

			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
			}

			&--danger:hover:not(:disabled),
			&--danger:focus-visible:not(:disabled) {
				border-color: var(--color-critical);
				color: var(--color-critical);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__button-icon {
			display: inline-grid;
			place-items: center;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}

	@media (max-width: 639px) {
		.setup-questions__summary {
			flex-wrap: wrap;
			padding: var(--space-small);
		}

		.setup-questions__toggle {
			flex-basis: 100%;
			padding: var(--space-smallest);
		}

		.setup-questions__actions {
			margin-left: auto;
		}
	}
</style>
