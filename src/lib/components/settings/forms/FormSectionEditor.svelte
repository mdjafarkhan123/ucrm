<script lang="ts">
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import DropdownMenu from '$lib/components/ui/DropdownMenu.svelte';
	import FormQuestionEditor from './FormQuestionEditor.svelte';
	import {
		FORM_QUESTION_TYPES,
		FORM_SECTION_TITLE_MAX,
		type FormQuestionType,
		type FormSection
	} from '$lib/forms/types';
	import { FORM_QUESTION_TYPE_LABELS } from '$lib/forms/labels';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';

	// One section of the form: a title and its questions. The global 20-question cap is owned by the builder
	// page, which passes `canAddQuestion` — this component only adds within that budget. Question-array edits
	// (add/move/remove, type change, options) are all owned by the builder page and passed down as callbacks;
	// a child reassigning an array on this plain prop would update `content` but not re-render this component.
	let {
		section,
		index,
		count,
		canAddQuestion,
		onMove,
		onRemove,
		onAddQuestion,
		onMoveQuestion,
		onRemoveQuestion,
		onChangeQuestionType,
		onAddOption,
		onRemoveOption
	}: {
		section: FormSection;
		index: number;
		count: number;
		canAddQuestion: boolean;
		onMove: (by: number) => void;
		onRemove: () => void;
		onAddQuestion: (type: FormQuestionType) => void;
		onMoveQuestion: (qi: number, by: number) => void;
		onRemoveQuestion: (qi: number) => void;
		onChangeQuestionType: (qi: number, type: FormQuestionType) => void;
		onAddOption: (qi: number) => void;
		onRemoveOption: (qi: number, i: number) => void;
	} = $props();

	const addItems = FORM_QUESTION_TYPES.map((type) => ({
		label: FORM_QUESTION_TYPE_LABELS[type],
		onSelect: () => {
			if (!canAddQuestion) return;
			onAddQuestion(type);
		}
	}));
</script>

<section class="section-editor">
	<header class="section-editor__head">
		<Input
			id={`section-title-${section.id}`}
			label="Section title"
			bind:value={section.title}
			maxlength={FORM_SECTION_TITLE_MAX}
			placeholder="e.g. About the job"
		/>
		<div class="section-editor__head-actions">
			<Button
				variant="secondary"
				size="small"
				iconOnly
				label={`Move section ${index + 1} up`}
				disabled={index === 0}
				onclick={() => onMove(-1)}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html arrowUpIcon}
			</Button>
			<Button
				variant="secondary"
				size="small"
				iconOnly
				label={`Move section ${index + 1} down`}
				disabled={index === count - 1}
				onclick={() => onMove(1)}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html arrowDownIcon}
			</Button>
			<Button
				variant="secondary"
				size="small"
				variation="destructive"
				iconOnly
				label={`Remove section ${index + 1}`}
				onclick={onRemove}
			>
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				{@html trashIcon}
			</Button>
		</div>
	</header>

	{#if section.questions.length === 0}
		<p class="section-editor__empty">No questions yet — add one below.</p>
	{:else}
		<ol class="section-editor__questions">
			{#each section.questions as question, qi (question.id)}
				<FormQuestionEditor
					{question}
					index={qi}
					count={section.questions.length}
					onMove={(by) => onMoveQuestion(qi, by)}
					onRemove={() => onRemoveQuestion(qi)}
					onChangeType={(type) => onChangeQuestionType(qi, type)}
					onAddOption={() => onAddOption(qi)}
					onRemoveOption={(i) => onRemoveOption(qi, i)}
				/>
			{/each}
		</ol>
	{/if}

	<div class="section-editor__add">
		<DropdownMenu
			items={addItems}
			triggerLabel="Add a question"
			triggerText="Add a question"
			triggerLeadingIcon={plusIcon}
			triggerChevron={false}
			align="start"
			disabled={!canAddQuestion}
		/>
	</div>
	{#if !canAddQuestion}
		<p class="section-editor__cap">You’ve reached the 20-question limit for this form.</p>
	{/if}
</section>

<style lang="scss">
	.section-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface--background--subtle);

		&__head {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(.field) {
				flex: 1;
			}
		}

		&__head-actions {
			display: flex;
			gap: var(--space-smaller);
		}

		&__questions {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__cap {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
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

	.section-editor__add {
		display: flex;
	}
</style>
