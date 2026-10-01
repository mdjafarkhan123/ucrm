<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import PipelineStageList, {
		type DraftStage
	} from '$lib/components/settings/PipelineStageList.svelte';
	import PipelineLostReasonList from '$lib/components/settings/PipelineLostReasonList.svelte';
	import PipelineStageRemoveDialog from '$lib/components/settings/PipelineStageRemoveDialog.svelte';
	import {
		fetchSettingsPipeline,
		settingsPipelineKey,
		savePipelineSettings,
		isSaveConflict,
		fetchPipelineStageCardCount,
		pipelineStageCardCountKey,
		type SettingsPipeline,
		type SettingsWriteError
	} from '$lib/settings/api';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import {
		BOARD_SECTIONS,
		BOARD_SECTION_LABELS,
		CUSTOM_STAGE_LIMIT,
		SECTION_STAGES,
		moveColumn,
		placeCustomStages,
		protectedNamesInSection,
		sectionColumns,
		stagesInColumn,
		type AnyBoardStage,
		type BoardSection,
		type CustomStage
	} from '$lib/pipeline/stages';
	import { DEFAULT_INACTIVITY_DAYS, INACTIVITY_DAYS_MAX } from '$lib/pipeline/freshness';
	import layoutKanbanIcon from '@tabler/icons/outline/layout-kanban.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: settingsPipelineKey,
		queryFn: fetchSettingsPipeline
	}));

	let detailed = $state<boolean | null>(null);
	let savedDetailed = $state<boolean | null>(null);
	// Every custom stage the form is holding, saved or not. Its order inside a section is the board's.
	let stages = $state<DraftStage[]>([]);
	// What the server last confirmed, as the exact list a save would send — the form is changed when what
	// it would send now is different.
	let savedStages = $state('[]');
	// The built-in stages' warning days as the form holds them; null is a box left empty.
	let builtInDays = $state<Record<AnyBoardStage, number | null>>({ ...DEFAULT_INACTIVITY_DAYS });
	let savedBuiltInDays = $state('');
	let saving = $state(false);
	let errorMessage = $state('');
	// Naming problems the server found that this page did not, by row.
	let serverErrors = $state<Record<string, string>>({});
	// A blank name is only called a mistake once the person tries to save it.
	let attempted = $state(false);
	let conflict = $state<{ editor_name: string | null; edited_at: string | null } | null>(null);
	let layout = $state<RecordFormLayout>();

	// One place the form shows why a save did not land — a plain error, or someone else getting there first.
	const saveError = $derived(
		conflict
			? `${conflict.editor_name ?? 'Someone else'} just changed this. Refresh the page to see their version before saving yours.`
			: errorMessage
	);

	function seed(pipeline: SettingsPipeline['pipeline']) {
		detailed = pipeline.detailed_assessment_stages;
		savedDetailed = pipeline.detailed_assessment_stages;
		stages = pipeline.stages.map((stage) => ({ ...stage, key: stage.id }));
		savedStages = JSON.stringify(payloadFor(stages));
		builtInDays = { ...pipeline.inactivity_days };
		savedBuiltInDays = JSON.stringify(builtInDays);
		serverErrors = {};
		attempted = false;
	}

	$effect(() => {
		const pipeline = query.data?.pipeline;
		if (!pipeline) return;
		untrack(() => {
			if (detailed === null) seed(pipeline);
		});
	});

	// Each section's rows in board order: built-in stages locked in place, custom ones between them.
	const columns = $derived({
		request: sectionColumns('request', detailed ?? false, stages),
		quote: sectionColumns('quote', detailed ?? false, stages)
	});

	// The list a save sends: every custom stage, Requests then Quotes, in the order the board will show.
	function payloadFor(list: DraftStage[]) {
		return BOARD_SECTIONS.flatMap((section) =>
			sectionColumns(section, false, list).flatMap((column) =>
				column.kind === 'custom'
					? [
							{
								id: column.stage.id,
								section: column.stage.section,
								name: column.stage.name.trim(),
								after_stage: column.stage.after_stage,
								requires_future_task: column.stage.requires_future_task,
								inactivity_days: column.stage.inactivity_days
							}
						]
					: []
			)
		);
	}
	// The same rows in the same order, so a problem the server reports by position finds its row here.
	function payloadKeys(list: DraftStage[]) {
		return BOARD_SECTIONS.flatMap((section) =>
			sectionColumns(section, false, list).flatMap((column) =>
				column.kind === 'custom' ? [column.stage.key] : []
			)
		);
	}

	// A name is wrong when it is blank, or when its section already has a stage called that — built in or
	// custom. The second of two matching rows is the one that is marked.
	const nameProblems = $derived.by(() => {
		const problems: Record<string, string> = {};
		const taken: Record<BoardSection, Set<string>> = {
			request: new Set(protectedNamesInSection('request').map((name) => name.toLowerCase())),
			quote: new Set(protectedNamesInSection('quote').map((name) => name.toLowerCase()))
		};
		for (const stage of stages) {
			const name = stage.name.trim();
			if (name === '') {
				if (attempted) problems[stage.key] = 'Give this stage a name.';
				continue;
			}
			if (taken[stage.section].has(name.toLowerCase())) {
				problems[stage.key] =
					`${BOARD_SECTION_LABELS[stage.section]} already has a stage called “${name}”.`;
			}
			taken[stage.section].add(name.toLowerCase());
		}
		return problems;
	});
	const rowErrors = $derived({ ...serverErrors, ...nameProblems });

	// A days box must hold a whole number from 1 to the limit. Built-in rows are marked by their column's
	// name, custom rows by their key; the collapsed Assessment row speaks for its three stages.
	function daysProblem(value: number | null): string | null {
		if (value === null) return 'Enter a number of days.';
		if (!Number.isInteger(value) || value < 1 || value > INACTIVITY_DAYS_MAX)
			return `Use a whole number from 1 to ${INACTIVITY_DAYS_MAX}.`;
		return null;
	}
	const daysErrors = $derived.by(() => {
		const problems: Record<string, string> = {};
		for (const section of BOARD_SECTIONS) {
			for (const column of columns[section]) {
				if (column.kind === 'protected') {
					const problem = stagesInColumn(column.key)
						.map((stage) => daysProblem(builtInDays[stage]))
						.find(Boolean);
					if (problem) problems[column.key] = problem;
				} else {
					const problem = daysProblem(column.stage.inactivity_days);
					if (problem) problems[column.stage.key] = problem;
				}
			}
		}
		return problems;
	});

	const atLimit = $derived(stages.length >= CUSTOM_STAGE_LIMIT);

	const dirty = $derived(
		detailed !== null &&
			savedDetailed !== null &&
			(detailed !== savedDetailed ||
				JSON.stringify(payloadFor(stages)) !== savedStages ||
				JSON.stringify(builtInDays) !== savedBuiltInDays)
	);

	function addStage(section: BoardSection) {
		const key = crypto.randomUUID();
		// A new stage starts at the end of its section. It can be moved from there.
		const last = SECTION_STAGES[section].at(-1);
		if (!last || atLimit) return key;
		stages = [
			...stages,
			{
				key,
				id: null,
				section,
				name: '',
				after_stage: last,
				requires_future_task: false,
				// A new stage starts with the days of the built-in stage it follows.
				inactivity_days: builtInDays[last]
			}
		];
		return key;
	}

	function renameStage(key: string, name: string) {
		stages = stages.map((stage) => (stage.key === key ? { ...stage, name } : stage));
		if (serverErrors[key]) serverErrors = { ...serverErrors, [key]: '' };
	}

	function requireTask(key: string, required: boolean) {
		stages = stages.map((stage) =>
			stage.key === key ? { ...stage, requires_future_task: required } : stage
		);
	}

	function setBuiltInDays(covered: readonly AnyBoardStage[], value: number | null) {
		const next = { ...builtInDays };
		for (const stage of covered) next[stage] = value;
		builtInDays = next;
	}

	function setStageDays(key: string, value: number | null) {
		stages = stages.map((stage) =>
			stage.key === key ? { ...stage, inactivity_days: value } : stage
		);
	}

	function moveStage(section: BoardSection, index: number, by: -1 | 1) {
		const placed = placeCustomStages(moveColumn(columns[section], index, by));
		stages = [...stages.filter((stage) => stage.section !== section), ...placed];
	}

	// The saved stage whose removal is being confirmed, by its row.
	let removingKey = $state<string | null>(null);

	// A saved stage as the dialog names it: by what the form calls it now, or by its saved name while the
	// name box is empty.
	function savedStage(stage: DraftStage): CustomStage | null {
		if (stage.id === null) return null;
		const saved = query.data?.pipeline.stages.find((other) => other.id === stage.id);
		return {
			...stage,
			id: stage.id,
			name: stage.name.trim() || (saved?.name ?? 'this stage'),
			inactivity_days: stage.inactivity_days ?? saved?.inactivity_days ?? 1
		};
	}

	const removingStage = $derived.by(() => {
		const stage = stages.find((other) => other.key === removingKey);
		return stage ? savedStage(stage) : null;
	});
	// Where the removed stage's cards may go: the other saved stages of its section.
	const removeDestinations = $derived(
		removingStage
			? stages.flatMap((stage) => {
					const saved = savedStage(stage);
					return saved && saved.id !== removingStage.id && saved.section === removingStage.section
						? [saved]
						: [];
				})
			: []
	);

	function removeStage(key: string) {
		const stage = stages.find((other) => other.key === key);
		if (!stage) return;
		// Never saved, so it is on nobody's board: it just leaves the form.
		if (stage.id === null) stages = stages.filter((other) => other.key !== key);
		else removingKey = key;
	}

	function warmStageCardCount(stageId: string) {
		void queryClient.prefetchQuery({
			queryKey: pipelineStageCardCountKey(stageId),
			queryFn: () => fetchPipelineStageCardCount(stageId)
		});
	}

	// The stage is already off the board by the time this runs. Only that stage leaves the form — anything
	// else the person was in the middle of changing stays exactly as they left it, still unsaved.
	async function stageRemoved(result: {
		stage: CustomStage;
		revision: number;
		movedCount: number;
		destinationName: string | null;
	}) {
		removingKey = null;
		const remaining = (query.data?.pipeline.stages ?? []).filter(
			(stage) => stage.id !== result.stage.id
		);
		queryClient.setQueryData<SettingsPipeline>(settingsPipelineKey, (current) =>
			current
				? {
						...current,
						pipeline: { ...current.pipeline, stages: remaining, revision: result.revision }
					}
				: current
		);
		stages = stages.filter((stage) => stage.id !== result.stage.id);
		savedStages = JSON.stringify(
			payloadFor(remaining.map((stage) => ({ ...stage, key: stage.id })))
		);

		const moved =
			result.movedCount === 0
				? ''
				: ` ${result.movedCount === 1 ? '1 card' : `${result.movedCount} cards`} moved to ${
						result.destinationName ? `“${result.destinationName}”` : 'the built-in stages'
					}.`;
		toast.success(`“${result.stage.name}” removed.${moved}`);
		await invalidatePipeline(queryClient);
	}

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (!dirty) return;
			event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});

	function cancel() {
		if (query.data) seed(query.data.pipeline);
		conflict = null;
		errorMessage = '';
	}

	async function save() {
		if (!query.data || detailed === null) return;
		errorMessage = '';
		conflict = null;
		serverErrors = {};
		attempted = true;
		if (Object.keys(nameProblems).length > 0) {
			errorMessage = 'Fix the stage names marked below, then save again.';
			return;
		}
		if (Object.keys(daysErrors).length > 0) {
			errorMessage = 'Fix the warning days marked below, then save again.';
			return;
		}

		saving = true;
		const keys = payloadKeys(stages);
		const result = await savePipelineSettings({
			expected_revision: query.data.pipeline.revision,
			detailed_assessment_stages: detailed,
			inactivity_days: builtInDays,
			stages: payloadFor(stages)
		}).catch((error: SettingsWriteError) => {
			// The server names a row by its place in the list it was sent ("stages.2.name"); anything it
			// says about the save as a whole goes to the banner.
			const fields = error.fieldErrors ?? {};
			const byRow: Record<string, string> = {};
			for (const [field, message] of Object.entries(fields)) {
				const key = keys[Number(/^stages\.(\d+)\./.exec(field)?.[1] ?? -1)];
				if (key) byRow[key] = message;
			}
			serverErrors = byRow;
			errorMessage =
				fields.form ??
				fields.stages ??
				(Object.keys(byRow).length > 0
					? 'Fix the stage names marked below, then save again.'
					: error.message);
			return null;
		});
		if (!result) {
			saving = false;
			return;
		}
		if (isSaveConflict(result)) {
			conflict = { editor_name: result.editor_name, edited_at: result.edited_at };
			saving = false;
			return;
		}

		// A new stage only gets its real identity from the server, so the form is reloaded from what was
		// actually saved rather than trusted as it stands.
		const fresh = await query.refetch();
		if (fresh.data) seed(fresh.data.pipeline);
		saving = false;
		toast.success('Pipeline settings saved.');
		await invalidatePipeline(queryClient);
	}
