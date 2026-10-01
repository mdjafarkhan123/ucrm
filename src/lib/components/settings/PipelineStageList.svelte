<script lang="ts" module>
	import type { CustomStage } from '$lib/pipeline/stages';

	// A custom stage as the Settings form holds it. `id` is null until the stage has been saved once;
	// `key` is what the list tracks a row by in the meantime. Its days are null while the box is empty.
	export type DraftStage = Omit<CustomStage, 'id' | 'inactivity_days'> & {
		key: string;
		id: string | null;
		inactivity_days: number | null;
	};
</script>

<script lang="ts">
	import { tick } from 'svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import {
		BOARD_COLUMN_LABELS,
		CUSTOM_STAGE_NAME_MAX,
		canMoveColumn,
		stagesInColumn,
		type AnyBoardStage,
		type SectionColumn
	} from '$lib/pipeline/stages';
	import { INACTIVITY_DAYS_MAX } from '$lib/pipeline/freshness';
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
		days,
		daysErrors,
		onAdd,
		onRename,
		onRequireTask,
		onBuiltInDays,
		onStageDays,
		onMove,
		onRemove,
		onRemoveIntent
	}: {
		columns: SectionColumn<DraftStage>[];
		canEdit: boolean;
		// False once the organization is at its limit of custom stages.
		canAdd: boolean;
		// What is wrong with a row's name, by the row's key. Empty when nothing is.
		errors: Record<string, string>;
		// The built-in stages' warning days, as the form holds them. Null is a box left empty.
		days: Record<AnyBoardStage, number | null>;
		// What is wrong with a row's days, by the built-in column's name or the custom row's key.
		daysErrors: Record<string, string>;
		// Returns the new row's key, so its name box can take the cursor.
		onAdd: () => string;
		onRename: (key: string, name: string) => void;
		// Turns a stage into an on-hold stage, or back: cards need a future Task to be moved in.
		onRequireTask: (key: string, required: boolean) => void;
		// The collapsed Assessment row speaks for its three stages at once.
		onBuiltInDays: (stages: readonly AnyBoardStage[], days: number | null) => void;
		onStageDays: (key: string, days: number | null) => void;
		onMove: (index: number, by: -1 | 1) => void;
		// A stage never saved is simply dropped from the form. A saved one is on the board, so the page asks
		// first — and where its cards go.
		onRemove: (key: string) => void;
		// The pointer or the keyboard has reached a saved stage's remove button: time to find out how many
		// cards it holds, before the click.
		onRemoveIntent: (stageId: string) => void;
	} = $props();

	let list = $state<HTMLOListElement>();

	// What the person typed, as a number. An empty box is null, so the page can ask for a number on Save
	// rather than quietly saving a zero.
	function typedDays(event: Event): number | null {
		const raw = (event.currentTarget as HTMLInputElement).value.trim();
		return raw === '' ? null : Number(raw);
	}

	function daysWord(value: number | null) {
		return value === 1 ? 'day' : 'days';
	}

	async function add() {
		const key = onAdd();
		await tick();
		list?.querySelector<HTMLInputElement>(`#pipeline-stage-${key}`)?.focus();
	}
</script>

<!-- "Warn after [2] days": how long a card here may go without real progress before it says so. -->
{#snippet warnAfter(
	id: string,
	stageName: string,
	value: number | null,
	error: string | undefined,
	onchange: (days: number | null) => void
)}
	{#if canEdit}
		<div class="stage-list__days">
			<span class="stage-list__days-text" aria-hidden="true">Warn after</span>
			<Input
				{id}
				type="number"
				size="small"
				class="stage-list__days-input"
				aria-label={`Days without progress before a card in ${stageName} shows a warning`}
				min={1}
				max={INACTIVITY_DAYS_MAX}
				step={1}
				inputmode="numeric"
				value={value ?? ''}
				invalid={Boolean(error)}
				oninput={(event: Event) => onchange(typedDays(event))}
			/>
			<span class="stage-list__days-text" aria-hidden="true">{daysWord(value)}</span>
		</div>
		{#if error}<p class="stage-list__days-error" role="alert">{error}</p>{/if}
	{:else if value !== null}
		<span class="stage-list__note">Warns after {value} {daysWord(value)}</span>
	{/if}
{/snippet}

<div class="stage-list">
	<ol class="stage-list__rows" bind:this={list}>
		{#each columns as column, index (column.kind === 'protected' ? column.key : column.stage.key)}
			{#if column.kind === 'protected'}
				{@const covered = stagesInColumn(column.key)}
				<li class="stage-list__row stage-list__row--locked">
					<span class="stage-list__lock" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html lockIcon}
					</span>
					<div class="stage-list__built-in">
						<span class="stage-list__name">{BOARD_COLUMN_LABELS[column.key]}</span>
						{@render warnAfter(
							`pipeline-stage-days-${column.key}`,
							BOARD_COLUMN_LABELS[column.key],
							days[covered[0]],
							daysErrors[column.key],
							(value) => onBuiltInDays(covered, value)
						)}
					</div>
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
							<Toggle
								id={`pipeline-stage-hold-${stage.key}`}
								label="On hold stage"
								description="A card can only be moved here once it has a task due on a later day, so nobody forgets to come back to it."
								checked={stage.requires_future_task}
								onchange={(checked) => onRequireTask(stage.key, checked)}
							/>
							{@render warnAfter(
								`pipeline-stage-days-${stage.key}`,
								label,
								stage.inactivity_days,
								daysErrors[stage.key],
								(value) => onStageDays(stage.key, value)
							)}
							{#if stage.requires_future_task}
								<p class="stage-list__hint">
									Cards here stay quiet until their task is due, then count from there.
								</p>
							{/if}
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
							<button
								type="button"
								class="stage-list__icon-button stage-list__icon-button--danger"
								aria-label={`Remove ${label}`}
								aria-haspopup={stage.id === null ? undefined : 'dialog'}
								onpointerenter={() => stage.id && onRemoveIntent(stage.id)}
								onfocus={() => stage.id && onRemoveIntent(stage.id)}
								onclick={() => onRemove(stage.key)}
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								{@html trashIcon}
							</button>
						</div>
					{:else}
						<div class="stage-list__built-in">
							<span class="stage-list__name">{stage.name}</span>
							{@render warnAfter(
								`pipeline-stage-days-${stage.key}`,
								label,
								stage.inactivity_days,
								undefined,
								() => {}
							)}
						</div>
						{#if stage.requires_future_task}
							<span class="stage-list__note">On hold · cards need a future task</span>
						{/if}
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

		// A locked row: the name on the left, its warning days on the right, wrapping under on a phone.
		&__built-in {
			display: flex;
			flex: 1 1 auto;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small) var(--space-base);
			min-width: 0;
		}

		&__days {
			display: flex;
			align-items: center;
			gap: var(--space-small);

			:global(.stage-list__days-input) {
				width: 80px;
			}
		}

		&__days-text,
		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			margin: 0;
		}

		&__days-error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__field {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: var(--space-small);
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
