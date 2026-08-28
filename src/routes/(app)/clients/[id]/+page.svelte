<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { untrack } from 'svelte';
	import { page } from '$app/state';
	import { replaceState } from '$app/navigation';
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
	import ClientDetailsDialog from '$lib/components/clients/ClientDetailsDialog.svelte';
	import PropertyDialog from '$lib/components/clients/PropertyDialog.svelte';
	import LeadSourceDialog from '$lib/components/clients/LeadSourceDialog.svelte';
	import ClientTagSelect from '$lib/components/clients/ClientTagSelect.svelte';
	import NotesPanel from '$lib/components/collaboration/NotesPanel.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import ClientCommunicationHistory from '$lib/components/communications/ClientCommunicationHistory.svelte';
	import {
		clientCommunicationHistoryKey,
		fetchClientCommunicationHistory,
		type InboxMessagePage
	} from '$lib/communications/inbox';
	import {
		ClientWriteError,
		clientDetailKey,
		fetchClient,
		saveClient,
		type ClientDetail,
		type ClientIdentityDraft,
		type ClientPreferences,
		type ClientProperty
	} from '$lib/clients/api';
	import { fetchTaxPicker, taxPickerKey } from '$lib/settings/api';
	import {
		activityKey,
		createNote,
		deleteNote,
		fetchNotes,
		fetchTagAssignments,
		notesKey,
		tagAssignmentsKey,
		updateNote,
		type NoteChange
	} from '$lib/collaboration/api';
	import homeIcon from '@tabler/icons/outline/home.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import targetIcon from '@tabler/icons/outline/target-arrow.svg?raw';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import checkIcon from '@tabler/icons/outline/circle-check.svg?raw';

	const queryClient = useQueryClient();
	const clientId = $derived(page.params.id ?? '');
	// A save on the create or edit form lands here, so the confirmation travels in the URL.
	const justSaved = $derived(page.url.searchParams.get('saved') !== null);
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

	// --- The draft ------------------------------------------------------------------------------------
	// A block's pencil opens a dialog, and Done puts the new values here rather than saving them. The page
	// then shows the draft, marks what changed, and the action bar writes it all in one go.

	const DEFAULT_PREFERENCES: ClientPreferences = {
		contact_policy: 'allow',
		quote_follow_ups: true,
		invoice_reminders: true,
		appointment_reminders: true,
		job_follow_ups: true,
		review_requests: true,
		marketing: false
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
			review_requests: flags.review_requests,
			marketing: flags.marketing
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

	// The same rule the server uses, so a staged name reads the way it will once it is saved.
	function displayNameOf(values: ClientIdentityDraft) {
		if (values.client_type === 'company') return values.company_name.trim();
		return [values.first_name, values.last_name]
			.map((part) => part.trim())
			.filter(Boolean)
			.join(' ');
	}

	let identityDraft = $state<ClientIdentityDraft | null>(null);
	let leadSourceDraft = $state<string | null>(null);
	let tagIdsDraft = $state<string[] | null>(null);
	let notePending = $state<NoteChange[]>([]);
	// Attachments keep their own staged files and deletes; the page only needs to know how many are waiting
	// so the bar lights up, and holds a handle so Save can tell the card to write them.
	let attachmentsCard = $state<AttachmentsCard>();
	let pendingFileCount = $state(0);
	let saving = $state(false);
	let saveError = $state('');
	// Set by a save made on this page, so the same confirmation strip serves both routes into it.
	let justSavedHere = $state(false);

	function discardDraft() {
		identityDraft = null;
		leadSourceDraft = null;
		tagIdsDraft = null;
		notePending = [];
		attachmentsCard?.discardChanges();
		saveError = '';
		justSavedHere = false;
	}

	// A different client in the same page component starts with a clean sheet. The client id is the only
	// thing this watches: `untrack` keeps the clearing itself out of the dependencies, or wiping the
	// attachments card's staged files would count as a change and set the whole thing running again.
	$effect(() => {
		const id = clientId;
		untrack(() => {
			if (id) discardDraft();
		});
	});

	// What the page renders: the saved client with anything staged laid over the top. Preferences are left
	// as saved on purpose — they carry opt-in timestamps the draft has no copy of, and a staged preference
	// change is read straight from the draft by the dialog that set it.
	const client = $derived.by(() => {
		if (!saved) return undefined;
		const identity = identityDraft ?? identityOf(saved);
		return {
			...saved,
			client_type: identity.client_type,
			lifecycle_status: identity.lifecycle_status,
			first_name: identity.first_name,
			last_name: identity.last_name,
			company_name: identity.company_name,
			email: identity.email,
			phone: identity.phone,
			display_name: displayNameOf(identity) || saved.display_name,
			lead_source: leadSourceDraft ?? saved.lead_source
		} satisfies ClientDetail;
	});

	const properties = $derived(saved?.properties ?? []);

	// Tags come from the assignments query rather than the client record, because that is the list the tag
	// card itself reads and writes. A staged pick sits on top of it until the bar saves.
	const savedTagIds = $derived((tagsQuery.data ?? []).map((assignment) => assignment.tag_id));
	const tagIds = $derived(tagIdsDraft ?? savedTagIds);

	// --- What is open, and what really changed ----------------------------------------------------------
	// Two different questions, and the action bar needs both. A staged value means a block is open for
	// editing, so the bar appears with a way out of it. It only counts as a change when it differs from what
	// is saved — pressing Done in a dialog without touching anything must not offer to save.
	//
	// Properties are in neither list on purpose: `PropertyDialog` owns them and saves itself, so they never
	// enter the page draft or light up the action bar.

	function samePreferences(a: ClientPreferences, b: ClientPreferences) {
		return (Object.keys(DEFAULT_PREFERENCES) as (keyof ClientPreferences)[]).every(
			(key) => a[key] === b[key]
		);
	}

	function sameIdentity(a: ClientIdentityDraft, b: ClientIdentityDraft) {
		return (
			a.client_type === b.client_type &&
			a.lifecycle_status === b.lifecycle_status &&
			a.first_name.trim() === b.first_name.trim() &&
			a.last_name.trim() === b.last_name.trim() &&
			a.company_name.trim() === b.company_name.trim() &&
			a.email.trim() === b.email.trim() &&
			a.phone.trim() === b.phone.trim() &&
			samePreferences(a.preferences, b.preferences)
		);
	}

	// The order tags were picked in means nothing, so only the set counts.
	function sameTags(a: string[], b: string[]) {
		return a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');
	}

	const identityChanged = $derived(
		Boolean(saved && identityDraft && !sameIdentity(identityDraft, identityOf(saved)))
	);
	const leadSourceChanged = $derived(
		leadSourceDraft !== null && leadSourceDraft.trim() !== (saved?.lead_source ?? '').trim()
	);
	const tagsChanged = $derived(tagIdsDraft !== null && !sameTags(tagIdsDraft, savedTagIds));

	const isEditing = $derived(
		identityDraft !== null ||
			leadSourceDraft !== null ||
			tagIdsDraft !== null ||
			notePending.length > 0 ||
			pendingFileCount > 0
	);
	const isDirty = $derived(
		identityChanged ||
			leadSourceChanged ||
			tagsChanged ||
			notePending.length > 0 ||
			pendingFileCount > 0
	);

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

			if (identityChanged || leadSourceChanged || tagsChanged) {
				const identity = identityDraft ?? identityOf(fresh);
				await saveClient(
					{
						...identity,
						lead_source: leadSourceDraft ?? fresh.lead_source ?? '',
						preferences: identityDraft?.preferences ?? preferencesOf(fresh),
						tag_ids: tagIdsDraft ?? fresh.tag_ids ?? []
					},
					clientId
				);
				identityDraft = null;
				leadSourceDraft = null;
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

			// Files last, and their failures are reported rather than thrown: everything above is already
			// saved, so a stuck upload must not read as the whole save failing.
			const failedFiles = (await attachmentsCard?.saveAll(clientId)) ?? 0;
			if (failedFiles > 0)
				saveError =
					failedFiles === 1
						? 'Everything else was saved, but one file did not upload. Try it again below.'
						: `Everything else was saved, but ${failedFiles} files did not upload. Try them again below.`;

			await Promise.all([
				queryClient.invalidateQueries({ queryKey: clientDetailKey(clientId) }),
				queryClient.invalidateQueries({ queryKey: ['clients', 'list'] }),
				queryClient.invalidateQueries({ queryKey: tagAssignmentsKey('client', clientId) }),
				queryClient.invalidateQueries({ queryKey: activityKey('client', clientId) }),
				queryClient.invalidateQueries({ queryKey: notesKey('client', clientId) })
			]);
			justSavedHere = true;
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

	const clientTabs: Tab[] = [
		{ value: 'details', label: 'Details' },
		{ value: 'communication', label: 'Communication', onhover: prefetchCommunicationHistory }
	];

	// The open tab lives in the URL the way Jobber's does, so it survives a reload and can be linked to.
	// Details is the default and carries no parameter; anything unrecognised falls back to it.
	const activeTab = $derived.by(() => {
		const asked = page.url.searchParams.get('tab');
		return clientTabs.some((tab) => tab.value === asked) ? (asked as string) : 'details';
	});

	function selectTab(next: string) {
		const url = new URL(page.url);
		if (next === 'details') url.searchParams.delete('tab');
		else url.searchParams.set('tab', next);
		// Replaced, not pushed, so Back leaves the client instead of stepping back through tabs.
		replaceState(url, page.state);
	}

	// --- Dialogs --------------------------------------------------------------------------------------

	let detailsOpen = $state(false);
	let leadSourceOpen = $state(false);
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
	{#if (justSaved || justSavedHere) && client && !isEditing}
		<p class="client-detail__saved" role="status">
			<span aria-hidden="true">{@html checkIcon}</span>{client.display_name} was saved.
		</p>
	{/if}

	{#if clientQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading client" />
	{:else if clientQuery.isError}
		<ErrorState description="That client could not be loaded. Refresh and try again." />
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
				<ClientDetailHeader {client} onEdit={() => (detailsOpen = true)} />
				{#if identityChanged}
					<p class="client-detail__pending">
						Client details changed. Save at the bottom of the page to keep them.
					</p>
				{/if}

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

					<TabPanel value="communication">
						<ClientCommunicationHistory {clientId} active={activeTab === 'communication'} />
					</TabPanel>
				</Tabs>
			{/snippet}

			{#snippet rail()}
				<RailCard title="Lead source" icon={targetIcon}>
					{#snippet actions()}
						<PencilButton onclick={() => (leadSourceOpen = true)} label="Edit lead source" />
					{/snippet}
					{#if client.lead_source}
						<p class="client-detail__lead-source">
							{client.lead_source}
							{#if leadSourceChanged}
								<Badge size="small" status="warning">Unsaved</Badge>
							{/if}
						</p>
					{:else}
						<p class="client-detail__rail-blank">
							Not recorded yet. Add it so you know what brings work in.
						</p>
					{/if}
				</RailCard>

				<RailCard title="Tags" count={tagIds.length}>
					{#snippet actions()}
						{#if tagsChanged}<Badge size="small" status="warning">Unsaved</Badge>{/if}
					{/snippet}
					<ClientTagSelect {tagIds} onChange={(next) => (tagIdsDraft = next)} />
				</RailCard>

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

				<AttachmentsCard
					bind:this={attachmentsCard}
					onPendingChange={(count) => (pendingFileCount = count)}
					entityType="client"
					entityId={clientId}
					{currentUserId}
				/>
			{/snippet}
		</RecordDetailLayout>

		<!-- Each dialog is mounted only while it is open, so it always starts from what the page holds now. -->
		{#if detailsOpen}
			<ClientDetailsDialog
				open={detailsOpen}
				values={identityDraft ?? identityOf(client)}
				wasCustomer={saved?.lifecycle_status === 'customer'}
				onDone={(next) => {
					identityDraft = next;
					detailsOpen = false;
				}}
				onClose={() => (detailsOpen = false)}
			/>
		{/if}

		{#if leadSourceOpen}
			<LeadSourceDialog
				open={leadSourceOpen}
				value={client.lead_source ?? ''}
				onDone={(next) => {
					leadSourceDraft = next;
					leadSourceOpen = false;
				}}
				onClose={() => (leadSourceOpen = false)}
			/>
		{/if}

		{#if propertyDialog}
			<PropertyDialog
				open
				{clientId}
				property={propertyDialog.property}
				onSaved={() => void refreshProperties()}
				onClose={() => (propertyDialog = null)}
			/>
		{/if}
	{/if}
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.client-detail__saved {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin-bottom: var(--space-base);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		color: var(--color-success--onSurface);
		background: var(--color-success--surface);
		font-size: var(--typography--fontSize-small);

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

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

		// Says the header is showing something not yet written, right where the changed values are.
		&__pending {
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