</script>

<svelte:head><title>Pipeline · Settings · Contractor CRM</title></svelte:head>

{#if query.isPending || detailed === null}
	<LoadingSkeleton variant="card" rows={2} />
{:else if query.isError}
	<ErrorState description="Pipeline settings could not be loaded." retry={() => query.refetch()} />
{:else}
	{@const canEdit = query.data.permissions.edit}
	{@const editor = query.data.pipeline.last_editor}

	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/(app)/settings') }, { label: 'Pipeline' }]}
	/>

	<RecordFormLayout title="Pipeline" icon={layoutKanbanIcon} bind:this={layout} error={saveError}>
		{#snippet main()}
			{#if !canEdit}
				<p class="pipeline-settings__readonly">
					Only owners and administrators can change this. {#if editor}Last changed by {editor.name ??
							'a teammate'}.{/if}
				</p>
			{/if}

			{#if detailed !== null}
				{@const d = detailed}
				<SectionBlock
					title="Assessment column"
					hint="How the board groups the three assessment stages for everyone in this organization."
					form
					level={3}
				>
					<Toggle
						id="pipeline-detailed-toggle"
						label="Show assessment stages as separate columns"
						description={d
							? 'The board shows Unscheduled, Scheduled, and Completed as three columns.'
							: 'The board shows one Assessment column, with each card’s state on the card itself.'}
						checked={d}
						disabled={!canEdit}
						labelSide="start"
						onchange={(checked) => (detailed = checked)}
					/>
				</SectionBlock>

				{#each BOARD_SECTIONS as section (section)}
					<SectionBlock
						title={section === 'request' ? 'Request stages' : 'Quote stages'}
						hint={section === 'request'
							? 'The columns a request moves through. Add your own follow-up stages between the built-in ones.'
							: 'The columns a quote moves through. Add your own follow-up stages between the built-in ones.'}
						form
						level={3}
					>
						<PipelineStageList
							columns={columns[section]}
							{canEdit}
							canAdd={!atLimit}
							errors={rowErrors}
							days={builtInDays}
							daysErrors={attempted ? daysErrors : {}}
							onBuiltInDays={setBuiltInDays}
							onStageDays={setStageDays}
							onAdd={() => addStage(section)}
							onRename={renameStage}
							onRequireTask={requireTask}
							onMove={(index, by) => moveStage(section, index, by)}
							onRemove={removeStage}
							onRemoveIntent={warmStageCardCount}
						/>
					</SectionBlock>
				{/each}

				<p class="pipeline-settings__limit">
					{stages.length} of {CUSTOM_STAGE_LIMIT} custom stages used.
					{#if atLimit}You have reached the limit, so no more can be added.{/if}
					Built-in stages follow real work — a request coming in, an assessment being booked, a quote
					being sent — so they cannot be renamed, moved, or removed. Removing one of your own stages asks
					where its cards go first. Switch on “On hold stage” for a column like “Waiting till spring”:
					cards there stay open and are never counted as lost. “Warn after” is how many days a card in
					that stage can go without real progress — a customer reply, a booked visit, a quote sent, or
					a finished task — before it is marked as needing attention.
				</p>

				<SectionBlock
					title="Lost reasons"
					hint="The reasons your team picks from when work is lost. Changes here save straight away."
					form
					level={3}
				>
					<PipelineLostReasonList {canEdit} />
				</SectionBlock>
			{/if}
		{/snippet}

		{#snippet actions()}
			{#if canEdit}
				<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
				<Button
					onclick={() => void save().finally(() => layout?.revealError())}
					disabled={!dirty || saving}
					loading={saving}>Save</Button
				>
			{/if}
		{/snippet}
	</RecordFormLayout>

	<PipelineStageRemoveDialog
		stage={removingStage}
		destinations={removeDestinations}
		revision={query.data.pipeline.revision}
		onClose={() => (removingKey = null)}
		onRemoved={stageRemoved}
	/>
{/if}

<style lang="scss">
	.pipeline-settings {
		&__readonly {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
		}

		&__limit {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
