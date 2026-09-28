<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { untrack } from 'svelte';
	import { page } from '$app/state';
	import { urlParam } from '$lib/url-param.svelte';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import DataTable, { type DataTableColumn } from '$lib/components/data-display/DataTable.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Tabs, { type Tab } from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import ClientDetailHeader from '$lib/components/clients/ClientDetailHeader.svelte';
	import ClientDetailsForm from '$lib/components/clients/ClientDetailsForm.svelte';
	import MarketingConsentDialog from '$lib/components/clients/MarketingConsentDialog.svelte';
	import PropertyDialog from '$lib/components/clients/PropertyDialog.svelte';
	import LeadSourceEditor from '$lib/components/clients/LeadSourceEditor.svelte';
	import ClientTagSelect from '$lib/components/clients/ClientTagSelect.svelte';
	import NotesPanel from '$lib/components/collaboration/NotesPanel.svelte';
	import RecordFilesCard from '$lib/components/files/RecordFilesCard.svelte';
	import ClientCommunicationHistory from '$lib/components/communications/ClientCommunicationHistory.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		clientCommunicationHistoryKey,
		clientLastCommunicationKey,
		communicationsAccessKey,
		fetchClientCommunicationHistory,
		fetchCommunicationsAccess,
		type CommunicationsAccess,
		type InboxMessagePage
	} from '$lib/communications/inbox';
	import { exactTime } from '$lib/collaboration/format';
	import {
		ClientWriteError,
		clientDetailKey,
		fetchClient,
		type ClientReadError,
		saveClient,
		type ClientDetail,
		type ClientIdentityDraft,
		type ClientPreferences,
		type ClientProperty,
		type MarketingConsentState
	} from '$lib/clients/api';
	import { fetchTaxPicker, taxPickerKey } from '$lib/settings/api';
	import {
		activityKey,
		createNote,
		deleteNote,
		fetchActivity,
		fetchNotes,
		fetchTagAssignments,
		notesKey,
		tagAssignmentsKey,
		updateNote,
		type NoteChange
	} from '$lib/collaboration/api';
	import ActivityFeed from '$lib/components/collaboration/ActivityFeed.svelte';
	import homeIcon from '@tabler/icons/outline/home.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import targetIcon from '@tabler/icons/outline/target-arrow.svg?raw';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import messageIcon from '@tabler/icons/outline/message-circle.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const clientId = $derived(page.params.id ?? '');
	const currentUserId = $derived(page.data.user?.id as string | undefined);

	const clientQuery = createQuery(() => ({
		queryKey: clientDetailKey(clientId),
		queryFn: () => fetchClient(clientId),
		enabled: Boolean(clientId)
	}));

	// Each rail card carries its own count, so the panel inside it needs no heading of its own. Both use the
	// same keys as those panels, so they share the cache instead of fetching twice.
	const notesQuery = createQuery(() => ({
		queryKey: notesKey('client', clientId),
		queryFn: () => fetchNotes('client', clientId),
		enabled: Boolean(clientId)
	}));
	const notesCount = $derived(notesQuery.data?.length);

	const tagsQuery = createQuery(() => ({
		queryKey: tagAssignmentsKey('client', clientId),
		queryFn: () => fetchTagAssignments('client', clientId),
		enabled: Boolean(clientId)
	}));

	const saved = $derived(clientQuery.data);

	// --- Editing ------------------------------------------------------------------------------------
	// Jobber's three edit patterns (jobber-08-screen-patterns.md § How WE compare). The client's own details
	// and lead source edit in place and their own Save writes there and then. The bottom bar only carries
	// what has no block of its own: tags and notes. The full edit page opens from the header's ... menu.

	const DEFAULT_PREFERENCES: ClientPreferences = {
		contact_policy: 'allow',
		quote_follow_ups: true,
		invoice_reminders: true,
		appointment_reminders: true,
		job_follow_ups: true,
		review_requests: true
	};

	function preferencesOf(source: ClientDetail): ClientPreferences {
		if (!source.preferences) return { ...DEFAULT_PREFERENCES };
		const { contact_policy, ...flags } = source.preferences;
		return {
			contact_policy,
			quote_follow_ups: flags.quote_follow_ups,
			invoice_reminders: flags.invoice_reminders,
			appointment_reminders: flags.appointment_reminders,
			job_follow_ups: flags.job_follow_ups,
			review_requests: flags.review_requests
		};
	}

	function identityOf(source: ClientDetail): ClientIdentityDraft {
		return {
			client_type: source.client_type,
			lifecycle_status: source.lifecycle_status,
			first_name: source.first_name ?? '',
			last_name: source.last_name ?? '',
			company_name: source.company_name ?? '',
			email: source.email ?? '',
			phone: source.phone ?? '',
			preferences: preferencesOf(source)
		};
	}

	// Which block is open in place, if any, and how its own save is going.
	let editingBlock = $state<'details' | 'lead_source' | null>(null);
	let blockSaving = $state(false);
	let blockError = $state('');
	let blockFieldErrors = $state<Record<string, string>>({});

	function openBlock(block: 'details' | 'lead_source') {
		editingBlock = block;
		blockError = '';
		blockFieldErrors = {};
	}

	function closeBlock() {
		editingBlock = null;
		blockError = '';
		blockFieldErrors = {};
	}

	// A block's Save. The payload is rebuilt on a fresh read of the client, so it only ever changes the
	// fields this block owns — a tag staged in the bar, or a preference changed elsewhere, is left alone.
	async function saveBlock(change: Partial<ClientIdentityDraft> & { lead_source?: string }) {
		if (blockSaving) return;
		blockSaving = true;
		blockError = '';
		blockFieldErrors = {};
		try {
			const fresh = await queryClient.fetchQuery({
				queryKey: clientDetailKey(clientId),
				queryFn: () => fetchClient(clientId),
				staleTime: 0
			});
			await saveClient(
				{
					...identityOf(fresh),
					lead_source: fresh.lead_source ?? '',
					tag_ids: fresh.tag_ids ?? [],
					...change
				},
				clientId
			);
			await Promise.all([
				queryClient.invalidateQueries({ queryKey: clientDetailKey(clientId) }),
				queryClient.invalidateQueries({ queryKey: ['clients', 'list'] }),
				queryClient.invalidateQueries({ queryKey: activityKey('client', clientId) })
			]);
			toast.success(editingBlock === 'lead_source' ? 'Lead source saved' : 'Client details saved');
			closeBlock();
		} catch (error) {
			if (error instanceof ClientWriteError) blockFieldErrors = error.fieldErrors;
			blockError = error instanceof Error ? error.message : 'That could not be saved.';
		} finally {
			blockSaving = false;
		}
	}

	// --- The bar's draft ------------------------------------------------------------------------------
	// Tags and notes stage here and the bottom bar writes them together.

	let tagIdsDraft = $state<string[] | null>(null);
	let notePending = $state<NoteChange[]>([]);
	// Files are not in the page draft. Adding one happens inside the picker dialog, which carries its own
	// button, and removing one is confirmed in its own dialog, so the page's save bar has nothing to wait
	// for — the same way a property dialog saves itself.
	let saving = $state(false);
	let saveError = $state('');

	function discardDraft() {
		tagIdsDraft = null;
		notePending = [];
		saveError = '';
	}

	// A different client in the same page component starts with a clean sheet. The client id is the only
	// thing this watches: `untrack` keeps the clearing itself out of the dependencies, or the clearing
	// would count as a change and set the whole thing running again.
	$effect(() => {
		const id = clientId;
		untrack(() => {
			if (!id) return;
			discardDraft();
			closeBlock();
		});
	});

	const client = $derived(saved);

	const properties = $derived(saved?.properties ?? []);

	// Tags come from the assignments query rather than the client record, because that is the list the tag
	// card itself reads and writes. A staged pick sits on top of it until the bar saves.
	const savedTagIds = $derived((tagsQuery.data ?? []).map((assignment) => assignment.tag_id));
	const tagIds = $derived(tagIdsDraft ?? savedTagIds);

	// --- What is open, and what really changed ----------------------------------------------------------
	// Two different questions, and the action bar needs both. A staged value means the bar has something
	// open, so it appears with a way out. It only counts as a change when it differs from what is saved.
	//
	// Properties, details and lead source are in neither list on purpose: each saves itself.

	// The order tags were picked in means nothing, so only the set counts.
	function sameTags(a: string[], b: string[]) {
		return a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');
	}

	const tagsChanged = $derived(tagIdsDraft !== null && !sameTags(tagIdsDraft, savedTagIds));

	const isEditing = $derived(tagIdsDraft !== null || notePending.length > 0);
	const isDirty = $derived(tagsChanged || notePending.length > 0);

	// --- Saving ---------------------------------------------------------------------------------------

	async function saveDraft() {
		if (!saved || saving || !isDirty) return;
		saving = true;
		saveError = '';

		try {
			// Tags save the moment they are clicked, and preferences can be changed elsewhere, so the payload
			// is built on a fresh copy of the client. Sending a stale tag list would silently undo a tag.
			const fresh = await queryClient.fetchQuery({
				queryKey: clientDetailKey(clientId),
				queryFn: () => fetchClient(clientId),
				staleTime: 0
			});

			if (tagsChanged && tagIdsDraft) {
				await saveClient(
					{
						...identityOf(fresh),
						lead_source: fresh.lead_source ?? '',
						tag_ids: tagIdsDraft
					},
					clientId
				);
				tagIdsDraft = null;
			}

			// Notes, in the order they were staged, each dropped as it lands so a failure halfway leaves only
			// the ones still to write.
			for (const change of [...notePending]) {
				if (change.kind === 'create')
					await createNote({ entityType: 'client', entityId: clientId, body: change.body });
				else if (change.kind === 'update')
					await updateNote({
						id: change.id,
						entityType: 'client',
						entityId: clientId,
						body: change.body
					});
				else if (change.kind === 'pin')
					await updateNote({
						id: change.id,
						entityType: 'client',
						entityId: clientId,
						pinned: change.pinned
					});
				else await deleteNote({ id: change.id, entityType: 'client', entityId: clientId });
				notePending = notePending.filter((entry) => entry !== change);
			}

			toast.success('Client saved');

			await Promise.all([
				queryClient.invalidateQueries({ queryKey: clientDetailKey(clientId) }),
				queryClient.invalidateQueries({ queryKey: ['clients', 'list'] }),
				queryClient.invalidateQueries({ queryKey: tagAssignmentsKey('client', clientId) }),
				queryClient.invalidateQueries({ queryKey: activityKey('client', clientId) }),
				queryClient.invalidateQueries({ queryKey: notesKey('client', clientId) })
			]);
		} catch (error) {
			saveError =
				error instanceof ClientWriteError || error instanceof Error
					? error.message
					: 'Those changes could not be saved.';
		} finally {
			saving = false;
		}
	}

	// --- Tabs -----------------------------------------------------------------------------------------

	// Warms the tab's query before it opens (CLAUDE.md rule 9): fires on hover and keyboard focus via
	// `Tab.onhover`, using the exact key/queryFn/getNextPageParam shape `ClientCommunicationHistory` itself
	// queries with, so the click that follows finds the cache already warm.
	function prefetchCommunicationHistory() {
		void queryClient.prefetchInfiniteQuery({
			queryKey: clientCommunicationHistoryKey(clientId),
			queryFn: ({ pageParam }: { pageParam: string | undefined }) =>
				fetchClientCommunicationHistory(clientId, pageParam),
			initialPageParam: undefined as string | undefined,
			getNextPageParam: (lastPage: InboxMessagePage) => lastPage.next_cursor ?? undefined
		});
	}

	// Only a member who may see conversations gets the Communication tab, and only one who may send gets the
	// header's Message button; the shell's Inbox link asks the same question under the same key, so this is
	// normally already cached.
	const communicationsAccessQuery = createQuery<CommunicationsAccess>(() => ({
		queryKey: communicationsAccessKey(currentUserId ?? null),
		queryFn: fetchCommunicationsAccess,
		staleTime: 5 * 60_000
	}));
	const canSeeCommunication = $derived(communicationsAccessQuery.data?.ok ?? true);
	const canMessage = $derived(communicationsAccessQuery.data?.canSend ?? true);

	// The rail's own small read: just the newest message, so the card is there the moment the page is
	// (Jobber's own client rail carries this under Tags), independent of the Communication tab's lazy,
	// hover-warmed infinite history.
	const lastCommunicationQuery = createQuery<InboxMessagePage>(() => ({
		queryKey: clientLastCommunicationKey(clientId),
		queryFn: () => fetchClientCommunicationHistory(clientId),
		enabled: canSeeCommunication,
		staleTime: 15_000
	}));
	const lastCommunication = $derived(lastCommunicationQuery.data?.messages[0] ?? null);

	const clientTabs: Tab[] = $derived([
		{ value: 'details', label: 'Details' },
		...(canSeeCommunication
			? [{ value: 'communication', label: 'Communication', onhover: prefetchCommunicationHistory }]
			: [])
	]);

	// The open tab lives in the URL the way Jobber's does, so it survives a reload and can be linked to.
	// Details is the default and carries no parameter; anything unrecognised falls back to it.
	const tabParam = urlParam('tab', 'details');
	const activeTab = $derived(
		clientTabs.some((tab) => tab.value === tabParam.current) ? tabParam.current : 'details'
	);
	const selectTab = tabParam.set;

	// --- History ----------------------------------------------------------------------------------------
	// The same panel the work records use: it swaps the whole rail rather than opening beside the notes, and
	// nothing about it loads with the page -- hovering the button starts the fetch, so the feed is usually
	// already there by the time the click lands. A client's review milestones reach it through the shared
	// activity feed the `review_requests` trigger writes.
	let showHistory = $state(false);

	function warmHistory() {
		if (!clientId) return;
		void queryClient.prefetchQuery({
			queryKey: activityKey('client', clientId),
			queryFn: () => fetchActivity('client', clientId)
		});
	}

	// --- Dialogs --------------------------------------------------------------------------------------

	let marketingConsentOpen = $state(false);

	// Consent is never staged with the rest of a client edit — it is dated evidence — so it reads straight
	// from the saved client, and recording it writes on its own and refreshes.
	const marketingConsent = $derived<MarketingConsentState | null>(
		client?.marketing_consent ?? null
	);
	// Recording a real preference is an owner/admin job. Field/office roles still see the state, read-only.
	const role = $derived((page.data.account as { role?: string } | undefined)?.role);
	const canRecordConsent = $derived(role === 'owner' || role === 'admin');

	const consentDateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});

	function consentSourceLabel(source: MarketingConsentState['source']) {
		switch (source) {
			case 'public_form':
				return 'signup form';
			case 'staff':
				return 'your team';
			case 'unsubscribe':
				return 'unsubscribe link';
			case 'complaint':
				return 'a spam complaint';
			default:
				return null;
		}
	}

	async function refreshMarketingConsent() {
		marketingConsentOpen = false;
		await queryClient.invalidateQueries({ queryKey: clientDetailKey(clientId) });
		toast.success('Marketing consent recorded');
	}
	// Null while closed. Adding opens the same dialog with no property behind it.
	let propertyDialog = $state<{ property: ClientProperty | null } | null>(null);

	function warmPropertyTaxPicker() {
		void queryClient.prefetchQuery({
			queryKey: taxPickerKey(),
			queryFn: () => fetchTaxPicker()
		});
	}

	// The dialog writes for itself, so all the page owes it afterwards is a refresh of anything that shows an
	// address. The list carries each client's primary property and a count of the rest.
	async function refreshProperties() {
		propertyDialog = null;
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: clientDetailKey(clientId) }),
			queryClient.invalidateQueries({ queryKey: ['clients', 'list'] })
		]);
	}

	const propertyColumns: DataTableColumn[] = [
		{ key: 'street', label: 'Street' },
		{ key: 'city', label: 'City' },
		{ key: 'state', label: 'State' },
		{ key: 'zip', label: 'Zip' }
	];

	// The line under a street tells the office which property this is. One saved without a name falls back
	// to what it is used for.
	function propertyCaption(property: ClientProperty) {
		if (property.label) return property.label;
		if (property.is_billing_address) return 'Billing address';
		return property.is_primary ? 'Main property' : 'Property';
	}
	function streetOf(property: ClientProperty) {
		return [property.address_line1, property.address_line2].filter(Boolean).join(', ');
	}
