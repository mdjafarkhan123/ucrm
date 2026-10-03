<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import { resolve } from '$app/paths';
	import headingIcon from '@tabler/icons/outline/heading.svg?raw';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SetupQuestionList from '$lib/components/jafar/setup/SetupQuestionList.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { jafarSetupEditorKey } from '$lib/jafar/query-keys';
	import {
		draftItems,
		fetchSetupEditor,
		isStaleSetupDraft,
		sameItems,
		saveSetupStageItems,
		SetupEditorError,
		stageAudience,
		type DraftItem,
		type SetupEditor
	} from '$lib/jafar/setup-editor';

	// Client onboarding A5 (plan §2.1, ADR 0006): the headings and questions of one setup stage, edited in the
	// same draft as the stages and published with them from the Client setup page.

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const stageKey = $derived(page.params.stage ?? '');

	const editorQuery = createQuery(() => ({
		queryKey: jafarSetupEditorKey,
		queryFn: fetchSetupEditor
	}));
	const editor = $derived(editorQuery.data);
	const stage = $derived(editor?.draft?.stages.find((candidate) => candidate.key === stageKey));
	const answered = $derived(new Set(editor?.answered ?? []));
	// What a "show only if" rule here can depend on from before this stage, as last saved.
	const earlierStages = $derived.by(() => {
		const stages = editor?.draft?.stages ?? [];
		const index = stages.findIndex((candidate) => candidate.key === stageKey);
		return index === -1 ? [] : stages.slice(0, index);
	});

	let items = $state<DraftItem[]>([]);
	let loaded = $state<{ versionId: string; revision: number; items: DraftItem[] } | null>(null);
	let questionList = $state<SetupQuestionList>();
	let newRows = 0;

	let saving = $state(false);
	let saveError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const dirty = $derived(loaded !== null && !sameItems(items, loaded.items));
	const questionCount = $derived(items.filter((item) => item.type === 'question').length);

	function load(next: SetupEditor) {
		const nextStage = next.draft?.stages.find((candidate) => candidate.key === stageKey);
		if (!next.draft || !nextStage) {
			loaded = null;
			items = [];
			return;
		}
		loaded = {
			versionId: next.draft.version_id,
			revision: next.draft.revision,
			items: draftItems(nextStage.items)
		};
		items = draftItems(nextStage.items);
		saveError = '';
		fieldErrors = {};
	}

	// Load the stage when the draft first arrives, or when it changes underneath a form with nothing unsaved.
	$effect(() => {
		const next = editor;
		void stageKey;
		if (!next) return;
		untrack(() => {
			const draft = next.draft;
			if (!draft) {
				if (loaded) load(next);
				return;
			}
			if (!loaded || loaded.versionId !== draft.version_id) return load(next);
			if (loaded.revision !== draft.revision && !dirty) load(next);
		});
	});

	function adopt(next: SetupEditor) {
		queryClient.setQueryData(jafarSetupEditorKey, next);
		load(next);
	}

	// The server names a field as `items.<index>.<field>`; the list names it by row.
	function rowErrors(errors: Record<string, string>) {
		const byRow: Record<string, string> = {};
		for (const [path, message] of Object.entries(errors)) {
			const match = /^items\.(\d+)\.(label|hint|kind|options|show_if)/.exec(path);
			const row = match ? items[Number(match[1])] : undefined;
			if (row) byRow[`${row.rowId}.${match![2]}`] ??= message;
		}
		return byRow;
	}

	function addItem(type: DraftItem['type']) {
		newRows += 1;
		const rowId = `new-${newRows}`;
		items.push({
			rowId,
			type,
			fact_key: null,
			label: '',
			hint: '',
			built_in: false,
			required: false,
			can_defer: false,
			kind: type === 'question' ? 'text' : null,
			options: [],
			show_if: []
		});
		void questionList?.openNew(rowId);
	}

	async function save() {
		if (!loaded) return;
		saving = true;
		saveError = '';
		fieldErrors = {};
		try {
			adopt(
				await saveSetupStageItems(
					{ version_id: loaded.versionId, revision: loaded.revision },
					stageKey,
					items
				)
			);
			toast.success('Questions saved to the draft. Clients still see the published setup.');
		} catch (error) {
			if (isStaleSetupDraft(error) && error.body.editor) {
				adopt(error.body.editor);
				toast.error(error.message);
			} else if (error instanceof SetupEditorError && error.body.field_errors) {
				fieldErrors = rowErrors(error.body.field_errors);
				saveError = error.message;
				questionList?.openFirstError();
			} else {
				saveError = error instanceof Error ? error.message : 'The questions could not be saved.';
			}
		} finally {
			saving = false;
		}
	}

	function cancel() {
		if (loaded) items = draftItems(stage?.items ?? []);
		saveError = '';
		fieldErrors = {};
	}

	beforeNavigate((navigation) => {
		if (!dirty || saving) return;
		if (!confirm('Leave this page? Your changes to these questions have not been saved.')) {
			navigation.cancel();
		}
	});
	$effect(() => {
		function handler(event: BeforeUnloadEvent) {
			if (dirty) event.preventDefault();
		}
		window.addEventListener('beforeunload', handler);
		return () => window.removeEventListener('beforeunload', handler);
	});
