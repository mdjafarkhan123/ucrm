<script lang="ts">
	import { tick } from 'svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import { SETUP_QUESTION_KINDS } from '$lib/setup/catalogue';
	import { SETUP_QUESTION_KIND_LABELS, type DraftItem } from '$lib/jafar/setup-editor';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import chevronDownIcon from '@tabler/icons/outline/chevron-down.svg?raw';
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
		errors = {}
	}: {
		items: DraftItem[];
		/** Questions clients have answered, by key. */
		answered: ReadonlySet<string>;
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

	function kindLocked(item: DraftItem) {
		return item.built_in || (item.fact_key !== null && answered.has(item.fact_key));
	}

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
		if (item.kind === 'choice' && item.options.length === 0) {
			addChoice(item);
			addChoice(item);
		}
	}

	function addChoice(item: DraftItem) {
		newChoices += 1;
		item.options.push({ rowId: `new-choice-${newChoices}`, value: null, label: '' });
	}

	/** Opens a newly added row and puts the cursor in its first box. */
	export async function openNew(rowId: string) {
		openRow = rowId;
		await tick();
		list?.querySelector<HTMLInputElement>(`#setup-item-${rowId}-label`)?.focus();
	}

	/** Opens the first row with a problem so its message is on screen. */
	export function openFirstError() {
		const rowId = Object.keys(errors)[0]?.split('.')[0];
		if (rowId) openRow = rowId;
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

							{#if item.kind === 'choice'}
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
											onclick={() => addChoice(item)}
											><span class="setup-questions__button-icon" aria-hidden="true"
												>{@html plusIcon}</span
											>Add choice</Button
										>
									</div>
								</fieldset>
							{/if}
						{/if}

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
