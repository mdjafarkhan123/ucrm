<script lang="ts">
	import type { Snippet } from 'svelte';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import thumbUpIcon from '@tabler/icons/outline/thumb-up.svg?raw';
	import thumbDownIcon from '@tabler/icons/outline/thumb-down.svg?raw';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import type { FormQuestion } from '$lib/forms/types';

	// One contractor-written question as a customer answers it, on any public page that asks them. Photo
	// questions need their page's own upload path, so the page draws that control through `imageUpload`.
	// Each question is its own card with its place in the form on a number tile (design `inputs.md` →
	// Questions on a public form); choices are whole tiles the customer taps.
	let {
		question,
		number,
		value = $bindable(),
		imageUpload
	}: {
		question: FormQuestion;
		/** The question's place in the form, counted by the caller across every section. */
		number: number;
		value: unknown;
		imageUpload?: Snippet<[FormQuestion]>;
	} = $props();

	const id = $derived(`q-${question.id}`);
	const labelId = $derived(`${id}-label`);
	const helpId = $derived(question.help ? `${id}-help` : undefined);
	const options = $derived(question.options ?? []);
	const list = $derived(Array.isArray(value) ? (value as string[]) : []);

	function toggle(option: string, checked: boolean) {
		value = checked ? [...list, option] : list.filter((item) => item !== option);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="form-question">
	<div class="form-question__head">
		<span class="form-question__number" aria-hidden="true">{number}</span>
		<div class="form-question__words">
			<span class="form-question__label" id={labelId}>
				{question.label}{#if question.required}<em>*</em>{/if}
			</span>
			{#if question.help}<span class="form-question__help" id={helpId}>{question.help}</span>{/if}
		</div>
	</div>

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
		<div class="form-question__choices" role="group" aria-labelledby={labelId} aria-describedby={helpId}>
			{#each options as option (option)}
				<label class="form-question__choice" class:form-question__choice--picked={list.includes(option)}>
					<input
						type="checkbox"
						checked={list.includes(option)}
						onchange={(event) => toggle(option, event.currentTarget.checked)}
					/>
					<span class="form-question__box" aria-hidden="true">{@html checkIcon}</span>
					{option}
				</label>
			{/each}
		</div>
	{:else if question.type === 'radio'}
		<div
			class="form-question__choices form-question__choices--row"
			role="radiogroup"
			aria-labelledby={labelId}
			aria-describedby={helpId}
		>
			{#each options as option (option)}
				<label class="form-question__choice" class:form-question__choice--picked={value === option}>
					<input
						type="radio"
						name={id}
						value={option}
						checked={value === option}
						onchange={() => (value = option)}
					/>
					<span class="form-question__circle" aria-hidden="true"></span>
					{option}
				</label>
			{/each}
		</div>
	{:else if question.type === 'yes_no'}
		<div
			class="form-question__choices form-question__choices--row"
			role="radiogroup"
			aria-labelledby={labelId}
			aria-describedby={helpId}
		>
			{#each [{ answer: true, label: 'Yes', icon: thumbUpIcon }, { answer: false, label: 'No', icon: thumbDownIcon }] as choice (choice.label)}
				<label
					class="form-question__choice"
					class:form-question__choice--picked={value === choice.answer}
				>
					<input
						type="radio"
						name={id}
						checked={value === choice.answer}
						onchange={() => (value = choice.answer)}
					/>
					<span class="form-question__circle" aria-hidden="true"></span>
					<IconTile
						icon={choice.icon}
						tone={value === choice.answer ? 'success' : 'inactive'}
						size={24}
					/>
					{choice.label}
				</label>
			{/each}
		</div>
	{:else if question.type === 'image_upload'}
		{@render imageUpload?.(question)}
	{/if}
</div>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.form-question {
		display: flex;
		flex-direction: column;
		gap: var(--space-slim);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: 14px;
		background: var(--color-surface--background--subtle);

		&__head {
			display: flex;
			align-items: flex-start;
			gap: var(--space-slim);
		}

		&__number {
			display: inline-grid;
			flex: 0 0 auto;
			place-items: center;
			box-sizing: border-box;
			width: 28px;
			height: 28px;
			border: var(--border-base) solid var(--color-request--surface-edge);
			border-radius: var(--radius-base);
			color: var(--color-request--onSurface);
			background: var(--color-request--surface);
			font-size: var(--typography--fontSize-label);
			font-weight: 700;
		}

		&__words {
			display: grid;
			gap: 2px;
			min-height: 28px;
			align-content: center;
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
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

			// Pick one and Yes / No sit side by side, sharing the width.
			&--row {
				flex-direction: row;
				flex-wrap: wrap;

				.form-question__choice {
					flex: 1 1 160px;
				}
			}
		}

		&__choice {
			position: relative;
			display: flex;
			box-sizing: border-box;
			min-height: 44px;
			align-items: center;
			gap: 10px;
			padding: 0 var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-tile-large);
			color: var(--color-heading);
			background: var(--color-surface);
			box-shadow: var(--shadow-button);
			font-size: var(--typography--fontSize-base);
			font-weight: 500;
			cursor: pointer;
			transition:
				background-color var(--timing-quick),
				border-color var(--timing-quick);

			input {
				position: absolute;
				width: 1px;
				height: 1px;
				overflow: hidden;
				clip: rect(0 0 0 0);
				white-space: nowrap;
			}

			&:hover {
				border-color: var(--color-interactive);
				background: var(--color-surface--hover);
			}

			&:has(input:focus-visible) {
				outline: 2px solid var(--color-focus);
				outline-offset: 2px;
			}

			// A picked tile's 1.5px edge: the 1px border plus a half-pixel ring.
			&--picked {
				border-color: var(--color-interactive);
				box-shadow:
					0 0 0 0.5px var(--color-interactive),
					var(--shadow-button);
				font-weight: 600;
			}
		}

		// The approved checkbox and radio circle (design `inputs.md`), drawn inside the tile it labels.
		&__box,
		&__circle {
			display: inline-grid;
			flex: 0 0 18px;
			place-items: center;
			box-sizing: border-box;
			width: 18px;
			height: 18px;
			border: var(--border-base) solid var(--color-border--interactive);
			color: var(--color-surface);
			background: var(--color-surface);
			transition: all var(--timing-quick) ease-out;
		}

		&__box {
			border-radius: var(--radius-small);

			:global(svg) {
				width: 12px;
				height: 12px;
				stroke-width: 3;
				opacity: 0;
			}
		}

		&__circle {
			border-radius: var(--radius-circle);
		}

		&__choice:hover &__box,
		&__choice:hover &__circle {
			border-color: var(--color-interactive);
		}

		&__choice--picked &__box {
			border-color: var(--color-interactive);
			background: var(--color-interactive);

			:global(svg) {
				opacity: 1;
			}
		}

		&__choice--picked &__circle {
			border: 5px solid var(--color-interactive);
		}
	}
</style>