</script>

<svelte:head><title>{stage?.title ?? 'Stage'} · Client setup · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="setup-stage">
	{#if editorQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading the stage" />
	{:else if editorQuery.isError}
		<ErrorState
			title="The client setup could not be loaded"
			description={editorQuery.error.message}
			retry={() => editorQuery.refetch()}
		/>
	{:else if editor && (!editor.draft || !stage)}
		<ErrorState
			title={editor.draft ? 'This stage is not in the draft' : 'No draft is open'}
			description={editor.draft
				? 'It may have been removed, or not saved yet. Questions can be added once the stage is saved.'
				: 'Start a draft on the Client setup page to change the questions. Clients keep seeing the published setup until you publish.'}
		>
			{#snippet action()}<Button variant="secondary" href={resolve('/jafar/setup')}
					>Back to Client setup</Button
				>{/snippet}
		</ErrorState>
	{:else if editor && stage}
		{#snippet rail()}
			<RailCard title="This stage">
				<dl class="setup-stage__facts">
					<div>
						<dt>Who sees it</dt>
						<dd>{stageAudience(stage.service_key, editor.services)}</dd>
					</div>
					<div>
						<dt>Questions</dt>
						<dd>{questionCount}</dd>
					</div>
					<div>
						<dt>Draft</dt>
						<dd>
							<Badge status={dirty ? 'warning' : 'inactive'} size="small"
								>{dirty ? 'Unsaved changes' : 'Saved'}</Badge
							>
						</dd>
					</div>
				</dl>
				<p class="setup-stage__muted">
					Publish from the Client setup page, together with any other changes in version {editor
						.draft?.version_number}.
				</p>
				<div>
					<Button size="small" variant="secondary" href={resolve('/jafar/setup')}>All stages</Button
					>
				</div>
			</RailCard>
		{/snippet}

		<RecordFormLayout title={stage.title} icon={listCheckIcon} error={saveError} {rail}>
			{#snippet main()}
				<p class="setup-stage__lead">
					Editing draft version {editor.draft?.version_number}. Clients see none of this until you
					publish. Questions are asked in this order; a heading starts a new group.
				</p>
				<SectionBlock title="Questions" form>
					{#snippet actions()}
						<div class="setup-stage__add">
							<Button
								size="small"
								variant="secondary"
								disabled={items.length >= 80}
								onclick={() => addItem('heading')}
								><span class="setup-stage__button-icon" aria-hidden="true">{@html headingIcon}</span
								>Add heading</Button
							>
							<Button
								size="small"
								variant="secondary"
								disabled={items.length >= 80}
								onclick={() => addItem('question')}
								><span class="setup-stage__button-icon" aria-hidden="true">{@html plusIcon}</span
								>Add question</Button
							>
						</div>
					{/snippet}
					<SetupQuestionList
						bind:this={questionList}
						bind:items
						{answered}
						{earlierStages}
						services={editor.services}
						errors={fieldErrors}
					/>
				</SectionBlock>
			{/snippet}

			{#snippet actions()}
				<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
				<Button onclick={save} disabled={!dirty || saving} loading={saving}>Save questions</Button>
			{/snippet}
		</RecordFormLayout>
	{/if}
</main>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-stage {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.setup-stage__lead {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.setup-stage__muted {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.setup-stage__add {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.setup-stage__facts {
		display: grid;
		gap: var(--space-base);
		margin: 0;

		div {
			display: grid;
			gap: var(--space-smallest);
		}

		dt {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-smaller);
			font-weight: 700;
			letter-spacing: var(--typography--letterSpacing-loose);
			text-transform: uppercase;
		}

		dd {
			margin: 0;
			color: var(--color-heading);
		}
	}

	.setup-stage__button-icon {
		display: inline-grid;
		place-items: center;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
</style>
