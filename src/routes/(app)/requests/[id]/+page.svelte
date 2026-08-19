<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { untrack } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import AssessmentBlock from '$lib/components/requests/AssessmentBlock.svelte';
	import NotesPanel from '$lib/components/collaboration/NotesPanel.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import ActivityFeed from '$lib/components/collaboration/ActivityFeed.svelte';
	import {
		completeAssessment,
		fetchRequest,
		patchRequest,
		removeAssessment,
		requestCountsKey,
		requestDetailKey,
		saveAssessment,
		type AssessmentDraft
	} from '$lib/requests/api';
	import { REQUEST_STATUS_LABELS, REQUEST_STATUS_TONES } from '$lib/requests/statuses';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import {
		activityKey,
		createNote,
		deleteNote,
		notesKey,
		fetchActivity,
		fetchNotes,
		updateNote,
		type NoteChange
	} from '$lib/collaboration/api';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import clipboardIcon from '@tabler/icons/outline/clipboard-text.svg?raw';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import quoteIcon from '@tabler/icons/outline/file-invoice.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';

	const queryClient = useQueryClient();
	const requestId = $derived(page.params.id ?? '');
	const currentUserId = $derived(page.data.user?.id as string | undefined);

	const requestQuery = createQuery(() => ({
		queryKey: requestDetailKey(requestId),
		queryFn: () => fetchRequest(requestId),
		enabled: Boolean(requestId)
	}));
	const saved = $derived(requestQuery.data);

	// The rail card carries the count, so the panel inside it needs no heading of its own, and both read
	// the same key so they share one fetch.
	const notesQuery = createQuery(() => ({
		queryKey: notesKey('request', requestId),
		queryFn: () => fetchNotes('request', requestId),
		enabled: Boolean(requestId)
	}));

	// --- The draft ------------------------------------------------------------------------------------
	// A block's pencil turns it into an editor, and what is typed sits here until the bar at the bottom
	// writes it. The assessment is not in here: it is a record of its own and saves itself.

	// Each editable block carries a flag saying it is open and the text being typed. Keeping the two
	// apart means an edit that ends up matching what was already saved simply leaves the bar alone.
	let editingTitle = $state(false);
	let titleDraft = $state('');
	let editingOverview = $state(false);
	let descriptionDraft = $state('');
	let notePending = $state<NoteChange[]>([]);
	let attachmentsCard = $state<AttachmentsCard>();
	let pendingFileCount = $state(0);
	let saving = $state(false);
	let saveError = $state('');

	const titleChanged = $derived(editingTitle && titleDraft.trim() !== (saved?.title ?? ''));
	const overviewChanged = $derived(
		editingOverview && descriptionDraft.trim() !== (saved?.description ?? '')
	);

	// Two separate questions for the bar at the bottom. An open editor puts the page in edit mode even
	// before a word is typed, so Cancel is there to close it again; Save waits for a real change.
	const isEditing = $derived(
		editingTitle || editingOverview || notePending.length > 0 || pendingFileCount > 0
	);
	const isDirty = $derived(
		titleChanged || overviewChanged || notePending.length > 0 || pendingFileCount > 0
	);

	function discardDraft() {
		editingTitle = false;
		titleDraft = '';
		editingOverview = false;
		descriptionDraft = '';
		notePending = [];
		attachmentsCard?.discardChanges();
		saveError = '';
	}

	// A different request in the same page component starts clean. `untrack` keeps the clearing out of the
	// dependencies, or the attachments card's own reset would count as a change and loop.
	$effect(() => {
		const id = requestId;
		untrack(() => {
			if (id) discardDraft();
		});
	});

	const title = $derived(saved?.title ?? '');
	const description = $derived(saved?.description ?? '');

	async function saveDraft() {
		if (!saved || saving || !isDirty) return;
		saving = true;
		saveError = '';

		try {
			if (titleChanged || overviewChanged) {
				const patch: Record<string, unknown> = {};
				if (titleChanged) patch.title = titleDraft.trim();
				if (overviewChanged) patch.description = descriptionDraft.trim();
				await patchRequest(requestId, patch);
				editingTitle = false;
				titleDraft = '';
				editingOverview = false;
				descriptionDraft = '';
			}

			// Notes in the order they were staged, each dropped as it lands, so a failure halfway leaves
			// only the ones still to write.
			for (const change of [...notePending]) {
				if (change.kind === 'create')
					await createNote({ entityType: 'request', entityId: requestId, body: change.body });
				else if (change.kind === 'update')
					await updateNote({
						id: change.id,
						entityType: 'request',
						entityId: requestId,
						body: change.body
					});
				else if (change.kind === 'pin')
					await updateNote({
						id: change.id,
						entityType: 'request',
						entityId: requestId,
						pinned: change.pinned
					});
				else await deleteNote({ id: change.id, entityType: 'request', entityId: requestId });
				notePending = notePending.filter((entry) => entry !== change);
			}

			// Files last, and their failures are reported rather than thrown: everything above is already
			// saved, so a stuck upload must not read as the whole save failing.
			const failedFiles = (await attachmentsCard?.saveAll(requestId)) ?? 0;
			if (failedFiles > 0)
				saveError =
					failedFiles === 1
						? 'Everything else was saved, but one file did not upload. Try it again below.'
						: `Everything else was saved, but ${failedFiles} files did not upload. Try them again below.`;

			await refresh();
		} catch (error) {
			saveError = error instanceof Error ? error.message : 'Those changes could not be saved.';
		} finally {
			saving = false;
		}
	}

	// The list and its Overview card both read a request's status, so a change here has to reach them too.
	// So does the pipeline: a status or assessment change is exactly what moves a card between columns,
	// and the database works out which one, so the board has to re-read rather than guess.
	async function refresh() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: requestDetailKey(requestId) }),
			queryClient.invalidateQueries({ queryKey: ['requests', 'list'] }),
			queryClient.invalidateQueries({ queryKey: requestCountsKey }),
			queryClient.invalidateQueries({ queryKey: notesKey('request', requestId) }),
			queryClient.invalidateQueries({ queryKey: activityKey('request', requestId) }),
			invalidatePipeline(queryClient)
		]);
	}

	// --- The assessment -------------------------------------------------------------------------------

	let assessmentBlock = $state<AssessmentBlock>();
	let assessmentSaving = $state(false);
	let assessmentError = $state('');

	async function runAssessmentWrite(work: () => Promise<unknown>) {
		if (assessmentSaving) return;
		assessmentSaving = true;
		assessmentError = '';
		try {
			await work();
			await refresh();
		} catch (error) {
			assessmentError =
				error instanceof Error ? error.message : 'The visit could not be saved. Try again.';
		} finally {
			assessmentSaving = false;
		}
	}

	// --- The header -----------------------------------------------------------------------------------

	const status = $derived(saved?.status ?? 'new');

	const dateFormat = new Intl.DateTimeFormat('en-GB', {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const dateTimeFormat = new Intl.DateTimeFormat('en-GB', {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	});

	const assessmentFact = $derived.by(() => {
		const assessment = saved?.assessment;
		if (!assessment) return null;
		if (!assessment.starts_at) return 'Booked, no date yet';
		const start = new Date(assessment.starts_at);
		return assessment.all_day
			? `${dateFormat.format(start)}, anytime`
			: dateTimeFormat.format(start);
	});

	const headerFacts = $derived([
		{
			label: 'Requested',
			value: saved ? dateFormat.format(new Date(saved.created_at)) : null
		},
		{ label: 'Assessment', value: assessmentFact, empty: 'Not booked yet' },
		{ label: 'Service', value: saved?.service_type, empty: 'Not recorded' }
	]);

	const propertyLine = $derived.by(() => {
		const property = saved?.property;
		if (!property) return null;
		return [property.address_line1, property.city, property.state_region, property.postal_code]
			.filter(Boolean)
			.join(', ');
	});

	// Whatever moves this request forward next. Converting to a quote or a job is not built yet, so it is
	// offered honestly rather than hidden — the office can see where the request is heading.
	const primaryAction = $derived.by(() => {
		if (!saved) return undefined;
		if (saved.stored_status === 'archived') return undefined;
		if (!saved.assessment)
			return {
				label: 'Schedule assessment',
				onclick: () => assessmentBlock?.open(),
				onhover: () => assessmentBlock?.warm()
			};
		if (!saved.assessment.completed_at)
			return {
				label: 'Complete assessment',
				loading: assessmentSaving,
				onclick: () => void runAssessmentWrite(() => completeAssessment(requestId, true))
			};
		return { label: 'Convert to quote', disabled: true };
	});

	const menuItems = $derived([
		{
			label: 'Convert to quote',
			icon: quoteIcon,
			disabled: true,
			onSelect: () => {}
		},
		{
			label: 'Convert to job',
			icon: briefcaseIcon,
			disabled: true,
			onSelect: () => {}
		},
		{
			label: saved?.stored_status === 'archived' ? 'Bring back' : 'Archive',
			icon: archiveIcon,
			onSelect: () =>
				void runAssessmentWrite(() =>
					patchRequest(requestId, {
						status: saved?.stored_status === 'archived' ? 'new' : 'archived'
					})
				)
		}
	]);

	const clientMenuItems = $derived(
		saved?.client
			? [
					{
						label: 'View client profile',
						onSelect: () => void goto(resolve('/(app)/clients/[id]', { id: saved.client!.id }))
					}
				]
			: []
	);

	// --- The rail -------------------------------------------------------------------------------------

	// Jobber swaps the whole rail for the history panel rather than opening it beside the notes, so the
	// two never compete for the same column. Nothing about it loads with the page — hovering the button
	// starts the fetch, so the feed is usually already there by the time the click lands.
	let showHistory = $state(false);

	function warmHistory() {
		if (!requestId) return;
		void queryClient.prefetchQuery({
			queryKey: activityKey('request', requestId),
			queryFn: () => fetchActivity('request', requestId)
		});
	}
</script>

<PageContainer>
	{#if requestQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading request" />
	{:else if requestQuery.isError}
		<ErrorState description="That request could not be loaded. Refresh and try again." />
	{:else if saved}
		<RecordDetailLayout
			class="request-detail"
			editing={isEditing}
			dirty={isDirty}
			{saving}
			error={saveError}
			onSave={() => void saveDraft()}
			onCancel={discardDraft}
		>
			{#snippet main()}
				<WorkRecordHeader
					icon={fileTextIcon}
					recordType="Request"
					{title}
					statusLabel={REQUEST_STATUS_LABELS[status]}
					statusTone={REQUEST_STATUS_TONES[status]}
					{primaryAction}
					{menuItems}
					onHistory={() => (showHistory = !showHistory)}
					onHistoryHover={warmHistory}
					onEditTitle={() => {
						titleDraft = saved.title;
						editingTitle = true;
					}}
					{editingTitle}
					bind:titleDraft
				>
					{#snippet summary()}
						<ClientSummaryCard
							name={saved.client?.display_name ?? 'No client'}
							href={saved.client
								? resolve('/(app)/clients/[id]', { id: saved.client.id })
								: undefined}
							addresses={[{ value: propertyLine, empty: 'No property on this request' }]}
							phone={saved.phone}
							email={saved.email}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet facts()}
						<RecordFactsList facts={headerFacts} />
					{/snippet}
				</WorkRecordHeader>

				<SectionBlock
					title="Service overview"
					icon={clipboardIcon}
					level={2}
					form={editingOverview}
				>
					{#snippet actions()}
						{#if !editingOverview}
							<PencilButton
								onclick={() => {
									descriptionDraft = saved.description ?? '';
									editingOverview = true;
								}}
								label="Edit the service overview"
							/>
						{:else if overviewChanged}
							<Badge size="small" status="warning">Unsaved</Badge>
						{/if}
					{/snippet}

					{#if editingOverview}
						<Textarea
							id="request-description"
							label="Please provide as much information as you can"
							rows={6}
							bind:value={descriptionDraft}
						/>
					{:else if description}
						<p class="request-detail__overview">{description}</p>
					{:else}
						<EmptyState
							icon={clipboardIcon}
							title="Nothing written down yet"
							description="Say what the client is asking for, so whoever visits knows what they are looking at."
						/>
					{/if}
				</SectionBlock>

				<AssessmentBlock
					bind:this={assessmentBlock}
					assessment={saved.assessment}
					saving={assessmentSaving}
					error={assessmentError}
					onSave={(draft: AssessmentDraft) =>
						runAssessmentWrite(() => saveAssessment(requestId, draft))}
					onRemove={() => runAssessmentWrite(() => removeAssessment(requestId))}
					onComplete={(complete: boolean) =>
						runAssessmentWrite(() => completeAssessment(requestId, complete))}
				/>

				<SectionBlock title="Products and services" icon={listIcon} level={2}>
					<EmptyState
						icon={listIcon}
						title="Nothing priced yet"
						description="Line items land here once quoting is built. For now, price the work on the quote itself."
					/>
				</SectionBlock>

				<SectionBlock title="Labour" icon={clockIcon} level={2}>
					<EmptyState
						icon={clockIcon}
						title="No time tracked"
						description="Time your team logs against this request will show up here once timesheets are built."
					/>
				</SectionBlock>
			{/snippet}

			{#snippet rail()}
				{#if showHistory}
					<RailCard title="Request history" icon={clockIcon}>
						{#snippet actions()}
							<Button size="small" variant="tertiary" onclick={() => (showHistory = false)}>
								Close
							</Button>
						{/snippet}
						<ActivityFeed entityType="request" entityId={requestId} {currentUserId} />
					</RailCard>
				{:else}
					<RailCard title="Notes" icon={notesIcon} count={notesQuery.data?.length}>
						<NotesPanel
							entityType="request"
							entityId={requestId}
							canManage
							{currentUserId}
							pending={notePending}
							onChange={(next: NoteChange[]) => (notePending = next)}
						/>
					</RailCard>

					<AttachmentsCard
						bind:this={attachmentsCard}
						onPendingChange={(count: number) => (pendingFileCount = count)}
						entityType="request"
						entityId={requestId}
						{currentUserId}
					/>
				{/if}
			{/snippet}
		</RecordDetailLayout>
	{/if}
</PageContainer>

<style lang="scss">
	.request-detail {
		&__overview {
			margin: 0;
			color: var(--color-text);
			white-space: pre-wrap;
		}
	}
</style>
