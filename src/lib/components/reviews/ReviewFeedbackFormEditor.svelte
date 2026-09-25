<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import FormQuestionEditor from '$lib/components/settings/forms/FormQuestionEditor.svelte';
	import { FORM_MAX_OPTIONS, isChoiceQuestion, type FormQuestionType } from '$lib/forms/types';
	import {
		REVIEW_FEEDBACK_HEADING_MAX,
		REVIEW_FEEDBACK_INTRO_MAX,
		REVIEW_FEEDBACK_MAX_QUESTIONS,
		REVIEW_FEEDBACK_QUESTION_TYPES,
		REVIEW_THANK_YOU_MESSAGE_MAX,
		REVIEW_THANK_YOU_TITLE_MAX,
		type ReviewFeedbackForm
	} from '$lib/reviews/settings';
	import messageIcon from '@tabler/icons/outline/message-2.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// The private-feedback form a customer fills in instead of (or before) a public review. The contractor can
	// reword it and add, remove and reorder questions; the job, client and rating are already known, so the
	// form never asks for them. Questions reuse the request-form question editor.
	let {
		form = $bindable(),
		disabled = false,
		fieldErrors = {}
	}: {
		form: ReviewFeedbackForm;
		disabled?: boolean;
		fieldErrors?: Record<string, string>;
	} = $props();

	const canAdd = $derived(form.questions.length < REVIEW_FEEDBACK_MAX_QUESTIONS);

	const questionErrors = $derived(
		Object.entries(fieldErrors)
			.filter(([path]) => path.startsWith('feedback_form.questions'))
			.map(([, message]) => message)
	);

	function addQuestion() {
		if (!canAdd) return;
		form.questions = [
			...form.questions,
			{ id: crypto.randomUUID(), type: 'long_text', label: '', required: false, help: '' }
		];
	}

	function moveQuestion(from: number, by: number) {
		const target = from + by;
		if (target < 0 || target >= form.questions.length) return;
		const next = [...form.questions];
		[next[from], next[target]] = [next[target], next[from]];
		form.questions = next;
	}

	function removeQuestion(from: number) {
		form.questions = form.questions.filter((_, i) => i !== from);
	}

	function changeType(index: number, type: FormQuestionType) {
		const question = form.questions[index];
		if (!question) return;
		question.type = type;
		if (isChoiceQuestion(type)) {
			if (!question.options || question.options.length === 0) question.options = [''];
		} else {
			delete question.options;
		}
	}

	function addOption(index: number) {
		const question = form.questions[index];
		if (!question) return;
		const options = question.options ?? [];
		if (options.length >= FORM_MAX_OPTIONS) return;
		question.options = [...options, ''];
	}

	function removeOption(index: number, option: number) {
		const question = form.questions[index];
		if (!question?.options) return;
		question.options = question.options.filter((_, i) => i !== option);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	title="Private feedback form"
	hint="Where a customer tells you privately what happened. Answers become a follow-up item for your team."
	icon={messageIcon}
	form
	level={3}
>
	<div class="feedback-editor">
		<Input
			id="review-feedback-heading"
			label="Heading"
			bind:value={form.heading}
			maxlength={REVIEW_FEEDBACK_HEADING_MAX}
			invalid={Boolean(fieldErrors['feedback_form.heading'])}
			errorMessage={fieldErrors['feedback_form.heading']}
			{disabled}
		/>
		<Textarea
			id="review-feedback-intro"
			label="Introduction (optional)"
			rows={3}
			bind:value={form.intro}
			maxlength={REVIEW_FEEDBACK_INTRO_MAX}
			{disabled}
		/>

		<div class="feedback-editor__questions">
			<h4 class="feedback-editor__subheading">Questions</h4>
			<ol class="feedback-editor__list">
				{#each form.questions as question, index (question.id)}
					<FormQuestionEditor
						{question}
						{index}
						count={form.questions.length}
						types={REVIEW_FEEDBACK_QUESTION_TYPES}
						onMove={(by) => moveQuestion(index, by)}
						onRemove={() => removeQuestion(index)}
						onChangeType={(type) => changeType(index, type)}
						onAddOption={() => addOption(index)}
						onRemoveOption={(option) => removeOption(index, option)}
					/>
				{/each}
			</ol>
			{#if questionErrors.length > 0}
				<p class="feedback-editor__error" role="alert">{questionErrors[0]}</p>
			{/if}
			<div>
				<Button
					variant="secondary"
					size="small"
					disabled={disabled || !canAdd}
					onclick={addQuestion}
				>
					<span class="feedback-editor__button-icon" aria-hidden="true">{@html plusIcon}</span>
					Add question
				</Button>
			</div>
			<p class="feedback-editor__hint">
				Up to {REVIEW_FEEDBACK_MAX_QUESTIONS} questions. The customer's name, job and rating are filled
				in for you, so there is no need to ask for them.
			</p>
		</div>

		<h4 class="feedback-editor__subheading">After they send it</h4>
		<Input
			id="review-feedback-thanks-title"
			label="Thank-you title"
			bind:value={form.thank_you_title}
			maxlength={REVIEW_THANK_YOU_TITLE_MAX}
			invalid={Boolean(fieldErrors['feedback_form.thank_you_title'])}
			errorMessage={fieldErrors['feedback_form.thank_you_title']}
			{disabled}
		/>
		<Textarea
			id="review-feedback-thanks-message"
			label="Thank-you message (optional)"
			rows={3}
			bind:value={form.thank_you_message}
			maxlength={REVIEW_THANK_YOU_MESSAGE_MAX}
			{disabled}
		/>
	</div>
</SectionBlock>

<style lang="scss">
	.feedback-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__questions {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
		}

		&__subheading {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}

		&__list {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__button-icon {
			display: inline-grid;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
