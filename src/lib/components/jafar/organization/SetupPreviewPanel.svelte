<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import presentationIcon from '@tabler/icons/outline/presentation.svg?raw';
	import arrowUpIcon from '@tabler/icons/outline/arrow-up.svg?raw';
	import arrowDownIcon from '@tabler/icons/outline/arrow-down.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import PreviewCardBody from '$lib/components/setup/PreviewCardBody.svelte';
	import PreviewScreenshots from '$lib/components/setup/PreviewScreenshots.svelte';
	import {
		organizationLaunchApprovalQuery,
		organizationPreviewQuery,
		organizationPreviewScreenshotUrls,
		organizationPreviewUrl
	} from '$lib/jafar/organization-setup-queries';
	import { jafarOnboardingKey, jafarOrganizationKey } from '$lib/jafar/query-keys';
	import {
		PREVIEW_CARDS_MAX,
		PREVIEW_CHOICE_LABEL,
		PREVIEW_KINDS,
		PREVIEW_KIND_OWNER_LABEL,
		PREVIEW_LINK_MAX,
		PREVIEW_SUMMARY_MAX,
		PREVIEW_TITLE_MAX,
		askingNotes,
		starterPreviewCards,
		type PreviewKind,
		type PreviewScreenshotUpload,
		type PreviewVersion
	} from '$lib/setup/preview';
	import { currentLaunchApproval } from '$lib/setup/launch-approval';
	import { formatDateTime } from './format';

	// Client onboarding E3 (plan §6): the preview Jafar writes once Ready is recorded — one card per part of the
	// package, each with a summary, an optional link and screenshots — and releases to the client. Their notes come
	// back once, together; he labels each as Correction, Our mistake or New request, and the client sees the label.
	// Each release is a new version; earlier ones stay readable below.
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const query = createQuery(() => organizationPreviewQuery(organizationId));
	// E4: what a release would cancel or replace, said in the Release dialog.
	const approvals = createQuery(() => organizationLaunchApprovalQuery(organizationId));
	const launch = $derived(currentLaunchApproval(approvals.data ?? []));
	const urls = $derived(organizationPreviewScreenshotUrls(organizationId));

	type EditCard = {
		id: string;
		title: string;
		summary: string;
		link: string;
		screenshots: PreviewScreenshotUpload[];
	};

	/** The cards being written, or null when the editor is closed. */
	let editing = $state<EditCard[] | null>(null);
	/** Cards with a screenshot still uploading; nothing saves until they finish. */
	let busyCards = $state<Record<string, boolean>>({});
	const uploading = $derived(Object.values(busyCards).some(Boolean));
	let formError = $state('');
	let notice = $state('');
	let confirmRelease = $state(false);
	let confirmDiscard = $state(false);

	const newest = $derived(query.data?.released[0] ?? null);
	const older = $derived(query.data?.released.slice(1) ?? []);

	const blankCard = (title = ''): EditCard => ({
		id: crypto.randomUUID(),
		title,
		summary: '',
		link: '',
		screenshots: []
	});

	function openEditor() {
		formError = '';
		notice = '';
		const data = query.data;
		if (!data) return;
		const from = data.draft?.cards ?? newest?.cards;
		editing = from
			? from.map((card) => ({ ...card, link: card.link ?? '', screenshots: [...card.screenshots] }))
			: starterPreviewCards(data.service_keys).map((title) => blankCard(title));
	}

	const refresh = () =>
		Promise.all([
			queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) }),
			queryClient.invalidateQueries({ queryKey: jafarOnboardingKey })
		]);

	async function request(url: string, method: string, body?: unknown) {
		const response = await fetch(url, {
			method,
			headers: body === undefined ? undefined : { 'content-type': 'application/json' },
			body: body === undefined ? undefined : JSON.stringify(body)
		});
		const result = (await response.json().catch(() => ({}))) as Record<string, unknown> & {
			error?: string;
			field_errors?: Record<string, string>;
		};
		if (!response.ok)
			throw new Error(
				Object.values(result.field_errors ?? {})[0] ??
					result.error ??
					'That could not be saved. Try again.'
			);
		return result;
	}

	const saveDraft = (cards: EditCard[]) =>
		request(organizationPreviewUrl(organizationId), 'POST', {
			cards: cards.map((card) => ({ ...card, link: card.link.trim() || null }))
		}) as Promise<{ version: number }>;

	const save = createMutation(() => ({
		mutationFn: async (release: boolean) => {
			if (!editing) throw new Error('Nothing to save.');
			const saved = await saveDraft(editing);
			if (!release) return { released: false, emailed: true };
			const result = await request(`${organizationPreviewUrl(organizationId)}/release`, 'POST', {
				version: saved.version
			});
			return { released: true, emailed: result.emailed !== false };
		},
		onMutate: () => {
			formError = '';
			notice = '';
		},
		onSuccess: (result) => {
			confirmRelease = false;
			if (!result.released) {
				notice = 'Draft saved. The client does not see it until you release it.';
				return;
			}
			editing = null;
			notice = result.emailed
				? 'Released. The client’s owners and administrators have been emailed.'
				: 'Released, but the email to the client could not be queued. Tell them in Chat with Uplift.';
		},
		onError: (error) => {
			confirmRelease = false;
			formError = error.message;
		},
		onSettled: refresh
	}));

	const discard = createMutation(() => ({
		mutationFn: () => request(organizationPreviewUrl(organizationId), 'DELETE'),
		onSuccess: () => {
			confirmDiscard = false;
			editing = null;
			notice = '';
		},
		onError: (error) => {
			confirmDiscard = false;
			formError = error.message;
		},
		onSettled: refresh
	}));

	let sortError = $state('');
	const sort = createMutation(() => ({
		mutationFn: (input: { version: number; card_id: string; kind: PreviewKind }) =>
			request(`${organizationPreviewUrl(organizationId)}/sort`, 'POST', input),
		onMutate: () => (sortError = ''),
		onError: (error) => (sortError = error.message),
		onSettled: refresh
	}));

	function move(index: number, by: number) {
		if (!editing) return;
		const next = [...editing];
		const [card] = next.splice(index, 1);
		next.splice(index + by, 0, card);
		editing = next;
	}

	const editorProblem = $derived.by(() => {
		if (!editing) return '';
		if (editing.length === 0) return 'Add at least one card.';
		if (editing.some((card) => !card.title.trim() || !card.summary.trim()))
			return 'Every card needs a title and a summary.';
		if (editing.some((card) => card.link.trim() && !/^https:\/\/\S+$/.test(card.link.trim())))
			return 'A link must be a full address starting with https://.';
		return '';
	});

	function versionStatus(version: PreviewVersion) {
		if (!version.notes_sent_at) return { label: 'Client reviewing', tone: 'warning' as const };
		const unsorted = askingNotes(version.notes).filter((note) => !note.kind).length;
		return unsorted > 0
			? { label: `${unsorted} to sort`, tone: 'critical' as const }
			: { label: 'Notes sorted', tone: 'success' as const };
	}

	const kindOptions = PREVIEW_KINDS.map((kind) => ({
		value: kind,
		label: PREVIEW_KIND_OWNER_LABEL[kind]
	}));