</script>

<svelte:head>
	<title>{client?.display_name ?? 'Client'} · Contractor CRM</title>
</svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="fill">
	{#if clientQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading client" />
	{:else if (clientQuery.error as ClientReadError | null)?.status === 403}
		<EmptyState
			icon={lockIcon}
			title="You do not have access to this client"
			description="You can open a client once one of their visits is assigned to you. Ask an owner or admin if you need it sooner."
		/>
	{:else if (clientQuery.error as ClientReadError | null)?.status === 404}
		<EmptyState
			title="This client could not be found"
			description="It may have been deleted, or the link is out of date."
		/>
	{:else if clientQuery.isError}
		<ErrorState
			description="That client could not be loaded. Try again."
			retry={() => clientQuery.refetch()}
		/>
	{:else if client}
		<RecordDetailLayout
			class="client-detail"
			editing={isEditing}
			dirty={isDirty}
			{saving}
			error={saveError}
			onSave={() => void saveDraft()}
			onCancel={discardDraft}
		>
			{#snippet main()}
				<ClientDetailHeader
					{client}
					{canMessage}
					onEdit={() => openBlock('details')}
					editing={editingBlock === 'details'}
					onHistory={() => (showHistory = !showHistory)}
					onHistoryHover={warmHistory}
				>
					{#snippet editor()}
						<ClientDetailsForm
							values={identityOf(client)}
							wasCustomer={client.lifecycle_status === 'customer'}
							saving={blockSaving}
							error={blockError}
							fieldErrors={blockFieldErrors}
							onSave={(next) => void saveBlock(next)}
							onCancel={closeBlock}
						/>
					{/snippet}
				</ClientDetailHeader>

				<Tabs tabs={clientTabs} value={activeTab} onChange={selectTab} label="Client sections">
					<TabPanel value="details">
						<SectionBlock title="Properties" icon={homeIcon} level={2}>
							{#snippet actions()}
								<Button
									size="small"
									variant="tertiary"
									onclick={() => (propertyDialog = { property: null })}
									onhover={warmPropertyTaxPicker}
								>
									Add property
								</Button>
							{/snippet}
							{#if properties.length === 0}
								<EmptyState
									icon={homeIcon}
									title="No properties yet"
									description="Add where the work happens and it will show up here."
								/>
							{:else}
								<DataTable
									columns={propertyColumns}
									items={properties}
									rowId={(property) => property.id}
									caption="Properties"
								>
									{#snippet row(property: ClientProperty)}
										<th scope="row">
											<span class="client-detail__street">{streetOf(property)}</span>
											<span class="client-detail__street-caption">
												{propertyCaption(property)}
												{#if property.is_primary}<Badge size="small">Main</Badge>{/if}
											</span>
										</th>
										<td>{property.city}</td>
										<td>{property.state_region ?? '—'}</td>
										<td>{property.postal_code ?? '—'}</td>
									{/snippet}
									{#snippet rowActions(property: ClientProperty)}
										<PencilButton
											onclick={() => (propertyDialog = { property })}
											onhover={warmPropertyTaxPicker}
											label={`Edit ${streetOf(property)}`}
										/>
									{/snippet}
								</DataTable>
							{/if}
						</SectionBlock>

						<SectionBlock title="Work overview" icon={briefcaseIcon} level={2}>
							<EmptyState
								icon={briefcaseIcon}
								title="No work yet"
								description="Requests, quotes, jobs, and invoices for this client will all be listed here once you start creating them."
							/>
						</SectionBlock>

						<SectionBlock title="Client schedule" icon={calendarIcon} level={2}>
							<EmptyState
								icon={calendarIcon}
								title="Nothing booked"
								description="Visits and reminders for this client will show up here once jobs are being scheduled."
							/>
						</SectionBlock>
					</TabPanel>

					{#if canSeeCommunication}
						<TabPanel value="communication">
							<ClientCommunicationHistory {clientId} active={activeTab === 'communication'} />
						</TabPanel>
					{/if}
				</Tabs>
			{/snippet}

			{#snippet rail()}
				{#if showHistory}
					<RailCard title="Client history" icon={clockIcon}>
						{#snippet actions()}
							<Button size="small" variant="tertiary" onclick={() => (showHistory = false)}>
								Close
							</Button>
						{/snippet}
						<ActivityFeed entityType="client" entityId={clientId} {currentUserId} />
					</RailCard>
				{:else}
					<RailCard title="Lead source" icon={targetIcon}>
						{#snippet actions()}
							{#if editingBlock !== 'lead_source'}
								<PencilButton onclick={() => openBlock('lead_source')} label="Edit lead source" />
							{/if}
						{/snippet}
						{#if editingBlock === 'lead_source'}
							<LeadSourceEditor
								value={client.lead_source ?? ''}
								saving={blockSaving}
								error={blockError}
								onSave={(next) => void saveBlock({ lead_source: next })}
								onCancel={closeBlock}
							/>
						{:else if client.lead_source}
							<p class="client-detail__lead-source">
								{client.lead_source}
							</p>
						{:else}
							<p class="client-detail__rail-blank">
								Not recorded yet. Add it so you know what brings work in.
							</p>
						{/if}
					</RailCard>

					<RailCard title="Marketing email" icon={mailIcon}>
						{#snippet actions()}
							{#if canRecordConsent && marketingConsent}
								<Button
									size="small"
									variant="tertiary"
									onclick={() => (marketingConsentOpen = true)}
								>
									Record
								</Button>
							{/if}
						{/snippet}
						{#if !marketingConsent}
							<p class="client-detail__rail-blank">
								Add an email address to record marketing consent.
							</p>
						{:else}
							<p class="client-detail__consent">
								{#if marketingConsent.state === 'opted_in'}
									<Badge status="success">Opted in</Badge>
								{:else if marketingConsent.state === 'opted_out'}
									<Badge status="critical">Opted out</Badge>
								{:else}
									<Badge status="informative">Not recorded</Badge>
								{/if}
							</p>
							{#if marketingConsent.effective_at}
								<p class="client-detail__rail-caption">
									{consentDateFormat.format(
										new Date(marketingConsent.effective_at)
									)}{#if consentSourceLabel(marketingConsent.source)}
										· via {consentSourceLabel(marketingConsent.source)}{/if}
								</p>
							{:else}
								<p class="client-detail__rail-caption">No opt-in or opt-out recorded yet.</p>
							{/if}
						{/if}
					</RailCard>

					<RailCard title="Tags" count={tagIds.length}>
						{#snippet actions()}
							{#if tagsChanged}<Badge size="small" status="warning">Unsaved</Badge>{/if}
						{/snippet}
						<ClientTagSelect {tagIds} onChange={(next) => (tagIdsDraft = next)} />
					</RailCard>

					{#if canSeeCommunication}
						<RailCard title="Last communication" icon={messageIcon}>
							{#if lastCommunicationQuery.isPending}
								<LoadingSkeleton variant="text" />
							{:else if lastCommunication}
								<p class="client-detail__rail-caption">
									{exactTime(lastCommunication.created_at)}
								</p>
								<p class="client-detail__last-communication-subject">
									{lastCommunication.subject}
								</p>
								<Button size="small" variant="tertiary" onclick={() => selectTab('communication')}>
									Read more...
								</Button>
							{:else}
								<p class="client-detail__rail-blank">Nothing sent yet.</p>
							{/if}
						</RailCard>
					{/if}

					<RailCard title="Notes" icon={notesIcon} count={notesCount}>
						<NotesPanel
							entityType="client"
							entityId={clientId}
							canManage
							{currentUserId}
							pending={notePending}
							onChange={(next) => (notePending = next)}
						/>
					</RailCard>

					<RecordFilesCard
						entityType="client"
						entityId={clientId}
						recordLabel="this client"
						pickerLabel="On this client"
					/>
				{/if}
			{/snippet}
		</RecordDetailLayout>

		<!-- Each dialog is mounted only while it is open, so it always starts from what the page holds now. -->
		{#if marketingConsentOpen && marketingConsent}
			<MarketingConsentDialog
				open={marketingConsentOpen}
				{clientId}
				consent={marketingConsent}
				onSaved={() => void refreshMarketingConsent()}
				onClose={() => (marketingConsentOpen = false)}
			/>
		{/if}

		{#if propertyDialog}
			<PropertyDialog
				open
				{clientId}
				clientLabel={client.display_name}
				property={propertyDialog.property}
				onSaved={() => void refreshProperties()}
				onClose={() => (propertyDialog = null)}
			/>
		{/if}
	{/if}
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The grid, the main card, and the rail all live in RecordDetailLayout now. What is left here is only
	// what this page's own content needs.
	.client-detail {
		&__street {
			display: block;
			color: var(--color-heading);
			font-weight: 700;
		}

		&__street-caption {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
		}

		&__lead-source {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-heading);
			font-weight: 600;
		}

		&__rail-blank {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__consent {
			display: flex;
			align-items: center;
			gap: var(--space-small);
		}

		&__rail-caption {
			margin-top: var(--space-slim);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__last-communication-subject {
			color: var(--color-heading);
			font-weight: 600;
			overflow: hidden;
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}
</style>
