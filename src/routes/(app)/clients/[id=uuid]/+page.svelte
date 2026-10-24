<script lang="ts">
	import historyCardIcon from '@tabler/icons/outline/history.svg?raw';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { untrack } from 'svelte';
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
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
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import MoneyFeatureCard from '$lib/components/work/MoneyFeatureCard.svelte';
	import Tabs, { type Tab } from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ManualEmailDialog from '$lib/components/clients/ManualEmailDialog.svelte';
	import RequestReviewButton from '$lib/components/reviews/RequestReviewButton.svelte';
	import type { RecordFact } from '$lib/components/work/types';
	import ClientDetailsForm from '$lib/components/clients/ClientDetailsForm.svelte';
	import ClientWorkOverview from '$lib/components/clients/ClientWorkOverview.svelte';
	import ClientSchedule from '$lib/components/clients/ClientSchedule.svelte';
	import ClientMergeDialog from '$lib/components/clients/ClientMergeDialog.svelte';
	import ClientDeleteDialog from '$lib/components/clients/ClientDeleteDialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
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
		setClientsArchived,
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
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import arrowRightIcon from '@tabler/icons/outline/arrow-right.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash-banknote.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import calendarTimeIcon from '@tabler/icons/outline/calendar-time.svg?raw';
	import speakerphoneIcon from '@tabler/icons/outline/speakerphone.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import mergeIcon from '@tabler/icons/outline/arrow-merge.svg?raw';
	import deleteIcon from '@tabler/icons/outline/trash.svg?raw';

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

	// A client merged into another no longer exists; an old link to it opens the client it became.
	const mergedInto = $derived((clientQuery.error as ClientReadError | null)?.mergedInto);
	$effect(() => {
		if (mergedInto)
			void goto(resolve('/(app)/clients/[id=uuid]', { id: mergedInto }), { replaceState: true });
	});

	let mergeOpen = $state(false);
	let deleteOpen = $state(false);

	// --- Archive and restore ------------------------------------------------------------------------
	// The same checked endpoint the clients list uses. Archiving is refused while the client still has a
	// live request, quote, job or unpaid invoice, and that refusal comes back as the counts to say so.
	let archiveConfirmOpen = $state(false);

	const archiveMutation = createMutation<
		Awaited<ReturnType<typeof setClientsArchived>>,
		Error,
		{ archived: boolean }
	>(() => ({
		mutationFn: ({ archived }) => setClientsArchived([clientId], archived),
		onSuccess: (result, variables) => {
			archiveConfirmOpen = false;
			void queryClient.invalidateQueries({ queryKey: ['clients'] });
			void queryClient.invalidateQueries({ queryKey: activityKey('client', clientId) });

			const open = result.results[0]?.open_work;
			if (result.changed === 0 && open) {
				const parts = [
					open.requests > 0 ? `${open.requests} open request${open.requests > 1 ? 's' : ''}` : '',
					open.quotes > 0 ? `${open.quotes} open quote${open.quotes > 1 ? 's' : ''}` : '',
					open.jobs > 0 ? `${open.jobs} job${open.jobs > 1 ? 's' : ''} still open` : '',
					open.invoices > 0 ? `${open.invoices} unpaid invoice${open.invoices > 1 ? 's' : ''}` : ''
				].filter(Boolean);
				toast.error(
					'This client still has live work',
					`Finish or archive it first — ${parts.join(', ')}.`
				);
				return;
			}
			if (variables.archived) {
				toast.success('Client archived.', 'Their history stays, and new work brings them back.');
			} else {
				toast.success('Client restored.');
			}
		},
		onError: (error) => toast.error(error.message)
	}));

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
			billing_email: source.billing_email ?? '',
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

	// --- The header --------------------------------------------------------------------------------------

	let manualEmailOpen = $state(false);

	// The client's main property on one line, the way a map search reads it.
	const mainAddress = $derived.by(() => {
		const property = clientQuery.data?.primary_property ?? clientQuery.data?.properties[0];
		if (!property) return null;
		const parts = [
			property.address_line1,
			property.address_line2,
			property.city,
			property.state_region,
			property.postal_code
		].filter((part): part is string => typeof part === 'string' && part.length > 0);
		return parts.length ? parts.join(', ') : null;
	});

	// Main phone · Main email · Payment terms · Lead source, as Jobber's client page shows them.
	const headerFacts = $derived.by((): RecordFact[] => {
		const current = clientQuery.data;
		if (!current) return [];
		return [
			{
				label: 'Main phone',
				value: current.phone,
				empty: 'Not added yet',
				icon: phoneIcon,
				kind: 'time',
				href: current.phone ? `tel:${current.phone}` : undefined
			},
			{
				label: 'Main email',
				value: current.email,
				empty: 'Not added yet',
				icon: mailIcon,
				kind: 'conversation',
				href: current.email ? `mailto:${current.email}` : undefined
			},
			{
				label: 'Payment terms',
				value: current.payment_term_name,
				empty: 'Not set',
				icon: calendarTimeIcon,
				kind: 'time'
			},
			{
				label: 'Lead source',
				value: current.lead_source,
				empty: 'None given',
				icon: speakerphoneIcon,
				kind: 'client'
			}
		];
	});

	// Jobber puts Archive in this same More menu, and swaps it for a Restore button once the client is
	// archived — which is why restoring is a button beside the menu, not an item inside it.
	const headerMenuItems = $derived.by(() => {
		const current = clientQuery.data;
		if (!current) return [];
		return [
			{
				label: 'Edit client details',
				icon: externalIcon,
				onSelect: () =>
					window.open(
						resolve('/(app)/clients/[id=uuid]/edit', { id: current.id }),
						'_blank',
						'noopener'
					)
			},
			...(current.can_merge
				? [{ label: 'Merge client', icon: mergeIcon, onSelect: () => (mergeOpen = true) }]
				: []),
			...(current.can_archive && !current.archived_at
				? [
						{
							label: 'Archive client',
							icon: archiveIcon,
							onSelect: () => (archiveConfirmOpen = true)
						}
					]
				: []),
			// Data privacy Part 6: Jobber and HubSpot put Delete last in the record's More menu, apart from the
			// everyday actions; the pop-up names what goes and keeps them restorable for 30 days.
			...(current.can_delete
				? [
						{
							label: 'Delete client',
							icon: deleteIcon,
							destructive: true,
							onSelect: () => (deleteOpen = true)
						}
					]
				: [])
		];
	});

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

	// --- Lifetime card ------------------------------------------------------------------------------------
	// Each figure is null when this member lacks the permission that gates it (customers.view_financials,
	// quotes.view, jobs.view); it then says so instead of showing a zero that may not be true. A figure whose
	// feature the business's package leaves out is not shown at all.
	const workSummary = $derived(client?.work_summary);
	const firstName = $derived(
		client?.first_name || client?.company_name || client?.display_name || ''
	);
	const sinceFormat = new Intl.DateTimeFormat(undefined, { month: 'short', year: 'numeric' });
	const lifetimeValue = $derived.by(() => {
		if (!workSummary?.included.billing) return undefined;
		if (workSummary.lifetime_billed_minor === null) return '—';
		return new Intl.NumberFormat(undefined, {
			style: 'currency',
			currency: workSummary.currency_code
		}).format(workSummary.lifetime_billed_minor / 100);
	});
	const lifetimeNote = $derived.by(() => {
		if (!workSummary?.included.billing) return undefined;
		if (workSummary.lifetime_billed_minor === null)
			return 'You do not have access to this client’s billing';
		return client?.created_at
			? `Billed to ${firstName} since ${sinceFormat.format(new Date(client.created_at))}`
			: `Billed to ${firstName}`;
	});
	const lifetimeDetails = $derived(
		[
			workSummary?.included.quotes && {
				label: 'Open quotes',
				value:
					workSummary.open_quotes_count === null
						? 'No access'
						: String(workSummary.open_quotes_count)
			},
			workSummary?.included.jobs && {
				label: 'Active jobs',
				value:
					workSummary.active_jobs_count === null
						? 'No access'
						: String(workSummary.active_jobs_count)
			}
		].filter((row): row is { label: string; value: string } => Boolean(row))
	);
	const showLifetime = $derived(lifetimeValue !== undefined || lifetimeDetails.length > 0);

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

	const consentLine = $derived.by(() => {
		if (!marketingConsent?.effective_at) return 'No opt-in or opt-out recorded yet.';
		const when = consentDateFormat.format(new Date(marketingConsent.effective_at));
		const via = consentSourceLabel(marketingConsent.source);
		return via ? `${when} · via ${via}` : when;
	});

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
		{ key: 'city', label: 'City', width: '150px' },
		{ key: 'state', label: 'State', width: '100px' },
		{ key: 'zip', label: 'Zip', width: '110px' }
	];

	// The line under a street tells the office which property this is: its name if it has one, or that the
	// bills go there. An unnamed address shows its street alone, as Jobber does; the Main badge marks the main one.
	function propertyCaption(property: ClientProperty) {
		if (property.label) return property.label;
		return property.is_billing_address ? 'Billing address' : '';
	}
	function streetOf(property: ClientProperty) {
		return [property.address_line1, property.address_line2].filter(Boolean).join(', ');
	}