</script>

{#snippet versionView(version: PreviewVersion)}
	{@const status = versionStatus(version)}
	<div class="setup-preview__version-head">
		<span>
			Released {formatDateTime(version.released_at)} ·
			{version.correction_round ? 'Opens the correction round' : 'Correction round already used'}
		</span>
		<StatusBadge status={status.tone}>{status.label}</StatusBadge>
	</div>
	{#if version.notes_sent_at}
		<p class="setup-preview__muted">
			Notes sent {formatDateTime(version.notes_sent_at)} by {version.notes_sent_by_name}
		</p>
	{/if}
	<ol class="setup-preview__cards">
		{#each version.cards as card (card.id)}
			{@const note = version.notes_sent_at
				? version.notes.find((each) => each.card_id === card.id)
				: undefined}
			<li class="setup-preview__card">
				<h4 class="setup-preview__card-title">{card.title}</h4>
				<PreviewCardBody {card} {urls} />
				{#if note}
					<div
						class="setup-preview__note"
						class:setup-preview__note--fine={note.choice === 'looks_right'}
					>
						<strong>Client: {PREVIEW_CHOICE_LABEL[note.choice]}</strong>
						{#if note.note}<p>{note.note}</p>{/if}
						<PreviewScreenshots value={note.screenshots} {urls} />
						{#if note.choice !== 'looks_right'}
							<SegmentedControl
								size="small"
								ariaLabel="Label for this note"
								options={kindOptions}
								value={note.kind ?? ''}
								disabled={sort.isPending}
								onchange={(kind) =>
									sort.mutate({
										version: version.version,
										card_id: card.id,
										kind: kind as PreviewKind
									})}
							/>
						{/if}
					</div>
				{:else if version.notes_sent_at}
					<p class="setup-preview__muted">No note on this card.</p>
				{/if}
			</li>
		{/each}
	</ol>
{/snippet}

{#if query.isPending}
	<LoadingSkeleton variant="card" label="Loading the preview" />
{:else if query.isError}
	<ErrorState
		title="The preview could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if query.data.ready}
	{@const data = query.data}
	<SectionBlock
		title="Preview"
		icon={presentationIcon}
		hint="What Uplift built, one card per part of their package. The client marks each card and sends their notes once; their package includes one round of corrections, and Uplift’s mistakes are always fixed."
	>
		{#snippet actions()}
			{#if data.draft && !editing}
				<StatusBadge status="inactive">Draft saved</StatusBadge>
			{/if}
		{/snippet}

		{#if editing}
			<div class="setup-preview__editor">
				{#each editing as card, index (card.id)}
					<fieldset class="setup-preview__edit-card">
						<legend class="setup-preview__hidden">Card {index + 1}</legend>
						<div class="setup-preview__edit-tools">
							<span class="setup-preview__muted">Card {index + 1} of {editing.length}</span>
							<span class="setup-preview__tool-buttons">
								<button
									type="button"
									class="setup-preview__tool"
									aria-label="Move card {index + 1} up"
									disabled={index === 0}
									onclick={() => move(index, -1)}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html arrowUpIcon}
								</button>
								<button
									type="button"
									class="setup-preview__tool"
									aria-label="Move card {index + 1} down"
									disabled={index === editing.length - 1}
									onclick={() => move(index, 1)}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html arrowDownIcon}
								</button>
								<button
									type="button"
									class="setup-preview__tool setup-preview__tool--remove"
									aria-label="Remove card {index + 1}"
									onclick={() => (editing = editing?.filter((each) => each.id !== card.id) ?? null)}
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									{@html trashIcon}
								</button>
							</span>
						</div>
						<Input
							id="preview-title-{card.id}"
							label="Title"
							bind:value={card.title}
							maxlength={PREVIEW_TITLE_MAX}
						/>
						<Textarea
							id="preview-summary-{card.id}"
							label="What the client should check"
							rows={4}
							maxlength={PREVIEW_SUMMARY_MAX}
							bind:value={card.summary}
						/>
						<Input
							id="preview-link-{card.id}"
							label="Link (optional)"
							type="url"
							placeholder="https://"
							maxlength={PREVIEW_LINK_MAX}
							bind:value={card.link}
						/>
						<PreviewScreenshots
							bind:value={card.screenshots}
							{urls}
							editable
							onUploadingChange={(busy) => (busyCards[card.id] = busy)}
						/>
					</fieldset>
				{/each}

				{#if editing.length < PREVIEW_CARDS_MAX}
					<Button
						variant="secondary"
						variation="subtle"
						size="small"
						onclick={() => editing && (editing = [...editing, blankCard()])}>Add a card</Button
					>
				{/if}

				{#if formError || editorProblem}
					<p class="setup-preview__error" role="alert">{formError || editorProblem}</p>
				{/if}
				{#if notice}
					<p class="setup-preview__notice" role="status">{notice}</p>
				{/if}

				<div class="setup-preview__actions">
					<Button
						onclick={() => (confirmRelease = true)}
						disabled={Boolean(editorProblem) || uploading || save.isPending}
						>Release to the client</Button
					>
					<Button
						variant="secondary"
						onclick={() => save.mutate(false)}
						loading={save.isPending && !confirmRelease}
						disabled={Boolean(editorProblem) || uploading}>Save draft</Button
					>
					<Button
						variant="tertiary"
						onclick={() => {
							editing = null;
							formError = '';
							notice = '';
						}}>Close</Button
					>
					{#if data.draft}
						<Button
							variant="tertiary"
							variation="destructive"
							onclick={() => (confirmDiscard = true)}>Discard draft</Button
						>
					{/if}
				</div>
			</div>
		{:else}
			{#if notice}
				<p class="setup-preview__notice" role="status">{notice}</p>
			{/if}
			<div class="setup-preview__start">
				{#if data.draft}
					<p class="setup-preview__muted">
						Draft of version {data.draft.version}, saved {formatDateTime(data.draft.updated_at)}.
						The client does not see it yet.
					</p>
					<Button size="small" onclick={openEditor}>Continue the draft</Button>
				{:else if newest}
					<Button size="small" variant="secondary" onclick={openEditor}
						>Write an updated preview</Button
					>
				{:else}
					<p class="setup-preview__muted">
						Nothing written yet. The cards start with one per part of their package.
					</p>
					<Button size="small" onclick={openEditor}>Write the preview</Button>
				{/if}
			</div>
		{/if}

		{#if newest}
			<div class="setup-preview__released">
				<h3 class="setup-preview__version-title">
					Version {newest.version} — what the client sees
				</h3>
				{@render versionView(newest)}
				{#if sortError}
					<p class="setup-preview__error" role="alert">{sortError}</p>
				{/if}
			</div>
		{/if}

		{#each older as version (version.version)}
			<details class="setup-preview__older">
				<summary>Version {version.version}</summary>
				{@render versionView(version)}
			</details>
		{/each}
	</SectionBlock>
{/if}

<ConfirmDialog
	open={confirmRelease}
	title="Release this preview?"
	confirmLabel="Release and email the client"
	loading={save.isPending}
	onConfirm={() => save.mutate(true)}
	onClose={() => (confirmRelease = false)}
>
	<p>
		The client’s owners and administrators get an email and see the preview on their Setup page.
		Once released, this version cannot be changed — you can release an updated one later.
	</p>
	{#if newest && !newest.notes_sent_at}
		<p>It replaces version {newest.version}, which the client has not sent notes on yet.</p>
	{/if}
	{#if launch?.status === 'open'}
		<p>
			It cancels the launch approval request on version {launch.version}; ask again on this one.
		</p>
	{:else if launch?.status === 'approved'}
		<p>
			Version {launch.version} is approved for launch. Releasing marks that approval replaced, and you
			ask for approval again.
		</p>
	{/if}
</ConfirmDialog>

<ConfirmDialog
	open={confirmDiscard}
	title="Discard this draft?"
	confirmLabel="Discard draft"
	destructive
	loading={discard.isPending}
	onConfirm={() => discard.mutate()}
	onClose={() => (confirmDiscard = false)}
>
	<p>The cards you wrote are thrown away. Released versions stay as they are.</p>
</ConfirmDialog>

<style lang="scss">
	.setup-preview {
		&__start {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small) var(--space-base);
		}

		&__muted {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__editor {
			display: grid;
			gap: var(--space-base);
		}

		&__edit-card {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
		}

		&__edit-tools {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__tool-buttons {
			display: inline-flex;
			gap: var(--space-smallest);
		}

		&__tool {
			display: grid;
			place-items: center;
			width: 32px;
			height: 32px;
			padding: 0;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			color: var(--color-text--secondary);
			cursor: pointer;

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&:hover:not(:disabled) {
				background: var(--color-surface--hover);
				color: var(--color-text);
			}

			&:focus-visible {
				outline: 2px solid var(--color-interactive);
				outline-offset: 2px;
			}

			&:disabled {
				opacity: 0.4;
				cursor: not-allowed;
			}

			&--remove:hover:not(:disabled) {
				color: var(--color-critical);
			}
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__notice {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__released {
			display: grid;
			gap: var(--space-small);
			margin-top: var(--space-base);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);
		}

		&__version-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
		}

		&__version-head {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__cards {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__card {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__card-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
		}

		&__note {
			display: grid;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-base);
			border-left: 3px solid var(--color-warning);
			background: var(--color-surface--background);

			p {
				margin: 0;
				white-space: pre-line;
			}

			&--fine {
				border-left-color: var(--color-success);
			}
		}

		&__older {
			margin-top: var(--space-small);

			summary {
				color: var(--color-interactive);
				font-weight: 600;
				cursor: pointer;
			}

			&[open] summary {
				margin-bottom: var(--space-small);
			}
		}

		&__hidden {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			white-space: nowrap;
		}
	}
</style>
