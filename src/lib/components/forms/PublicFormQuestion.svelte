<script lang="ts">
	import type { Snippet } from 'svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import type { FormQuestion } from '$lib/forms/types';

	// One contractor-written question as a customer answers it, on any public page that asks them. Photo
	// questions need their page's own upload path, so the page draws that control through `imageUpload`.
	let {
		question,
		value = $bindable(),
		imageUpload
	}: {
		question: FormQuestion;
		value: unknown;
		imageUpload?: Snippet<[FormQuestion]>;
	} = $props();

	const id = $derived(`q-${question.id}`);
	const options = $derived(question.options ?? []);
	const list = $derived(Array.isArray(value) ? (value as string[]) : []);

	function toggle(option: string, checked: boolean) {
		value = checked ? [...list, option] : list.filter((item) => item !== option);
	}
</script>

<div class="form-question">
	<span class="form-question__label">
		{question.label}{#if question.required}<em>*</em>{/if}
	</span>
	{#if question.help}<span class="form-question__help">{question.help}</span>{/if}

	{#if question.type === 'short_text'}
		<Input
			{id}
			label=""
			value={(value as string) ?? ''}
			oninput={(event: Event) => (value = (event.currentTarget as HTMLInputElement).value)}
		/>
	{:else if question.type === 'long_text'}
		<Textarea
			{id}
			label=""
			rows={3}
			value={(value as string) ?? ''}
			oninput={(event: Event) => (value = (event.currentTarget as HTMLTextAreaElement).value)}
		/>
	{:else if question.type === 'number'}
		<Input
			{id}
			label=""
			type="number"
			value={(value as number | '') ?? ''}
			oninput={(event: Event) => {
				const typed = (event.currentTarget as HTMLInputElement).value;
				value = typed === '' ? '' : Number(typed);
			}}
		/>
	{:else if question.type === 'dropdown'}
		<Select
			{id}
			ariaLabel={question.label}
			placeholder="Choose…"
			options={options.map((option) => ({ value: option, label: option }))}
			value={(value as string) ?? ''}
			onchange={(chosen) => (value = chosen)}
		/>
	{:else if question.type === 'dropdown_multi' || question.type === 'checkbox'}
		<div class="form-question__choices">
			{#each options as option (option)}
				<label class="form-question__choice">
					<input
						type="checkbox"
						checked={list.includes(option)}
						onchange={(event) => toggle(option, event.currentTarget.checked)}
					/>
					{option}
				</label>
			{/each}
		</div>
	{:else if question.type === 'radio'}
		<div class="form-question__choices">
			{#each options as option (option)}
				<label class="form-question__choice">
					<input
						type="radio"
						name={id}
						value={option}
						checked={value === option}
						onchange={() => (value = option)}
					/>
					{option}
				</label>
			{/each}
		</div>
	{:else if question.type === 'yes_no'}
		<div class="form-question__choices form-question__choices--row">
			<label class="form-question__choice">
				<input type="radio" name={id} checked={value === true} onchange={() => (value = true)} />
				Yes
			</label>
			<label class="form-question__choice">
				<input type="radio" name={id} checked={value === false} onchange={() => (value = false)} />
				No
			</label>
		</div>
	{:else if question.type === 'image_upload'}
		{@render imageUpload?.(question)}
	{/if}
</div>

<style lang="scss">
	.form-question {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			em {
				margin-left: var(--space-smallest);
				color: var(--color-critical);
				font-style: normal;
			}
		}

		&__help {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__choices {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);

			&--row {
				flex-direction: row;
				gap: var(--space-large);
			}
		}

		&__choice {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text);
			font-size: var(--typography--fontSize-base);
			cursor: pointer;
		}
	}
</style>
