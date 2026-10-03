<script lang="ts">
	import { tick } from 'svelte';
	import { resolve } from '$app/paths';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { stageAudience, type DraftStage, type SetupEditor } from '$lib/jafar/setup-editor';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	// Client onboarding A4 (plan §2.1): the setup stages in the order clients see them. While a draft is open
	// each stage can be renamed, reworded, moved, limited to one service or removed; the page owns the list and
	// the saving. A stage holding built-in questions can be renamed and moved only — the app copies those
	// answers into CRM settings, so every client must be asked them.
	let {
		stages = $bindable(),
		services,
		canEdit,
		errors = {}
	}: {
		stages: DraftStage[];
		services: SetupEditor['services'];
		canEdit: boolean;
		/** What is wrong with a row's field, keyed `<rowId>.title` or `<rowId>.description`. */
		errors?: Record<string, string>;
	} = $props();

	let list = $state<HTMLOListElement>();

	// Archived services are not offered for a stage, except the one a stage already has.
	function audienceOptions(current: string | null) {
		return [
			{ value: '', label: 'Every client' },
			...services
				.filter((service) => !service.archived || service.key === current)
				.map((service) => ({
					value: service.key,
					label: `Only clients with ${service.name}${service.archived ? ' (archived)' : ''}`
				}))
		];
	}

	function move(index: number, by: -1 | 1) {
		const target = index + by;
		[stages[index], stages[target]] = [stages[target], stages[index]];
	}

	function remove(index: number) {
		stages.splice(index, 1);
	}

	/** Puts the cursor in a newly added stage's name box. */
	export async function focusRow(rowId: string) {
		await tick();
		list?.querySelector<HTMLInputElement>(`#setup-stage-${rowId}-title`)?.focus();
	}

	function questionsLabel(count: number) {
		return `${count} ${count === 1 ? 'question' : 'questions'}`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<ol class="setup-stages" bind:this={list}>
	{#each stages as stage, index (stage.rowId)}
		{@const name = stage.title.trim() || 'this stage'}
		<li class="setup-stages__row" class:setup-stages__row--hidden={stage.questions === 0}>
			<span class="setup-stages__number" aria-hidden="true">{index + 1}</span>

			<div class="setup-stages__body">
				{#if canEdit}
					<Input
						id={`setup-stage-${stage.rowId}-title`}
						label="Stage name"
						maxlength={80}
						bind:value={stage.title}
						invalid={Boolean(errors[`${stage.rowId}.title`])}
						errorMessage={errors[`${stage.rowId}.title`] ?? ''}
					/>
					<Textarea
						id={`setup-stage-${stage.rowId}-description`}
						label="What the client does here"
						rows={2}
						maxlength={300}
						bind:value={stage.description}
						invalid={Boolean(errors[`${stage.rowId}.description`])}
						errorMessage={errors[`${stage.rowId}.description`] ?? ''}
					/>
					<div class="setup-stages__audience">
						<Select
							id={`setup-stage-${stage.rowId}-audience`}
							label="Who sees this stage"
							options={audienceOptions(stage.service_key)}
							value={stage.service_key ?? ''}
							disabled={stage.builtIn}
							onchange={(value: string) => (stage.service_key = value || null)}
						/>
						{#if stage.builtIn}
							<p class="setup-stages__hint">
								Holds built-in questions the CRM uses, so every client sees it.
							</p>
						{/if}
					</div>
				{:else}
					<h3 class="setup-stages__title">{stage.title}</h3>
					{#if stage.description}<p class="setup-stages__description">{stage.description}</p>{/if}
					<p class="setup-stages__audience-text">
						{stageAudience(stage.service_key, services)}
					</p>
				{/if}

				<div class="setup-stages__meta">
					{#if stage.key === null}
						<Badge status="informative" size="small">New</Badge>
					{/if}
					{#if stage.builtIn}
						<span class="setup-stages__lock">
							<span class="setup-stages__meta-icon" aria-hidden="true">{@html lockIcon}</span>
							Built-in questions
						</span>
					{/if}
					{#if stage.questions > 0}
						<span class="setup-stages__count">{questionsLabel(stage.questions)}</span>
					{:else}
						<span class="setup-stages__warning">
							<span class="setup-stages__meta-icon" aria-hidden="true">{@html alertIcon}</span>
							No questions yet — clients won't see this stage until it has one
						</span>
					{/if}
					{#if canEdit}
						{#if stage.key === null}
							<span class="setup-stages__count">Save the draft to add questions</span>
						{:else}
							<a
								class="setup-stages__link"
								href={resolve('/jafar/(protected)/setup/[stage]', { stage: stage.key })}
								><span class="setup-stages__meta-icon" aria-hidden="true">{@html pencilIcon}</span
								>Edit questions</a
							>
						{/if}
					{/if}
				</div>
			</div>

			{#if canEdit}
				<div class="setup-stages__actions">
					<button
						type="button"
						class="setup-stages__icon-button"
						aria-label={`Move ${name} earlier`}
						disabled={index === 0}
						onclick={() => move(index, -1)}>{@html arrowUpIcon}</button
					>
					<button
						type="button"
						class="setup-stages__icon-button"
						aria-label={`Move ${name} later`}
						disabled={index === stages.length - 1}
						onclick={() => move(index, 1)}>{@html arrowDownIcon}</button
					>
					<button
						type="button"
						class="setup-stages__icon-button setup-stages__icon-button--danger"
						aria-label={stage.builtIn
							? `${name} holds built-in questions and cannot be removed`
							: `Remove ${name}`}
						title={stage.builtIn ? 'Holds built-in questions, so it cannot be removed' : undefined}
						disabled={stage.builtIn || stages.length === 1}
						onclick={() => remove(index)}>{@html trashIcon}</button
					>
				</div>
			{/if}
		</li>
	{/each}
</ol>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-stages {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;

		&__row {
			display: flex;
			align-items: flex-start;
			gap: var(--space-base);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--hidden {
				border-style: dashed;
			}
		}

		&__number {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			width: 28px;
			height: 28px;
			border-radius: var(--radius-circle);
			background: var(--color-surface--background);
			color: var(--color-heading);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__body {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-slim);
			min-width: 0;
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			line-height: var(--typography--lineHeight-tight);
			overflow-wrap: anywhere;
		}

		&__description,
		&__audience-text,
		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__audience {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			max-width: 420px;
		}

		&__meta {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small) var(--space-base);
			font-size: var(--typography--fontSize-small);
		}

		&__count,
		&__lock {
			color: var(--color-text--secondary);
		}

		&__link {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smallest);
			border-radius: var(--radius-small);
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: none;

			&:hover {
				text-decoration: underline;
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__lock,
		&__warning {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smallest);
		}

		&__warning {
			color: var(--color-warning--onSurface);
			font-weight: 600;
		}

		&__meta-icon {
			display: inline-grid;
			place-items: center;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			gap: var(--space-smallest);
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
	}

	@media (max-width: 639px) {
		.setup-stages__row {
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		.setup-stages__body {
			order: 3;
			flex-basis: 100%;
		}

		.setup-stages__actions {
			margin-left: auto;
		}
	}
</style>
