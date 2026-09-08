<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import {
		createChecklistTemplate,
		updateChecklistTemplate,
		type ChecklistTemplateDraftItem
	} from '$lib/checklists/api';
	import {
		CHECKLIST_ITEM_TYPES,
		CHECKLIST_ITEM_TYPE_LABELS,
		CHECKLIST_MAX_QUESTIONS,
		type ChecklistItemType,
		type ChecklistTemplate
	} from '$lib/checklists/types';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';

	let {
		open,
		template,
		onSaved,
		onClose
	}: {
		open: boolean;
		/** Null builds a new checklist; a template edits that one. */
		template: ChecklistTemplate | null;
		onSaved: (result: { jobsAlreadyUsing: number }) => void;
		onClose: () => void;
	} = $props();

	/** One question while it is being written. `key` only exists to keep the list stable as rows move. */
	type DraftQuestion = {
		key: string;
		label: string;
		item_type: ChecklistItemType;
		required: boolean;
		/** Kept as one line of comma-separated choices — how a person actually types a short list. */
		options: string;
	};

	let name = $state('');
	let questions = $state<DraftQuestion[]>([]);
	let saving = $state(false);
	let error = $state('');

	function blankQuestion(): DraftQuestion {
		return {
			key: crypto.randomUUID(),
			label: '',
			item_type: 'checkbox',
			required: false,
			options: ''
		};
	}

	// Reloads the form whenever a different checklist is opened, and starts a new one with a single empty
	// question so there is always something to type into.
	$effect(() => {
		if (!open) return;
		name = template?.name ?? '';
		questions = template
			? template.items.map((item) => ({
					key: item.id,
					label: item.label,
					item_type: item.item_type,
					required: item.required,
					options: (item.options ?? []).join(', ')
				}))
			: [blankQuestion()];
		error = '';
	});

	const typeOptions = CHECKLIST_ITEM_TYPES.map((type) => ({
		value: type,
		label: CHECKLIST_ITEM_TYPE_LABELS[type]
	}));

	function choicesOf(question: DraftQuestion) {
		return question.options
			.split(',')
			.map((choice) => choice.trim())
			.filter(Boolean);
	}

	function addQuestion() {
		if (questions.length >= CHECKLIST_MAX_QUESTIONS) return;
		questions = [...questions, blankQuestion()];
	}

	function removeQuestion(key: string) {
		questions = questions.filter((question) => question.key !== key);
	}

	function move(index: number, by: number) {
		const target = index + by;
		if (target < 0 || target >= questions.length) return;
		const next = [...questions];
		[next[index], next[target]] = [next[target], next[index]];
		questions = next;
	}

	async function save() {
		if (saving) return;
		error = '';

		if (!name.trim()) {
			error = 'Give this checklist a name.';
			return;
		}
		const filled = questions.filter((question) => question.label.trim().length > 0);
		if (filled.length === 0) {
			error = 'Add at least one question.';
			return;
		}
		const missingChoices = filled.find(
			(question) => question.item_type === 'dropdown' && choicesOf(question).length === 0
		);
		if (missingChoices) {
			error = `"${missingChoices.label.trim()}" is a choose-one question, so it needs some choices — separate them with commas.`;
			return;
		}

		const items: ChecklistTemplateDraftItem[] = filled.map((question) => ({
			label: question.label.trim(),
			item_type: question.item_type,
			required: question.required,
			...(question.item_type === 'dropdown' ? { options: choicesOf(question) } : {})
		}));

		saving = true;
		try {
			if (template) {
				const result = await updateChecklistTemplate(template.id, { name: name.trim(), items });
				onSaved({ jobsAlreadyUsing: result.jobs_already_using });
			} else {
				await createChecklistTemplate({ name: name.trim(), items });
				onSaved({ jobsAlreadyUsing: 0 });
			}
		} catch (caught) {
			error = caught instanceof Error ? caught.message : 'That checklist could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<Dialog
	{open}
	title={template ? 'Edit checklist' : 'New checklist'}
	size="large"
	onClose={saving ? () => {} : onClose}
>
	<div class="checklist-builder">
		{#if error}<p class="checklist-builder__error" role="alert">{error}</p>{/if}

		<Input
			id="checklist-name"
			label="Checklist name"
			bind:value={name}
			required
			maxlength={120}
			placeholder="Lawn service"
		/>

		{#if template}
			<p class="checklist-builder__note">
				Changing these questions only affects jobs you attach this checklist to from now on. Jobs
				already using it keep the questions their crew has been answering.
			</p>
		{/if}

		<ol class="checklist-builder__list">
			{#each questions as question, index (question.key)}
				<li class="checklist-builder__row">
					<div class="checklist-builder__fields">
						<Input
							id={`question-label-${question.key}`}
							label={`Question ${index + 1}`}
							bind:value={question.label}
							maxlength={200}
							placeholder="Gate left locked"
						/>
						<Select
							id={`question-type-${question.key}`}
							label="Answer type"
							options={typeOptions}
							value={question.item_type}
							onchange={(next) => (question.item_type = next as ChecklistItemType)}
						/>
					</div>

					{#if question.item_type === 'dropdown'}
						<div>
							<Input
								id={`question-options-${question.key}`}
								label="Choices"
								bind:value={question.options}
								placeholder="Short, Medium, Long"
							/>
							<p class="checklist-builder__hint">Separate each choice with a comma.</p>
						</div>
					{/if}

					<div class="checklist-builder__row-footer">
						<Checkbox
							id={`question-required-${question.key}`}
							label="Must be answered"
							bind:checked={question.required}
						/>
						<div class="checklist-builder__row-actions">
							<button
								type="button"
								class="checklist-builder__icon-button"
								aria-label={`Move question ${index + 1} up`}
								disabled={index === 0}
								onclick={() => move(index, -1)}
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html arrowUpIcon}
							</button>
							<button
								type="button"
								class="checklist-builder__icon-button"
								aria-label={`Move question ${index + 1} down`}
								disabled={index === questions.length - 1}
								onclick={() => move(index, 1)}
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html arrowDownIcon}
							</button>
							<button
								type="button"
								class="checklist-builder__icon-button checklist-builder__icon-button--danger"
								aria-label={`Remove question ${index + 1}`}
								disabled={questions.length === 1}
								onclick={() => removeQuestion(question.key)}
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html trashIcon}
							</button>
						</div>
					</div>
				</li>
			{/each}
		</ol>

		<div>
			<Button
				variant="secondary"
				size="small"
				disabled={questions.length >= CHECKLIST_MAX_QUESTIONS}
				onclick={addQuestion}
			>
				<span class="checklist-builder__button-icon" aria-hidden="true">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html plusIcon}
				</span>
				Add question
			</Button>
		</div>

		<div class="checklist-builder__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button onclick={() => void save()} loading={saving}>Save checklist</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.checklist-builder {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__error {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			margin: var(--space-smallest) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
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
		}

		&__button-icon {
			display: inline-grid;
			place-items: center;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__fields {
			display: grid;
			grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
			gap: var(--space-small);
		}

		&__row-footer {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__row-actions {
			display: flex;
			gap: var(--space-smaller);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.checklist-builder__fields {
			grid-template-columns: 1fr;
		}
	}
</style>
