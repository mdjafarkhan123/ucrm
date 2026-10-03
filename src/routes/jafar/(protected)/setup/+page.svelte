<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SetupStageList from '$lib/components/jafar/setup/SetupStageList.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { jafarOnboardingKey, jafarSetupEditorKey } from '$lib/jafar/query-keys';
	import {
		discardSetupDraft,
		draftStages,
		fetchSetupEditor,
		isStaleSetupDraft,
		publishChanges,
		publishSetupDraft,
		sameStages,
		saveSetupDraft,
		SetupEditorError,
		startSetupDraft,
		type DraftStage,
		type SetupEditor
	} from '$lib/jafar/setup-editor';

	// Client onboarding A4 (plan §2.1, ADR 0006): Jafar writes the setup clients go through. He edits a draft
	// and publishes it, the way package editions are published (ADR 0003): clients see only the published
	// version, and a client still filling in setup sees a published change on their next page.

	const queryClient = useQueryClient();
	const toast = getToastManager();

	const editorQuery = createQuery(() => ({
		queryKey: jafarSetupEditorKey,
		queryFn: fetchSetupEditor
	}));
	const editor = $derived(editorQuery.data);

	// The draft as the form holds it, and the saved draft it was loaded from.
	let stages = $state<DraftStage[]>([]);
	let loaded = $state<{ versionId: string; revision: number; stages: DraftStage[] } | null>(null);
	let stageList = $state<SetupStageList>();
	let newRows = 0;

	let saving = $state(false);
	let opening = $state(false);
	let publishOpen = $state(false);
	let publishing = $state(false);
	let discardOpen = $state(false);
	let discarding = $state(false);
	let saveError = $state('');
	let fieldErrors = $state<Record<string, string>>({});

	const dirty = $derived(loaded !== null && !sameStages(stages, loaded.stages));

	function load(next: SetupEditor) {
		if (!next.draft) {
			loaded = null;
			stages = [];
			return;
		}
		const saved = draftStages(next.draft.stages);
		loaded = { versionId: next.draft.version_id, revision: next.draft.revision, stages: saved };
		stages = draftStages(next.draft.stages);
		saveError = '';
		fieldErrors = {};
	}

	// Load the draft when it first arrives, or when it changes underneath a form with nothing unsaved.
	$effect(() => {
		const next = editor;
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
		// Each client's task count follows the published stages.
		void queryClient.invalidateQueries({ queryKey: jafarOnboardingKey });
	}

	function draftRevision() {
		return { version_id: loaded!.versionId, revision: loaded!.revision };
	}

	// The server names a field as `stages.<index>.<field>`; the list names it by row.
	function rowErrors(errors: Record<string, string>) {
		const byRow: Record<string, string> = {};
		for (const [path, message] of Object.entries(errors)) {
			const match = /^stages\.(\d+)\.(title|description)$/.exec(path);
			const row = match ? stages[Number(match[1])] : undefined;
			if (row) byRow[`${row.rowId}.${match![2]}`] = message;
		}
		return byRow;
	}

	function failed(error: unknown, fallback: string) {
		if (isStaleSetupDraft(error) && error.body.editor) {
			adopt(error.body.editor);
			toast.error(error.message);
			return;
		}
		if (error instanceof SetupEditorError && error.body.field_errors) {
			fieldErrors = rowErrors(error.body.field_errors);
			saveError = error.message;
			return;
		}
		saveError = error instanceof Error ? error.message : fallback;
	}

	async function start() {
		opening = true;
		try {
			adopt(await startSetupDraft());
		} catch (error) {
			toast.error(error instanceof Error ? error.message : 'The draft could not be started.');
		} finally {
			opening = false;
		}
	}

	function addStage() {
		newRows += 1;
		const rowId = `new-${newRows}`;
		stages.push({
			rowId,
			key: null,
			title: '',
			description: '',
			service_key: null,
			questions: 0,
			builtIn: false
		});
		void stageList?.focusRow(rowId);
	}

	async function save() {
		if (!loaded) return;
		saving = true;
		saveError = '';
		fieldErrors = {};
		try {
			adopt(await saveSetupDraft(draftRevision(), stages));
			toast.success('Draft saved. Clients still see the published setup.');
		} catch (error) {
			failed(error, 'The draft could not be saved.');
		} finally {
			saving = false;
		}
	}

	function cancel() {
		if (loaded) stages = draftStages(editor?.draft?.stages ?? []);
		saveError = '';
		fieldErrors = {};
	}

	async function publish() {
		publishing = true;
		try {
			adopt(await publishSetupDraft(draftRevision()));
			publishOpen = false;
			toast.success('Published. Clients filling in setup see it on their next page.');
		} catch (error) {
			publishOpen = false;
			if (isStaleSetupDraft(error) && error.body.editor) {
				adopt(error.body.editor);
				toast.error('The draft was saved again in another tab. Check it, then publish.');
			} else {
				toast.error(error instanceof Error ? error.message : 'The draft could not be published.');
			}
		} finally {
			publishing = false;
		}
	}

	async function discard() {
		discarding = true;
		try {
			adopt(await discardSetupDraft(draftRevision()));
			discardOpen = false;
			toast.success('Draft discarded.');
		} catch (error) {
			discardOpen = false;
			failed(error, 'The draft could not be discarded.');
			if (saveError) toast.error(saveError);
		} finally {
			discarding = false;
		}
	}

	beforeNavigate((navigation) => {
		if (!dirty || saving) return;
		if (!confirm('Leave this page? Your changes to this draft have not been saved.')) {
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

	const changes = $derived(
		editor?.draft && editor.published
			? publishChanges(editor.published.stages, editor.draft.stages, editor.services)
			: []
	);
	const publishedStages = $derived(editor?.published ? draftStages(editor.published.stages) : []);

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		dateStyle: 'medium',
		timeStyle: 'short'
	});
	const formatDate = (value: string) => dateFormat.format(new Date(value));
</script>

<svelte:head><title>Client setup · Control Room</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<main class="setup-editor">
	{#if editorQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading client setup" />
	{:else if editorQuery.isError}
		<ErrorState
			title="The client setup could not be loaded"
			description={editorQuery.error.message}
			retry={() => editorQuery.refetch()}
		/>
	{:else if editor}
		{#snippet rail()}
			<RailCard title="Status">
				<dl class="setup-editor__status">
					<div>
						<dt>Clients see</dt>
						<dd>
							{#if editor.published}
								<Badge status="success" size="small"
									>Version {editor.published.version_number}</Badge
								>
								<span class="setup-editor__muted"
									>Published {formatDate(editor.published.published_at)}</span
								>
							{:else}
								<span class="setup-editor__muted">Nothing published</span>
							{/if}
						</dd>
					</div>
					<div>
						<dt>Draft</dt>
						<dd>
							{#if editor.draft}
								<Badge status={dirty ? 'warning' : 'inactive'} size="small"
									>{dirty ? 'Unsaved changes' : 'Saved'}</Badge
								>
								<span class="setup-editor__muted"
									>Last saved {formatDate(editor.draft.updated_at)}{editor.draft.updated_by_email
										? ` by ${editor.draft.updated_by_email}`
										: ''}</span
								>
							{:else}
								<span class="setup-editor__muted">No draft open</span>
							{/if}
						</dd>
					</div>
				</dl>
			</RailCard>

			{#if editor.draft}
				<RailCard title="Publish">
					<p class="setup-editor__muted">
						{#if dirty}
							Save your changes first. Publishing uses the saved draft, exactly as saved.
						{:else if changes.length === 0}
							This draft is the same as what clients see now.
						{:else}
							Review the changes, then publish them as version {editor.draft.version_number}.
						{/if}
					</p>
					<div>
						<Button
							size="small"
							disabled={dirty || saving || changes.length === 0}
							onclick={() => (publishOpen = true)}
							><span class="setup-editor__button-icon" aria-hidden="true">{@html sendIcon}</span
							>Review and publish</Button
						>
					</div>
				</RailCard>
			{/if}

			{#if editor.history.length}
				<RailCard title="History">
					<ol class="setup-editor__history">
						{#each editor.history as version (version.version_number)}
							<li>
								<span class="setup-editor__history-name">Version {version.version_number}</span>
								<span class="setup-editor__muted"
									>{formatDate(version.published_at)}{version.published_by_email &&
									version.published_by_email !== 'migration'
										? ` · ${version.published_by_email}`
										: ''}</span
								>
								{#if version.status === 'published'}
									<Badge status="success" size="small">Live</Badge>
								{/if}
							</li>
						{/each}
					</ol>
				</RailCard>
			{/if}

			{#if editor.draft}
				<RailCard title="Discard draft">
					<p class="setup-editor__muted">
						Throw away this draft. Clients keep the published setup.
					</p>
					<div>
						<Button
							variant="secondary"
							variation="destructive"
							size="small"
							disabled={saving}
							onclick={() => (discardOpen = true)}>Discard draft</Button
						>
					</div>
				</RailCard>
			{/if}
		{/snippet}

		{#if !editor.draft}
			<RecordFormLayout title="Client setup" icon={listCheckIcon} {rail}>
				{#snippet main()}
					<div class="setup-editor__intro">
						<p>
							The stages every paid client works through after signing in. A stage tied to a service
							shows only to clients whose package includes it. To change them, start a draft —
							clients keep seeing version {editor.published?.version_number} until you publish.
						</p>
						<div>
							<Button loading={opening} onclick={start}
								><span class="setup-editor__button-icon" aria-hidden="true">{@html pencilIcon}</span
								>Start a draft</Button
							>
						</div>
					</div>
					<SectionBlock title="Stages clients see">
						<SetupStageList stages={publishedStages} services={editor.services} canEdit={false} />
					</SectionBlock>
				{/snippet}
			</RecordFormLayout>
		{:else}
			<RecordFormLayout
				title="Client setup"
				icon={listCheckIcon}
				error={saveError}
				errorFields={[]}
				{rail}
			>
				{#snippet main()}
					<p class="setup-editor__lead">
						Editing draft version {editor.draft?.version_number}. Clients see none of this until you
						publish. Save your stage changes, then use Edit questions to change what a stage asks.
					</p>
					<SectionBlock title="Stages" form>
						{#snippet actions()}
							<Button
								size="small"
								variant="secondary"
								disabled={stages.length >= 30}
								onclick={addStage}
								><span class="setup-editor__button-icon" aria-hidden="true">{@html plusIcon}</span
								>Add stage</Button
							>
						{/snippet}
						<SetupStageList
							bind:this={stageList}
							bind:stages
							services={editor.services}
							canEdit
							errors={fieldErrors}
						/>
					</SectionBlock>
				{/snippet}

				{#snippet actions()}
					<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
					<Button onclick={save} disabled={!dirty || saving} loading={saving}>Save draft</Button>
				{/snippet}
			</RecordFormLayout>
		{/if}
	{/if}
</main>

<ConfirmDialog
	open={publishOpen}
	title={`Publish version ${editor?.draft?.version_number ?? ''}?`}
	icon={sendIcon}
	confirmLabel="Publish"
	loading={publishing}
	onConfirm={publish}
	onClose={() => (publishOpen = false)}
>
	<p>Clients filling in setup see these changes on their next page:</p>
	<ul class="setup-editor__changes">
		{#each changes as change (change)}
			<li>{change}</li>
		{/each}
	</ul>
	<p class="setup-editor__muted">
		Clients who already sent their setup to Uplift are not reopened.
	</p>
</ConfirmDialog>

<ConfirmDialog
	open={discardOpen}
	title="Discard this draft?"
	tone="critical"
	confirmLabel="Discard draft"
	destructive
	loading={discarding}
	onConfirm={discard}
	onClose={() => (discardOpen = false)}
>
	<p>Every change in the draft is thrown away. Clients keep the published setup.</p>
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.setup-editor {
		min-width: 0;
		display: grid;
		gap: var(--space-large);
	}

	.setup-editor__intro {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);

		p {
			margin: 0;
			max-width: 68ch;
			color: var(--color-text);
		}
	}

	.setup-editor__lead {
		margin: 0;
		color: var(--color-text--secondary);
	}

	.setup-editor__muted {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	p.setup-editor__muted {
		margin: 0;
	}

	.setup-editor__status {
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
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			margin: 0;
		}
	}

	.setup-editor__history {
		display: grid;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;

		li {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-smallest) var(--space-small);
		}
	}

	.setup-editor__history-name {
		color: var(--color-heading);
		font-weight: 600;
	}

	.setup-editor__changes {
		margin: var(--space-small) 0;
		padding-left: var(--space-large);

		li + li {
			margin-top: var(--space-smallest);
		}
	}

	.setup-editor__button-icon {
		display: inline-grid;
		place-items: center;

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}
</style>
