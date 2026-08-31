<script lang="ts">
	import { useQueryClient } from '@tanstack/svelte-query';
	import { goto, beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import SummaryRail from './SummaryRail.svelte';
	import EmailActionEditor from './EmailActionEditor.svelte';
	import {
		catalogEntriesByKind,
		getCatalogEntry,
		isEnabled,
		type CatalogEntry
	} from '$lib/automation/catalog';
	import {
		sendEmailStepsMissingContent,
		type AuthoredDefinition,
		type AuthoredStep
	} from '$lib/automation/authoring';
	import { unknownEmailVariables } from '$lib/automation/email-variables';
	import {
		createRecipeDraft,
		saveRecipeDraft,
		fetchRecipeEditor,
		automationEditorKey,
		StaleDraftError
	} from '$lib/settings/automation-authoring';
	import type { RecipeSource } from '$lib/settings/automation-recipes';
	import { STORED_QUOTE_STATUSES, QUOTE_STATUS_LABELS } from '$lib/quotes/statuses';
	import robotIcon from '@tabler/icons/outline/robot.svg?raw';
	import boltIcon from '@tabler/icons/outline/bolt.svg?raw';
	import filterIcon from '@tabler/icons/outline/filter.svg?raw';
	import arrowsSortIcon from '@tabler/icons/outline/arrows-sort.svg?raw';
	import handStopIcon from '@tabler/icons/outline/hand-stop.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// The shared When/If/Then/Stop builder. It serves both `/settings/automation/new` (create a draft from a
	// preset or from scratch) and `/settings/automation/[id]/edit` (edit an existing draft), because the two
	// are the same form over the same AuthoredDefinition. It holds the draft locally; the first successful
	// save is the first write (create) or a revision-checked update (edit). A stale save never overwrites — it
	// surfaces the newer editor and offers Review or Discard (docs/automation-behavior-contract.md § Builder).
	let {
		mode,
		source,
		initialName,
		initialDefinition,
		presetKey = null,
		presetVersion = null,
		recipeId = null,
		initialRevision = 0
	}: {
		mode: 'create' | 'edit';
		source: RecipeSource;
		initialName: string;
		initialDefinition: AuthoredDefinition;
		presetKey?: string | null;
		presetVersion?: number | null;
		recipeId?: string | null;
		initialRevision?: number;
	} = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();
	const homeHref = resolve('/(app)/settings/automation');

	// A plain, proxy-free copy so local edits never mutate the caller's object.
	function clone(definition: AuthoredDefinition): AuthoredDefinition {
		return JSON.parse(JSON.stringify(definition)) as AuthoredDefinition;
	}

	// These seed local editor state from the initial props once, on mount, by design: the builder owns the
	// draft after that and the loader remounts it per recipe, so capturing only the initial value is correct.
	// svelte-ignore state_referenced_locally
	let name = $state(initialName);
	// svelte-ignore state_referenced_locally
	let definition = $state<AuthoredDefinition>(clone(initialDefinition));
	// svelte-ignore state_referenced_locally
	let currentRevision = $state(initialRevision);

	let saving = $state(false);
	let errors = $state<{ name: string; trigger: string; steps: Record<number, string> }>({
		name: '',
		trigger: '',
		steps: {}
	});
	let stale = $state<{ editorName: string | null; updatedAt: string | null } | null>(null);

	// Dirty tracking drives the unsaved-navigation guard. The snapshot is refreshed after every successful
	// save so a saved draft no longer warns on the way out.
	// svelte-ignore state_referenced_locally
	let savedSnapshot = $state(JSON.stringify({ name: initialName, definition: initialDefinition }));
	const dirty = $derived(JSON.stringify({ name, definition }) !== savedSnapshot);
	// Set before every intentional navigation (after a save, or Discard) so the guard does not fight our own.
	let leaving = false;

	beforeNavigate((navigation) => {
		if (leaving || !dirty) return;
		if (!confirm('You have unsaved changes. Leave without saving them?')) navigation.cancel();
	});

	// --- Catalog choices -------------------------------------------------------------------------------
	const triggerOptions = $derived([
		{ value: '', label: 'Choose a trigger' },
		...catalogEntriesByKind('trigger').map((entry) => ({
			value: entry.key,
			label: isEnabled(entry)
				? entry.label
				: `${entry.label} — ${entry.availability.status === 'blocked' ? entry.availability.reason : 'Not available yet'}`,
			disabled: !isEnabled(entry)
		}))
	]);

	const chosenConditionKeys = $derived(new Set(definition.conditions.map((c) => c.key)));
	const addableConditions = $derived(
		catalogEntriesByKind('condition').filter(
			(entry) => isEnabled(entry) && !chosenConditionKeys.has(entry.key)
		)
	);
	const MAX_CONDITIONS = 6;

	const stopEntries = $derived(catalogEntriesByKind('stop').filter(isEnabled));
	const chosenStops = $derived(new Set(definition.stops.map((s) => s.key)));

	function label(key: string): string {
		return getCatalogEntry(key)?.label ?? key;
	}

	// --- When ------------------------------------------------------------------------------------------
	function setTrigger(key: string) {
		definition.trigger = key ? { key, config: {} } : null;
		if (key) errors = { ...errors, trigger: '' };
	}

	// --- If --------------------------------------------------------------------------------------------
	function addCondition(key: string) {
		if (!key || definition.conditions.length >= MAX_CONDITIONS) return;
		const config = key === 'quote.current_status' ? { statuses: [] as string[] } : {};
		definition.conditions = [...definition.conditions, { key, config }];
	}

	function removeCondition(index: number) {
		definition.conditions = definition.conditions.filter((_, i) => i !== index);
	}

	function conditionStatuses(index: number): string[] {
		const value = definition.conditions[index]?.config?.statuses;
		return Array.isArray(value) ? (value as string[]) : [];
	}

	function toggleStatus(index: number, status: string, checked: boolean) {
		const existing = conditionStatuses(index);
		const statuses = checked
			? existing.includes(status)
				? existing
				: [...existing, status]
			: existing.filter((value) => value !== status);
		const condition = definition.conditions[index];
		definition.conditions[index] = {
			...condition,
			config: { ...condition.config, statuses }
		};
		definition.conditions = [...definition.conditions];
	}

	// --- Then ------------------------------------------------------------------------------------------
	function addWait() {
		const step: AuthoredStep = {
			type: 'wait',
			key: 'wait.relative_delay',
			config: { unit: 'days', amount: 1 }
		};
		definition.steps = [...definition.steps, step];
	}

	function addEmail() {
		const step: AuthoredStep = { type: 'action', key: 'action.send_email', config: {} };
		definition.steps = [...definition.steps, step];
	}

	function moveStep(index: number, direction: -1 | 1) {
		const target = index + direction;
		if (target < 0 || target >= definition.steps.length) return;
		const next = [...definition.steps];
		[next[index], next[target]] = [next[target], next[index]];
		definition.steps = next;
	}

	function duplicateStep(index: number) {
		const copy = clone({ ...definition, steps: [definition.steps[index]] }).steps[0];
		definition.steps = [
			...definition.steps.slice(0, index + 1),
			copy,
			...definition.steps.slice(index + 1)
		];
	}

	function removeStep(index: number) {
		definition.steps = definition.steps.filter((_, i) => i !== index);
		const { [index]: _removed, ...rest } = errors.steps;
		errors = { ...errors, steps: rest };
	}

	function setWaitUnit(index: number, unit: string) {
		const step = definition.steps[index];
		definition.steps[index] = { ...step, config: { ...step.config, unit } };
		definition.steps = [...definition.steps];
	}

	function setWaitAmount(index: number, raw: number) {
		const amount = Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : 1;
		const step = definition.steps[index];
		definition.steps[index] = { ...step, config: { ...step.config, amount } };
		definition.steps = [...definition.steps];
	}

	function stepEmailField(index: number, field: 'subject' | 'body'): string {
		const value = definition.steps[index]?.config?.[field];
		return typeof value === 'string' ? value : '';
	}

	function setEmailField(index: number, field: 'subject' | 'body', value: string) {
		const step = definition.steps[index];
		const config = { ...step.config };
		if (value.trim()) config[field] = value;
		else delete config[field];
		definition.steps[index] = { ...step, config };
		definition.steps = [...definition.steps];

		// Clear the step error once both the subject and the message are present again.
		const subject = typeof config.subject === 'string' ? config.subject.trim() : '';
		const body = typeof config.body === 'string' ? config.body.trim() : '';
		if (subject && body) {
			const { [index]: _cleared, ...rest } = errors.steps;
			errors = { ...errors, steps: rest };
		}
	}

	function waitAmount(index: number): number {
		const value = definition.steps[index]?.config?.amount;
		return typeof value === 'number' ? value : 1;
	}

	function waitUnit(index: number): string {
		const value = definition.steps[index]?.config?.unit;
		return value === 'hours' ? 'hours' : 'days';
	}

	// --- Stop ------------------------------------------------------------------------------------------
	function toggleStop(key: string, checked: boolean) {
		definition.stops = checked
			? [...definition.stops, { key }]
			: definition.stops.filter((stop) => stop.key !== key);
	}

	// --- Save ------------------------------------------------------------------------------------------
	function validate(): boolean {
		const next: typeof errors = { name: '', trigger: '', steps: {} };
		let ok = true;
		if (!name.trim()) {
			next.name = 'Give this automation a name.';
			ok = false;
		}
		if (!definition.trigger) {
			next.trigger = 'Choose what starts this automation.';
			ok = false;
		}
		for (const index of sendEmailStepsMissingContent(definition)) {
			next.steps[index] = 'Add a subject line and a message.';
			ok = false;
		}
		// The picker only inserts allow-listed variables, but a hand-typed {{token}} could be unknown; catch it
		// here so a save that the server would reject never leaves the builder.
		definition.steps.forEach((step, index) => {
			if (step.key !== 'action.send_email' || next.steps[index]) return;
			const subject = typeof step.config?.subject === 'string' ? step.config.subject : '';
			const body = typeof step.config?.body === 'string' ? step.config.body : '';
			const unknown = [...unknownEmailVariables(subject), ...unknownEmailVariables(body)];
			if (unknown.length > 0) {
				next.steps[index] = `"{{${unknown[0]}}}" is not a value you can use here.`;
				ok = false;
			}
		});
		errors = next;
		return ok;
	}

	function focusFirstError() {
		let id: string | null = null;
		if (errors.name) id = 'builder-name';
		else if (errors.trigger) id = 'builder-trigger';
		else {
			const firstStep = Object.keys(errors.steps)[0];
			if (firstStep !== undefined) id = `builder-step-${firstStep}-subject`;
		}
		if (id) document.getElementById(id)?.focus();
	}

	async function invalidateLists() {
		await queryClient.invalidateQueries({ queryKey: ['settings', 'automation', 'recipes'] });
	}

	async function save() {
		if (saving) return;
		if (!validate()) {
			focusFirstError();
			return;
		}
		saving = true;
		const idempotencyKey = crypto.randomUUID();
		try {
			if (mode === 'create') {
				const result = await createRecipeDraft({
					name: name.trim(),
					source,
					presetKey,
					presetVersion,
					definition,
					idempotencyKey
				});
				savedSnapshot = JSON.stringify({ name, definition });
				await invalidateLists();
				toast.success('Draft saved.');
				leaving = true;
				await goto(resolve('/(app)/settings/automation/[id]/edit', { id: result.recipe_id }));
			} else if (recipeId) {
				const result = await saveRecipeDraft({
					recipeId,
					name: name.trim(),
					expectedRevision: currentRevision,
					definition,
					idempotencyKey
				});
				currentRevision = result.draft_revision;
				savedSnapshot = JSON.stringify({ name, definition });
				stale = null;
				await queryClient.invalidateQueries({ queryKey: automationEditorKey(recipeId) });
				await invalidateLists();
				toast.success('Draft saved.');
			}
		} catch (error) {
			if (error instanceof StaleDraftError) {
				stale = { editorName: error.editorName, updatedAt: error.updatedAt };
			} else {
				toast.error(error instanceof Error ? error.message : 'We could not save that automation.');
			}
		} finally {
			saving = false;
		}
	}

	// Review: adopt the newer draft into the builder so the user can see what changed and re-apply. Discards
	// the local edits (the conflict makes them un-saveable) but never touches the server copy.
	async function reviewLatest() {
		if (!recipeId) return;
		try {
			const latest = await fetchRecipeEditor(recipeId);
			name = latest.name;
			definition = clone(latest.draft_definition);
			currentRevision = latest.draft_revision;
			savedSnapshot = JSON.stringify({ name: latest.name, definition: latest.draft_definition });
			queryClient.setQueryData(automationEditorKey(recipeId), latest);
			stale = null;
			toast.success('Loaded the latest version.');
		} catch (error) {
			toast.error(
				error instanceof Error ? error.message : 'The latest version could not be loaded.'
			);
		}
	}

	// Discard: give up this editing session entirely and return to the list.
	function discardChanges() {
		leaving = true;
		void goto(homeHref);
	}

	function staleWhen(): string {
		if (!stale?.updatedAt) return '';
		return new Date(stale.updatedAt).toLocaleString(undefined, {
			month: 'short',
			day: 'numeric',
			hour: 'numeric',
			minute: '2-digit'
		});
	}
</script>

<RecordFormLayout title={mode === 'create' ? 'New automation' : 'Edit automation'} icon={robotIcon}>
	{#snippet main()}
		<div class="builder">
			<Input
				id="builder-name"
				label="Automation name"
				bind:value={name}
				required
				invalid={Boolean(errors.name)}
				errorMessage={errors.name}
				placeholder="e.g. Quote follow-up"
			/>

			<!-- When -->
			<SectionBlock
				title="When this happens"
				icon={boltIcon}
				hint="Pick what starts the automation."
			>
				<Select
					id="builder-trigger"
					value={definition.trigger?.key ?? ''}
					options={triggerOptions}
					ariaLabel="Trigger"
					onchange={setTrigger}
				/>
				{#if errors.trigger}
					<p class="builder__error" role="alert">{errors.trigger}</p>
				{/if}
			</SectionBlock>

			<!-- If -->
			<SectionBlock
				title="Only keep going if"
				icon={filterIcon}
				hint="Optional. Add up to six checks that must all be true."
			>
				{#if definition.conditions.length === 0}
					<p class="builder__muted">No conditions yet — the automation runs every time.</p>
				{:else}
					<ul class="builder__rows">
						{#each definition.conditions as condition, index (condition.key)}
							<li class="builder__row">
								<div class="builder__row-head">
									<span class="builder__row-title">{label(condition.key)}</span>
									<button
										type="button"
										class="builder__icon-button"
										aria-label={`Remove condition: ${label(condition.key)}`}
										onclick={() => removeCondition(index)}
									>
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html trashIcon}
									</button>
								</div>
								{#if condition.key === 'quote.current_status'}
									<fieldset class="builder__statuses">
										<legend>Continue only while the quote is:</legend>
										{#each STORED_QUOTE_STATUSES as status (status)}
											<Checkbox
												id={`builder-status-${index}-${status}`}
												label={QUOTE_STATUS_LABELS[status]}
												checked={conditionStatuses(index).includes(status)}
												onchange={(checked) => toggleStatus(index, status, checked)}
											/>
										{/each}
									</fieldset>
								{/if}
							</li>
						{/each}
					</ul>
				{/if}

				{#if definition.conditions.length < MAX_CONDITIONS && addableConditions.length > 0}
					<div class="builder__add">
						<Select
							id="builder-add-condition"
							value=""
							options={[
								{ value: '', label: 'Add a condition…' },
								...addableConditions.map((entry: CatalogEntry) => ({
									value: entry.key,
									label: entry.label
								}))
							]}
							ariaLabel="Add a condition"
							onchange={addCondition}
						/>
					</div>
				{/if}
			</SectionBlock>

			<!-- Then -->
			<SectionBlock
				title="Then do this"
				icon={arrowsSortIcon}
				hint="The steps run in order. Use Move up and Move down to reorder them."
			>
				{#if definition.steps.length === 0}
					<p class="builder__muted">No steps yet. Add a wait or an email to get started.</p>
				{:else}
					<ol class="builder__steps">
						{#each definition.steps as step, index (index)}
							<li class="builder__step" class:builder__step--invalid={Boolean(errors.steps[index])}>
								<div class="builder__step-head">
									<span class="builder__step-index">{index + 1}</span>
									<span class="builder__step-icon" aria-hidden="true">
										<!-- eslint-disable-next-line svelte/no-at-html-tags -->
										{@html step.key === 'action.send_email' ? mailIcon : clockIcon}
									</span>
									<span class="builder__step-title">{label(step.key)}</span>
									<div class="builder__step-controls">
										<button
											type="button"
											class="builder__icon-button"
											aria-label="Move step up"
											disabled={index === 0}
											onclick={() => moveStep(index, -1)}
										>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -->
											{@html arrowUpIcon}
										</button>
										<button
											type="button"
											class="builder__icon-button"
											aria-label="Move step down"
											disabled={index === definition.steps.length - 1}
											onclick={() => moveStep(index, 1)}
										>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -->
											{@html arrowDownIcon}
										</button>
										{#if step.key === 'action.send_email'}
											<button
												type="button"
												class="builder__icon-button"
												aria-label="Duplicate step"
												onclick={() => duplicateStep(index)}
											>
												<!-- eslint-disable-next-line svelte/no-at-html-tags -->
												{@html copyIcon}
											</button>
										{/if}
										<button
											type="button"
											class="builder__icon-button builder__icon-button--danger"
											aria-label="Remove step"
											onclick={() => removeStep(index)}
										>
											<!-- eslint-disable-next-line svelte/no-at-html-tags -->
											{@html trashIcon}
										</button>
									</div>
								</div>

								<div class="builder__step-body">
									{#if step.key === 'wait.relative_delay'}
										<div class="builder__wait">
											<Input
												id={`builder-step-amount-${index}`}
												type="number"
												label="Amount"
												min="1"
												max="2160"
												value={String(waitAmount(index))}
												oninput={(event: Event) =>
													setWaitAmount(
														index,
														Number((event.currentTarget as HTMLInputElement).value)
													)}
											/>
											<Select
												id={`builder-step-unit-${index}`}
												value={waitUnit(index)}
												options={[
													{ value: 'hours', label: 'Hours' },
													{ value: 'days', label: 'Days' }
												]}
												ariaLabel="Wait unit"
												onchange={(unit) => setWaitUnit(index, unit)}
											/>
										</div>
									{:else if step.key === 'action.send_email'}
										<EmailActionEditor
											idPrefix={`builder-step-${index}`}
											subject={stepEmailField(index, 'subject')}
											body={stepEmailField(index, 'body')}
											errorMessage={errors.steps[index] ?? ''}
											onSubjectChange={(value) => setEmailField(index, 'subject', value)}
											onBodyChange={(value) => setEmailField(index, 'body', value)}
										/>
									{/if}
								</div>
							</li>
						{/each}
					</ol>
				{/if}

				<div class="builder__step-actions">
					<Button variant="tertiary" size="small" onclick={addWait}>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="builder__button-icon" aria-hidden="true">{@html plusIcon}</span> Add a wait
					</Button>
					<Button variant="tertiary" size="small" onclick={addEmail}>
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="builder__button-icon" aria-hidden="true">{@html plusIcon}</span> Add an email
					</Button>
				</div>
			</SectionBlock>

			<!-- Stop -->
			<SectionBlock
				title="Stop the automation when"
				icon={handStopIcon}
				hint="Pick the things that should end the follow-ups early."
			>
				<div class="builder__stops">
					{#each stopEntries as stop (stop.key)}
						<Checkbox
							id={`builder-stop-${stop.key}`}
							label={stop.label}
							checked={chosenStops.has(stop.key)}
							onchange={(checked) => toggleStop(stop.key, checked)}
						/>
					{/each}
				</div>
			</SectionBlock>
		</div>
	{/snippet}

	{#snippet rail()}
		<SummaryRail {name} {definition} />
	{/snippet}

	{#snippet actions()}
		<div class="builder__bar">
			{#if stale}
				<p class="builder__stale" role="alert">
					<span class="builder__stale-icon" aria-hidden="true">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						{@html alertTriangleIcon}
					</span>
					<span>
						{stale.editorName ? `${stale.editorName} changed` : 'Someone changed'} this automation{staleWhen()
							? ` on ${staleWhen()}`
							: ''}. Your changes weren’t saved.
					</span>
				</p>
				<div class="builder__bar-actions">
					<Button variant="secondary" onclick={discardChanges}>Discard my changes</Button>
					<Button variant="primary" onclick={reviewLatest}>Review their version</Button>
				</div>
			{:else}
				<span class="builder__bar-hint">
					{dirty ? 'You have unsaved changes.' : 'All changes saved.'}
				</span>
				<div class="builder__bar-actions">
					<Button variant="secondary" href={homeHref}>Cancel</Button>
					<Button variant="primary" loading={saving} onclick={save}>Save draft</Button>
				</div>
			{/if}
		</div>
	{/snippet}
</RecordFormLayout>

<style lang="scss">
	.builder {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__error {
			margin-top: var(--space-smaller);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__muted {
			color: var(--color-text--secondary);
			font-style: italic;
		}

		&__rows,
		&__steps {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__row,
		&__step {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__step--invalid {
			border-color: var(--color-critical);
		}

		&__row-head,
		&__step-head {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__row-title,
		&__step-title {
			flex: 1 1 auto;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__step-index {
			display: grid;
			place-items: center;
			width: 24px;
			height: 24px;
			flex: 0 0 auto;
			border-radius: var(--radius-circle);
			color: var(--color-surface);
			background: var(--color-interactive);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__step-icon {
			display: grid;
			place-items: center;
			color: var(--color-icon--secondary);
		}
		&__step-icon :global(svg) {
			width: 18px;
			height: 18px;
		}

		&__step-controls {
			display: flex;
			align-items: center;
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
				width: 16px;
				height: 16px;
			}
		}

		&__statuses {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small) var(--space-base);
			margin: 0;
			padding: var(--space-small) 0 0;
			border: 0;

			legend {
				width: 100%;
				margin-bottom: var(--space-smaller);
				padding: 0;
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
				font-weight: 600;
			}
		}

		&__step-body {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__wait {
			display: grid;
			grid-template-columns: 1fr 1fr;
			gap: var(--space-small);
		}

		&__add,
		&__step-actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__add {
			max-width: 320px;
		}

		&__button-icon {
			display: inline-grid;
			place-items: center;
		}
		&__button-icon :global(svg) {
			width: 16px;
			height: 16px;
		}

		&__stops {
			display: grid;
			grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
			gap: var(--space-small) var(--space-base);
		}
	}

	.builder__bar {
		display: flex;
		flex: 1 1 auto;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.builder__bar-hint {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.builder__bar-actions {
		display: flex;
		gap: var(--space-small);
	}

	.builder__stale {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.builder__stale-icon {
		display: grid;
		place-items: center;
		flex: 0 0 auto;
		color: var(--color-critical);
	}
	.builder__stale-icon :global(svg) {
		width: 18px;
		height: 18px;
	}

	@media (max-width: 767px) {
		.builder__bar {
			flex-direction: column;
			align-items: stretch;
		}
		.builder__bar-actions {
			justify-content: flex-end;
		}
	}
</style>