</script>

<svelte:head>
	<title>{client?.display_name ?? 'Client'} · Contractor CRM</title>
</svelte:head>

{#if mergeOpen && saved}
	<ClientMergeDialog open initialClient={saved} onClose={() => (mergeOpen = false)} />
{/if}

{#if deleteOpen && saved}
	<ClientDeleteDialog
		open
		clients={[{ id: saved.id, display_name: saved.display_name }]}
		onClose={() => (deleteOpen = false)}
		onDeleted={(result) => {
			if (result.deleted.length) void goto(resolve('/(app)/clients'));
		}}
	/>
{/if}

{#if manualEmailOpen && saved}
	<ManualEmailDialog
		open={manualEmailOpen}
		client={saved}
		onClose={() => (manualEmailOpen = false)}
	/>
{/if}

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer variant="open">
	{#if clientQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading client" />
	{:else if (clientQuery.error as ClientReadError | null)?.status === 403}
		<EmptyState
			icon={lockIcon}
			title="You do not have access to this client"
			description="You can open a client once one of their visits is assigned to you. Ask an owner or admin if you need it sooner."
		/>
	{:else if mergedInto}
		<LoadingSkeleton variant="card" label="Opening the merged client" />
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
			cards
			concept
			editing={isEditing}
			dirty={isDirty}
			{saving}
			error={saveError}
			onSave={() => void saveDraft()}
			onCancel={discardDraft}
		>
			{#snippet main()}
				<Tabs tabs={clientTabs} value={activeTab} onChange={selectTab} label="Client sections">
					{#snippet header(tabList)}
						{#snippet detailsEditor()}
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
						<WorkRecordHeader
							icon={userIcon}
							recordType="Client"
							title={client.display_name}
							statusLabel={client.archived_at
								? 'Archived'
								: client.lifecycle_status === 'customer'
									? 'Customer'
									: 'Lead'}
							statusTone={client.archived_at
								? 'inactive'
								: client.lifecycle_status === 'customer'
									? 'success'
									: 'informative'}
							menuItems={headerMenuItems}
							onEditTitle={editingBlock === 'details' ? undefined : () => openBlock('details')}
							onHistory={() => (showHistory = !showHistory)}
							onHistoryHover={warmHistory}
							body={editingBlock === 'details' ? detailsEditor : undefined}
							facts={headerFacts}
							tabs={tabList}
						>
							{#snippet actions()}
								{#if client.archived_at && client.can_archive}
									<Button
										variant="secondary"
										loading={archiveMutation.isPending}
										onclick={() => archiveMutation.mutate({ archived: false })}>Restore</Button
									>
								{/if}
							{/snippet}
							{#snippet line()}
								<p class="client-detail__address">
									<span class="client-detail__address-icon" aria-hidden="true"
										>{@html mapPinIcon}</span
									>
									{#if mainAddress}
										<a
											href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(mainAddress)}`}
											target="_blank"
											rel="noopener noreferrer"
											title="{mainAddress} · Click to open in Google Maps">{mainAddress}</a
										>
									{:else}
										<span class="client-detail__address-blank">No property yet</span>
									{/if}
								</p>
								{#if canMessage}
									<Button variant="secondary" onclick={() => (manualEmailOpen = true)}>
										<span class="client-detail__action-icon" aria-hidden="true"
											>{@html mailIcon}</span
										>
										Message
									</Button>
								{/if}
								{#if client.can_request_review}
									<RequestReviewButton target={{ clientId: client.id }} size="base" />
								{/if}
							{/snippet}
						</WorkRecordHeader>
					{/snippet}

					<TabPanel value="details">
						<SectionBlock
							tone="client"
							title="Properties"
							subtitle="Where the work happens"
							icon={homeIcon}
							level={2}
							class="section-block--flush client-detail__properties"
						>
							{#snippet actions()}
								<Button
									size="small"
									variant="secondary"
									class="client-detail__action"
									onclick={() => (propertyDialog = { property: null })}
									onhover={warmPropertyTaxPicker}
								>
									<span class="client-detail__action-icon" aria-hidden="true">{@html plusIcon}</span
									>
									Add property
								</Button>
							{/snippet}
							{#if properties.length === 0}
								<div class="client-detail__pad">
									<EmptyState
										icon={homeIcon}
										title="No properties yet"
										description="Add where the work happens and it will show up here."
									/>
								</div>
							{:else}
								<DataTable
									columns={propertyColumns}
									items={properties}
									rowId={(property) => property.id}
									caption="Properties"
									variant="card"
								>
									{#snippet row(property: ClientProperty)}
										<th scope="row">
											<span class="client-detail__street">{streetOf(property)}</span>
											{#if propertyCaption(property) || property.is_primary}
												<span class="client-detail__street-caption">
													{propertyCaption(property)}
													{#if property.is_primary}<span class="client-detail__main-pill">Main</span
														>{/if}
												</span>
											{/if}
										</th>
										<td class="client-detail__cell">{property.city}</td>
										<td class="client-detail__cell">{property.state_region ?? '—'}</td>
										<td class="client-detail__cell">{property.postal_code ?? '—'}</td>
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

						<ClientWorkOverview {clientId} clientName={firstName} />

						<ClientSchedule {clientId} clientName={firstName} />
					</TabPanel>

					{#if canSeeCommunication}
						<TabPanel value="communication">
							<SectionBlock
								tone="conversation"
								title="Communication"
								subtitle={`Texts, emails and calls with ${firstName}`}
								icon={messageIcon}
								level={2}
							>
								<ClientCommunicationHistory
									{clientId}
									active={activeTab === 'communication'}
									inbox={communicationsAccessQuery.data?.inbox ?? true}
								/>
							</SectionBlock>
						</TabPanel>
					{/if}
				</Tabs>
			{/snippet}

			{#snippet rail()}
				{#if showHistory}
					<RailCard tone="client" title="Client history" icon={historyCardIcon} description="Newest first">
						{#snippet actions()}
							<Button size="small" variant="tertiary" onclick={() => (showHistory = false)}>
								Close
							</Button>
						{/snippet}
						<ActivityFeed entityType="client" entityId={clientId} {currentUserId} />
					</RailCard>
				{:else}
					{#if showLifetime}
						<MoneyFeatureCard
							icon={cashIcon}
							eyebrow="Lifetime"
							value={lifetimeValue}
							note={lifetimeNote}
							rows={lifetimeDetails}
						/>
					{/if}

					<RailCard tone="client" title="Source and marketing" flush>
						<div class="client-detail__row">
							<IconTile icon={targetIcon} tone="growth" size={32} />
							<div class="client-detail__row-text">
								<span class="client-detail__row-label">Lead source</span>
								{#if editingBlock === 'lead_source'}
									<LeadSourceEditor
										value={client.lead_source ?? ''}
										saving={blockSaving}
										error={blockError}
										onSave={(next) => void saveBlock({ lead_source: next })}
										onCancel={closeBlock}
									/>
								{:else if client.lead_source}
									<span class="client-detail__row-value">{client.lead_source}</span>
								{:else}
									<span class="client-detail__row-blank">
										Not recorded yet. Add it so you know what brings work in.
									</span>
								{/if}
							</div>
							{#if editingBlock !== 'lead_source'}
								<PencilButton onclick={() => openBlock('lead_source')} label="Edit lead source" />
							{/if}
						</div>

						<div class="client-detail__row">
							<IconTile icon={mailIcon} tone="conversation" size={32} />
							<div class="client-detail__row-text">
								<span class="client-detail__row-label">Marketing email</span>
								{#if !marketingConsent}
									<span class="client-detail__row-blank">
										Add an email address to record marketing consent.
									</span>
								{:else}
									<span class="client-detail__consent">
										{#if marketingConsent.state === 'opted_in'}
											<StatusBadge status="success" size="compact">Opted in</StatusBadge>
										{:else if marketingConsent.state === 'opted_out'}
											<StatusBadge status="critical" size="compact">Opted out</StatusBadge>
										{:else}
											<StatusBadge status="informative" size="compact">Not recorded</StatusBadge>
										{/if}
									</span>
									<span class="client-detail__row-note">{consentLine}</span>
								{/if}
							</div>
							{#if canRecordConsent && marketingConsent}
								<Button
									size="small"
									variant="secondary"
									class="client-detail__action client-detail__action--small"
									onclick={() => (marketingConsentOpen = true)}
								>
									Record
								</Button>
							{/if}
						</div>
					</RailCard>

					<RailCard tone="client" title="Tags" count={tagIds.length}>
						{#snippet actions()}
							{#if tagsChanged}<Badge size="small" status="warning">Unsaved</Badge>{/if}
						{/snippet}
						<ClientTagSelect {tagIds} onChange={(next) => (tagIdsDraft = next)} />
					</RailCard>

					{#if canSeeCommunication}
						<RailCard tone="conversation" title="Last communication">
							{#if lastCommunicationQuery.isPending}
								<LoadingSkeleton variant="text" />
							{:else if lastCommunication}
								<div class="client-detail__message">
									<p class="client-detail__message-when">
										<span class="client-detail__message-icon" aria-hidden="true"
											>{@html mailIcon}</span
										>
										{exactTime(lastCommunication.created_at)}
									</p>
									<p class="client-detail__last-communication-subject">
										{lastCommunication.subject}
									</p>
									<div class="client-detail__read-more">
										<Button variant="quiet" size="small" onclick={() => selectTab('communication')}>
											Read more
											{@html arrowRightIcon}
										</Button>
									</div>
								</div>
							{:else}
								<p class="client-detail__rail-blank">Nothing sent yet.</p>
							{/if}
						</RailCard>
					{/if}

					<RailCard tone="conversation" title="Notes" description="Only your team sees these" flush>
						<NotesPanel
							compact
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
						title="Photos and files"
						summary
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

<ConfirmDialog
	open={archiveConfirmOpen}
	title="Archive client"
	confirmLabel="Archive"
	loading={archiveMutation.isPending}
	confirmDisabled={archiveMutation.isPending}
	onConfirm={() => archiveMutation.mutate({ archived: true })}
	onClose={() => {
		if (!archiveMutation.isPending) archiveConfirmOpen = false;
	}}
>
	<p>
		<strong>{saved?.display_name}</strong> leaves your client list. Everything stays — past quotes, jobs,
		invoices and messages — and you can find them again under the Archived status filter on the Clients
		page. Starting new work for them brings them back automatically.
	</p>
</ConfirmDialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The client line of the header: the main property, which opens in Google Maps, then the ways to reach out.
	.client-detail__address {
		display: flex;
		flex: 1 1 auto;
		min-width: 0;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-heading);
		font-size: var(--typography--fontSize-base);
		font-weight: 500;

		a {
			overflow: hidden;
			color: inherit;
			text-decoration: none;
			text-overflow: ellipsis;
			white-space: nowrap;

			&:hover {
				color: var(--color-interactive);
				text-decoration: underline;
			}
		}
	}

	.client-detail__address-icon {
		display: inline-flex;
		flex: 0 0 auto;
		color: var(--color-client);

		:global(svg) {
			display: block;
			width: 18px;
			height: 18px;
		}
	}

	.client-detail__address-blank {
		color: var(--color-text--secondary);
	}

	// The grid, the cards and the rail all live in RecordDetailLayout (`cards`). What is left here is only
	// what this page's own content needs.
	// The tab row now sits inside the header card, so the tabs root only stacks the card and its panels.
	:global(.client-detail .tabs) {
		display: flex;
		flex-direction: column;
		gap: 20px;
	}
	:global(.client-detail .tab-panel:not([hidden])) {
		gap: 20px;
		padding: 0;
	}

	:global(.client-detail__action-icon) {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 16px;
			height: 16px;
		}
	}

	// The properties table is only four short columns, so it never needs the list tables' width floor.
	:global(.client-detail__properties) {
		--data-table-min-width: 520px;

		:global(.data-table--card tbody tr:last-child th),
		:global(.data-table--card tbody tr:last-child td) {
			border-bottom: 0;
		}
	}

	.client-detail {
		&__pad {
			padding: 0 24px 24px;
		}

		&__street {
			display: block;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__street-caption {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			margin-top: 3px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__main-pill {
			padding: 2px 8px;
			border-radius: 999px;
			color: var(--color-text--secondary);
			background: var(--color-surface--background--subtle);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__cell {
			color: var(--color-text);
			font-weight: 500;
		}

		// A row inside the Source and marketing card: a small icon tile, the label over its value, and the
		// row's one action at the end. Rows run edge to edge under a hairline.
		&__row {
			display: flex;
			align-items: center;
			gap: 12px;
			padding: 12px 20px;
			border-top: var(--border-base) solid var(--color-border);
		}

		&__row-text {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-direction: column;
			align-items: flex-start;
			gap: 2px;
		}

		&__row-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__row-value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;
		}

		&__row-blank,
		&__row-note {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__row-text :global(.lead-source-editor) {
			align-self: stretch;
			margin-top: 4px;
		}

		&__consent {
			display: flex;
			align-items: center;
			margin: 2px 0;
		}

		&__rail-blank {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__message {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: 4px;
			margin-top: -2px;
		}

		&__message-when {
			display: flex;
			align-items: center;
			gap: 6px;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__message-icon {
			display: inline-flex;
			color: var(--color-icon--secondary);

			:global(svg) {
				width: 13px;
				height: 13px;
			}
		}

		&__last-communication-subject {
			max-width: 100%;
			overflow: hidden;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			text-overflow: ellipsis;
			white-space: nowrap;
		}

		&__read-more {
			margin-top: 6px;
		}
	}
</style>
