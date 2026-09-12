<script lang="ts">
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import {
		FORM_MAX_OPTIONS,
		FORM_OPTION_MAX,
		FORM_QUESTION_HELP_MAX,
		FORM_QUESTION_LABEL_MAX,
		FORM_QUESTION_TYPES,
		isChoiceQuestion,
		type FormQuestion,
		type FormQuestionType
	} from '$lib/forms/types';
	import { FORM_QUESTION_TYPE_LABELS } from '$lib/forms/labels';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';

	// Edits one question in the rail. The type picker reshapes the question: switching to a choice type seeds
	// an empty option so there is always a row to type into, and switching away drops the options so the saved
	// content never carries options on a non-choice question (the API's Zod refuses that). The options array
	// is owned by the builder page and edited through callbacks — a child reassigning an array on this plain
	// prop would update `content` but not re-render this component.
	let {
		question,
		index,
		count,
		onMove,
		onRemove,
		onChangeType,
		onAddOption,
		onRemoveOption
	}: {
		question: FormQuestion;
		index: number;
		count: number;
		onMove: (by: number) => void;
		onRemove: () => void;
		onChangeType: (type: FormQuestionType) => void;
		onAddOption: () => void;
		onRemoveOption: (i: number) => void;
	} = $props();

	const typeOptions = FORM_QUESTION_TYPES.map((type) => ({
		value: type,
		label: FORM_QUESTION_TYPE_LABELS[type]
	}));

	const isChoice = $derived(isChoiceQuestion(question.type));
</script>

<li class="question-editor">
	<div class="question-editor__grid">
		<Input
			id={`q-label-${question.id}`}
			label={`Question ${index + 1}`}
			bind:value={question.label}
			maxlength={FORM_QUESTION_LABEL_MAX}
			placeholder="What would you like done?"
		/>
		<Select
			id={`q-type-${question.id}`}
			label="Answer type"
			options={typeOptions}
			value={question.type}
			onchange={(next) => onChangeType(next as FormQuestionType)}
		/>
	</div>

	{#if isChoice}
		<div class="question-editor__options">
			<span class="question-editor__options-label">Options</span>
			{#each question.options ?? [] as _, i (i)}
				<div class="question-editor__option-row">
					<Input
						id={`q-${question.id}-opt-${i}`}
						label={`Option ${i + 1}`}
						bind:value={question.options![i]}
						maxlength={FORM_OPTION_MAX}
						placeholder="Type an option"
					/>
					<button
						type="button"
						class="question-editor__icon-button question-editor__icon-button--danger"
						aria-label={`Remove option ${i + 1}`}
						onclick={() => onRemoveOption(i)}
					>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html trashIcon}
					</button>
				</div>
			{/each}
			<button
				type="button"
				class="question-editor__add-option"
				disabled={(question.options?.length ?? 0) >= FORM_MAX_OPTIONS}
				onclick={onAddOption}
			>
				<span class="question-editor__button-icon" aria-hidden="true">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html plusIcon}
				</span>
				Add option
			</button>
		</div>
	{/if}

	<Input
		id={`q-help-${question.id}`}
		label="Helper text (optional)"
		bind:value={question.help}
		maxlength={FORM_QUESTION_HELP_MAX}
		placeholder="A short hint shown under the question"
	/>

	<div class="question-editor__footer">
		<Checkbox id={`q-required-${question.id}`} label="Required" bind:checked={question.required} />
		<div class="question-editor__actions">
			<button
				type="button"
				class="question-editor__icon-button"
				aria-label={`Move question ${index + 1} up`}
				disabled={index === 0}
				onclick={() => onMove(-1)}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html arrowUpIcon}
			</button>
			<button
				type="button"
				class="question-editor__icon-button"
				aria-label={`Move question ${index + 1} down`}
				disabled={index === count - 1}
				onclick={() => onMove(1)}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html arrowDownIcon}
			</button>
			<button
				type="button"
				class="question-editor__icon-button question-editor__icon-button--danger"
				aria-label={`Remove question ${index + 1}`}
				onclick={onRemove}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html trashIcon}
			</button>
		</div>
	</div>
</li>

<style lang="scss">
	.question-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface);

		&__grid {
			display: grid;
			grid-template-columns: minmax(0, 1fr);
			gap: var(--space-small);
		}

		&__options {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-slim);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
		}

		&__options-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__option-row {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(.field) {
				flex: 1;
			}
		}

		&__add-option {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			align-self: flex-start;
			padding: var(--space-smaller) var(--space-small);
			border: none;
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: none;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover:not(:disabled) {
				background: var(--color-interactive--background--subtle--hover);
			}
			&:disabled {
				color: var(--color-disabled);
				cursor: not-allowed;
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

		&__footer {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__actions {
			display: flex;
			gap: var(--space-smaller);
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

			:global(svg) {
				width: 16px;
				height: 16px;
			}

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
	}
</style>
