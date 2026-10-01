<script lang="ts" module>
	import type { CustomStage } from '$lib/pipeline/stages';

	// A custom stage as the Settings form holds it. `id` is null until the stage has been saved once;
	// `key` is what the list tracks a row by in the meantime.
	export type DraftStage = Omit<CustomStage, 'id'> & { key: string; id: string | null };
</script>

<script lang="ts">
	import { tick } from 'svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import {
		BOARD_COLUMN_LABELS,
		CUSTOM_STAGE_NAME_MAX,
		canMoveColumn,
		type SectionColumn
	} from '$lib/pipeline/stages';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';

	// One section's stages in board order: the built-in ones locked in place, the custom ones editable
	// between them. The page owns the list and the saving; this only reports what the person did.
	let {
		columns,
		canEdit,
		canAdd,
		errors,
		onAdd,
		onRename,
		onMove,
		onRemove
	}: {
		columns: SectionColumn<DraftStage>[];
		canEdit: boolean;
		// False once the organization is at its limit of custom stages.
		canAdd: boolean;
		// What is wrong with a row's name, by the row's key. Empty when nothing is.
		errors: Record<string, string>;
		// Returns the new row's key, so its name box can take the cursor.
		onAdd: () => string;
		onRename: (key: string, name: string) => void;
		onMove: (index: number, by: -1 | 1) => void;
		onRemove: (key: string) => void;
	} = $props();

	let list = $state<HTMLOListElement>();

	async function add() {
		const key = onAdd();
		await tick();
		list?.querySelector<HTMLInputElement>(`#pipeline-stage-${key}`)?.focus();
	}
</script>

<div class="stage-list">
	<ol class="stage-list__rows" bind:this={list}>
		{#each columns as column, index (column.kind === 'protected' ? column.key : column.stage.key)}
			{#if column.kind === 'protected'}
				<li class="stage-list__row stage-list__row--locked">
					<span class="stage-list__lock" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html lockIcon}
					</span>
					<span class="stage-list__name">{BOARD_COLUMN_LABELS[column.key]}</span>
					<span class="stage-list__note">Built in</span>
				</li>
			{:else}
				{@const stage = column.stage}
				{@const label = stage.name.trim() || 'this stage'}
				<li class="stage-list__row">
					{#if canEdit}
						<div class="stage-list__field">
							<Input
								id={`pipeline-stage-${stage.key}`}
								aria-label="Stage name"
								placeholder="Stage name"
								maxlength={CUSTOM_STAGE_NAME_MAX}
								value={stage.name}
								invalid={Boolean(errors[stage.key])}
								errorMessage={errors[stage.key] ?? ''}
								oninput={(event: Event) =>
									onRename(stage.key, (event.currentTarget as HTMLInputElement).value)}
							/>
						</div>
						<div class="stage-list__actions">
							<button
								type="button"
								class="stage-list__icon-button"
								aria-label={`Move ${label} earlier`}
								disabled={!canMoveColumn(columns, index, -1)}
								onclick={() => onMove(index, -1)}
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html arrowUpIcon}
							</button>
							<button
								type="button"
								class="stage-list__icon-button"
								aria-label={`Move ${label} later`}
								disabled={!canMoveColumn(columns, index, 1)}
								onclick={() => onMove(index, 1)}
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html arrowDownIcon}
							</button>
							<!-- Only a stage that has never been saved can be taken away here. -->
							{#if stage.id === null}
								<button
									type="button"
									class="stage-list__icon-button stage-list__icon-button--danger"
									aria-label={`Remove ${label}`}
									onclick={() => onRemove(stage.key)}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html trashIcon}
								</button>
							{/if}
						</div>
					{:else}
						<span class="stage-list__name">{stage.name}</span>
					{/if}
				</li>
			{/if}
		{/each}
	</ol>

	{#if canEdit}
		<div>
			<Button variant="secondary" size="small" disabled={!canAdd} onclick={add}>
				<span class="stage-list__button-icon" aria-hidden="true">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					{@html plusIcon}
				</span>
				Add stage
			</Button>
		</div>
	{/if}
</div>

<style lang="scss">
	.stage-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__rows {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			min-height: 48px;
			padding: var(--space-small) var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);

			&--locked {
				align-items: center;
				background: var(--color-surface--background);
			}
		}

		&__lock {
			display: grid;
			flex: 0 0 auto;
			place-items: center;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__name {
			flex: 1 1 auto;
			min-width: 0;
			align-self: center;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__note {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__field {
			flex: 1 1 auto;
			min-width: 0;
		}

		&__actions {
			display: flex;
			flex: 0 0 auto;
			gap: var(--space-smallest);
			// Lines the buttons up with the name box rather than with an error message under it.
			padding-top: var(--space-smallest);
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
</style>
