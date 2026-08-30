<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteSummaryCard from '$lib/components/quotes/QuoteSummaryCard.svelte';
	import QuoteDiscountCard from '$lib/components/quotes/QuoteDiscountCard.svelte';
	import QuoteTaxCard from '$lib/components/quotes/QuoteTaxCard.svelte';
	import QuoteDepositCard from '$lib/components/quotes/QuoteDepositCard.svelte';
	import QuoteClientViewBlock from '$lib/components/quotes/QuoteClientViewBlock.svelte';
	import QuoteEmailDialog from '$lib/components/quotes/QuoteEmailDialog.svelte';
	import AddSectionControl from '$lib/components/work/AddSectionControl.svelte';
	import ActivityFeed from '$lib/components/collaboration/ActivityFeed.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import NotesPanel from '$lib/components/collaboration/NotesPanel.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import {
		activityKey,
		attachmentsKey,
		createNote,
		deleteNote,
		fetchActivity,
		fetchAttachments,
		fetchNotes,
		notesKey,
		updateNote,
		isImageAttachment,
		type NoteChange
	} from '$lib/collaboration/api';
	import {
		fetchQuote,
		issueQuoteAccessLink,
		publishQuote,
		recordQuoteDecision,
		reviseQuote,
		quoteCountsKey,
		quoteDetailKey,
		quoteLinesKey,
		saveQuoteCopy,
		saveQuoteDraft,
		saveQuoteLines,
		saveQuoteVersionAttachments,
		collectQuoteSignature,
		quoteSignatureImageHref,
		saveQuoteVisibility,
		createSimilarQuote,
		archiveQuote,
		restoreQuote,
		deleteQuote,
		type QuoteVisibility,
		type QuoteWriteError,
		type RequestPricingLine,
		type RequestPricingLineInput
	} from '$lib/quotes/api';
	import { QUOTE_STATUS_LABELS, QUOTE_STATUS_TONES } from '$lib/quotes/statuses';
	import CollectSignatureDialog from '$lib/components/quotes/CollectSignatureDialog.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import fileDollarIcon from '@tabler/icons/outline/file-dollar.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import speakerphoneIcon from '@tabler/icons/outline/speakerphone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import versionsIcon from '@tabler/icons/outline/versions.svg?raw';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import signatureIcon from '@tabler/icons/outline/signature.svg?raw';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import archiveIcon from '@tabler/icons/outline/archive.svg?raw';
	import archiveOffIcon from '@tabler/icons/outline/archive-off.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const quoteId = $derived(page.params.id ?? '');
	const currentUserId = $derived(page.data.user?.id as string | undefined);
	const sectionOptions = [
		{ id: 'introduction', label: 'Introduction', icon: speakerphoneIcon },
		{ id: 'attachments', label: 'Attachments', icon: paperclipIcon },
		{ id: 'images', label: 'Images', icon: photoIcon },
		{ id: 'client_message', label: 'Client Message', icon: messageIcon }
	];

	const quoteQuery = createQuery(() => ({
		queryKey: quoteDetailKey(quoteId),
		queryFn: () => fetchQuote(quoteId),
		enabled: Boolean(quoteId),
		staleTime: 15_000
	}));
	const saved = $derived(quoteQuery.data);

	const notesQuery = createQuery(() => ({
		queryKey: notesKey('quote', quoteId),
		queryFn: () => fetchNotes('quote', quoteId),
		enabled: Boolean(quoteId),
		staleTime: 15_000
	}));

	// The quote's own files, so the client-facing picker and the rail's Attachments card read one cache
	// entry between them rather than fetching the same list twice.
	const attachmentsQuery = createQuery(() => ({
		queryKey: attachmentsKey('quote', quoteId),
		queryFn: () => fetchAttachments('quote', quoteId),
		enabled: Boolean(quoteId),
		staleTime: 15_000
	}));

	let editingTitle = $state(false);
	let titleDraft = $state('');
	let editingDisclaimer = $state(false);
	let disclaimerDraft = $state('');
	let editingIntroduction = $state(false);
	let introductionDraft = $state('');
	let editingClientMessage = $state(false);
	let clientMessageDraft = $state('');
	let editingVisibility = $state(false);
	// Null means nobody has touched these yet, so they follow whatever the last read said. Staging them as
	// a copy of the saved values instead would fight every refetch.
	let visibilityDraft = $state<QuoteVisibility | null>(null);
	let fileSelection = $state<string[] | null>(null);
	let notePending = $state<NoteChange[]>([]);
	let documentAttachments = $state<AttachmentsCard>();
	let imageAttachments = $state<AttachmentsCard>();
	let pendingDocumentCount = $state(0);
	let pendingImageCount = $state(0);
	let addedAttachments = $state(false);
	let addedImages = $state(false);
	let saving = $state(false);
	let saveError = $state('');

	const title = $derived(saved?.quote.title?.trim() || `Quote #${saved?.quote.quote_number ?? ''}`);
	const titleChanged = $derived(
		editingTitle && titleDraft.trim() !== (saved?.quote.title?.trim() ?? '')
	);
	const disclaimerChanged = $derived(
		editingDisclaimer &&
			disclaimerDraft.trim() !== (saved?.version?.contract_disclaimer?.trim() ?? '')
	);
	const introductionChanged = $derived(
		editingIntroduction && introductionDraft.trim() !== (saved?.version?.introduction?.trim() ?? '')
	);
	const clientMessageChanged = $derived(
		editingClientMessage &&
			clientMessageDraft.trim() !== (saved?.version?.client_message?.trim() ?? '')
	);

	const savedVisibility = $derived<QuoteVisibility>({
		show_quantities: saved?.version?.show_quantities ?? true,
		show_unit_prices: saved?.version?.show_unit_prices ?? true,
		show_line_totals: saved?.version?.show_line_totals ?? true,
		show_totals: saved?.version?.show_totals ?? true
	});
	const visibility = $derived(visibilityDraft ?? savedVisibility);
	const visibilityChanged = $derived(
		visibilityDraft !== null &&
			(Object.keys(savedVisibility) as Array<keyof QuoteVisibility>).some(
				(key) => visibility[key] !== savedVisibility[key]
			)
	);

	const savedClientFiles = $derived(
		(saved?.version_attachments ?? [])
			.filter((entry) => entry.customer_visible)
			.map((entry) => entry.attachment_id)
	);
	const clientFiles = $derived(fileSelection ?? savedClientFiles);
	const clientFilesChanged = $derived(
		fileSelection !== null &&
			(clientFiles.length !== savedClientFiles.length ||
				clientFiles.some((id) => !savedClientFiles.includes(id)))
	);
	const clientDocumentIds = $derived(
		clientFiles.filter((id) => {
			const file = (attachmentsQuery.data ?? []).find((entry) => entry.id === id);
			return file ? !isImageAttachment(file) : false;
		})
	);
	const clientImageIds = $derived(
		clientFiles.filter((id) => {
			const file = (attachmentsQuery.data ?? []).find((entry) => entry.id === id);
			return file ? isImageAttachment(file) : false;
		})
	);
	const showIntroduction = $derived(editingIntroduction || Boolean(saved?.version?.introduction));
	const showClientMessage = $derived(
		editingClientMessage || Boolean(saved?.version?.client_message)
	);
	const showAttachments = $derived(addedAttachments || clientDocumentIds.length > 0);
	const showImages = $derived(addedImages || clientImageIds.length > 0);
	const availableSections = $derived([
		...(!showIntroduction ? (['introduction'] as const) : []),
		...(!showAttachments ? (['attachments'] as const) : []),
		...(!showImages ? (['images'] as const) : []),
		...(!showClientMessage ? (['client_message'] as const) : [])
	]);
	const availableLowerSections = $derived(
		availableSections.filter((section) => section !== 'introduction')
	);
	const introductionOption = $derived(
		sectionOptions.filter((option) => option.id === 'introduction')
	);
	const lowerSectionOptions = $derived(
		sectionOptions.filter((option) => availableLowerSections.some((id) => id === option.id))
	);
	const pendingFileCount = $derived(pendingDocumentCount + pendingImageCount);

	const isEditing = $derived(
		editingTitle ||
			editingDisclaimer ||
			editingIntroduction ||
			editingClientMessage ||
			editingVisibility ||
			notePending.length > 0 ||
			pendingFileCount > 0
	);
	const isDirty = $derived(
		titleChanged ||
			disclaimerChanged ||
			introductionChanged ||
			clientMessageChanged ||
			visibilityChanged ||
			clientFilesChanged ||
			notePending.length > 0 ||
			pendingFileCount > 0
	);
	// Editing needs a draft to write into. A quote whose draft has been published away is read-only even
	// though the quote itself still says draft, because every command refuses a quote with no draft.
	const editable = $derived(
		Boolean(
			saved?.can_edit &&
			saved.quote.status === 'draft' &&
			saved.version &&
			saved.version.status === 'draft'
		)
	);

	const quoteLines = $derived<RequestPricingLine[]>(
		(saved?.lines ?? []).map((line) => ({
			...line,
			catalog_item_id: line.source_catalog_item_id,
			unit_price_minor: line.unit_price_minor ?? 0,
			unit_cost_minor: line.unit_cost_minor ?? 0,
			line_total_minor: line.line_total_minor ?? 0,
			line_cost_total_minor: line.line_cost_total_minor ?? 0
		}))
	);

	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	});

	// A quote that has never been published has no versions worth naming, so the row stays away entirely
	// rather than saying 'Version 1' about a draft nobody has seen.
	const versionFact = $derived.by(() => {
		const published = saved?.published_version_number;
		if (!saved || !published) return null;
		return {
			label: 'Version',
			value: saved.version?.status === 'published' ? String(published) : `Draft after ${published}`
		};
	});

	// The facts row grows with the lifecycle, the way Jobber's does: created, then sent, then whichever
	// answer came back. A date that has not happened yet is not listed at all rather than sitting there
	// empty - except the answer, which stays visible so the row does not jump when one arrives.
	const headerFacts = $derived([
		{ label: 'Quote #', value: saved ? String(saved.quote.quote_number) : null },
		...(versionFact ? [versionFact] : []),
		{
			label: 'Created',
			value: saved ? dateTimeFormat.format(new Date(saved.quote.created_at)) : null
		},
		...(saved?.quote.sent_at
			? [{ label: 'Sent', value: dateTimeFormat.format(new Date(saved.quote.sent_at)) }]
			: []),
		{
			label: saved?.quote.decision === 'declined' ? 'Declined' : 'Approved',
			value: saved?.quote.decided_at
				? dateTimeFormat.format(new Date(saved.quote.decided_at))
				: null,
			empty:
				saved?.quote.status === 'approved' || saved?.quote.status === 'converted'
					? 'Date not recorded'
					: 'No answer yet'
		}
	]);

	// Only meaningful once approved and not yet converted: readiness is what stands between an approval
	// and starting the job, and a converted quote has already crossed that line.
	const readinessBadge = $derived.by(() => {
		if (saved?.quote.status !== 'approved') return null;
		return saved.ready_for_job
			? { label: 'Ready for job', tone: 'success' as const }
			: { label: 'Deposit due', tone: 'warning' as const };
	});

	const propertyLine = $derived.by(() => {
		const property = saved?.quote.property;
		if (!property) return null;
		return [
			property.address_line1,
			property.address_line2,
			property.city,
			property.state_region,
			property.postal_code
		]
			.filter(Boolean)
			.join(', ');
	});

	// --- Moving the quote along ------------------------------------------------------------------------

	// Publishing, revising, and recording an answer all end the same way: the quote is re-read and every
	// list that counted it is invalidated. One flag guards all three so a second click cannot race the
	// first, and the message a refusal carries is the sentence the database wrote.
	let lifecycleSaving = $state(false);

	async function runLifecycle(done: string, action: () => Promise<unknown>) {
		if (lifecycleSaving) return;
		lifecycleSaving = true;
		try {
			await action();
			await refreshQuote();
			toast.success(done);
		} catch (error) {
			const failure = error as QuoteWriteError;
			toast.error(
				failure.fieldErrors?.form ?? failure.message ?? 'That could not be done. Try again.'
			);
		} finally {
			lifecycleSaving = false;
		}
	}

	const sendable = $derived(
		Boolean(saved?.can_send && saved.quote.status === 'draft' && saved.version?.status === 'draft')
	);
	// A delivery intent must be built from a published quote. Drafts still use the offline publish path;
	// once a customer is awaiting a response, Send email is the single next-step action in the header.
	const emailable = $derived(
		Boolean(
			saved?.can_send_email &&
			saved.quote.current_published_version_id &&
			['awaiting_response', 'changes_requested'].includes(saved.quote.status)
		)
	);
	// Revising needs something published to copy and nothing already in progress. A quote still saying
	// draft after a publish has no draft version, which is exactly the case revise exists for.
	const revisable = $derived(
		Boolean(
			saved?.can_edit && saved.quote.current_published_version_id && !saved.quote.draft_version_id
		)
	);
	const answerable = $derived(
		Boolean(
			saved?.can_record_decision &&
			['draft', 'awaiting_response', 'changes_requested'].includes(saved.quote.status)
		)
	);

	// Any status but converted or already archived. Approved asks for a reason (the dialog below);
	// everything else is one click, same as Mark as Awaiting Response.
	const archivable = $derived(
		Boolean(saved?.can_edit && !['converted', 'archived'].includes(saved.quote.status))
	);
	const restorable = $derived(Boolean(saved?.can_edit && saved.quote.status === 'archived'));
	// Never published, ever - current_published_version_id stays set forever once a quote is first
	// published, even after a later revision takes status back to draft. And never made from a Request:
	// deleting one of those would leave the Request's own terminal Converted status pointing at nothing.
	const deletable = $derived(
		Boolean(
			saved?.can_edit &&
			saved.quote.status === 'draft' &&
			!saved.quote.request_id &&
			!saved.quote.current_published_version_id
		)
	);

	function send() {
		if (!saved?.version) return;
		const revision = saved.version.revision;
		void runLifecycle('Quote marked as awaiting response', () => publishQuote(quoteId, revision));
	}

	function answer(decision: 'approved' | 'declined') {
		const revision = saved?.version?.status === 'draft' ? saved.version.revision : undefined;
		void runLifecycle(
			decision === 'approved' ? 'Quote marked as approved' : 'Quote marked as declined',
			() => recordQuoteDecision(quoteId, { decision, expectedRevision: revision })
		);
	}

	let quoteEmailOpen = $state(false);

	// Jobber offers Collect Signature in every status a quote can still be answered in, draft included,
	// because the tablet at the customer's door is often the first time anyone has seen it. Signing
	// approves the quote, so it is guarded by the same permission as recording any other answer.
	let collectingSignature = $state(false);

	async function collectSignature(input: {
		name: string;
		method: 'typed' | 'in_person';
		image: string | null;
		note: string;
	}) {
		const revision = saved?.version?.status === 'draft' ? saved.version.revision : undefined;
		await collectQuoteSignature(quoteId, {
			name: input.name,
			method: input.method,
			image: input.image,
			note: input.note || null,
			expectedRevision: revision
		});
		await refreshQuote();
		toast.success('Signature collected. Quote approved.');
	}

	// A brand-new quote, so this leaves the page rather than refreshing it.
	let creatingSimilar = $state(false);

	async function createSimilar() {
		if (creatingSimilar) return;
		creatingSimilar = true;
		try {
			const result = await createSimilarQuote(quoteId);
			toast.success(`Quote #${result.quote_number} created.`);
			await goto(resolve('/(app)/quotes/[id]', { id: result.quote_id }));
		} catch (error) {
			const failure = error as QuoteWriteError;
			toast.error(
				failure.fieldErrors?.form ?? failure.message ?? 'That could not be done. Try again.'
			);
		} finally {
			creatingSimilar = false;
		}
	}

	// Approved is the one status that asks why, so it gets a dialog with a reason field. Every other
	// archivable status is one click, same as Mark as Awaiting Response.
	let archivingApproved = $state(false);
	let archiveReason = $state('');

	function archive() {
		if (saved?.quote.status === 'approved') {
			archiveReason = '';
			archivingApproved = true;
			return;
		}
		void runLifecycle('Quote archived', () => archiveQuote(quoteId));
	}

	async function confirmArchiveApproved() {
		const reason = archiveReason.trim();
		if (!reason || lifecycleSaving) return;
		lifecycleSaving = true;
		try {
			await archiveQuote(quoteId, reason);
			await refreshQuote();
			toast.success('Quote archived');
			archivingApproved = false;
		} catch (error) {
			const failure = error as QuoteWriteError;
			toast.error(
				failure.fieldErrors?.form ?? failure.message ?? 'That could not be done. Try again.'
			);
		} finally {
			lifecycleSaving = false;
		}
	}

	function restore() {
		void runLifecycle('Quote restored', () => restoreQuote(quoteId));
	}

	let deletingQuote = $state(false);

	async function confirmDelete() {
		if (lifecycleSaving) return;
		lifecycleSaving = true;
		try {
			await deleteQuote(quoteId);
			toast.success('Quote deleted.');
			await goto(resolve('/(app)/quotes'));
		} catch (error) {
			const failure = error as QuoteWriteError;
			toast.error(
				failure.fieldErrors?.form ?? failure.message ?? 'That could not be done. Try again.'
			);
		} finally {
			lifecycleSaving = false;
			deletingQuote = false;
		}
	}

	// One action, named for the next step this quote is waiting on. An approved quote's next step is a Job,
	// which is not built, so it says nothing rather than offering a button that cannot work.
	const primaryAction = $derived.by(() => {
		if (!saved) return undefined;
		if (emailable)
			return {
				label: 'Send email',
				onclick: () => (quoteEmailOpen = true)
			};
		if (sendable)
			return {
				label: 'Mark as awaiting response',
				loading: lifecycleSaving,
				onclick: () => send()
			};
		if (answerable && saved.quote.status !== 'draft')
			return {
				label: 'Mark as approved',
				loading: lifecycleSaving,
				onclick: () => answer('approved')
			};
		return undefined;
	});

	// The client's view of this quote, in its own tab, with our sidebar left behind. `print` asks that tab
	// to open the print dialog as soon as it has drawn, so `Print or save PDF` is one press rather than a
	// page and then an instruction.
	function openCustomerView(print = false) {
		if (!quoteId) return;
		const path = resolve('/(app)/quotes/[id]/preview', { id: quoteId });
		window.open(print ? `${path}?print=1` : path, '_blank', 'noopener');
	}

	// The customer's own link. Nothing is created by looking at a quote, so this is the press that makes
	// the recipient and the door together — and pressing it again makes a fresh one and turns the old one
	// off, which is what staff mean by "send them the link again".
	//
	// The raw URL comes back exactly once. It goes straight to the clipboard, because there is nowhere to
	// read it from afterwards.
	let linkSaving = $state(false);

	async function copyCustomerLink() {
		if (linkSaving || !quoteId) return;
		linkSaving = true;
		try {
			const link = await issueQuoteAccessLink(quoteId);
			await navigator.clipboard.writeText(link.url);
			toast.success(`Link copied. Send it to ${link.recipient_email}.`);
		} catch (error) {
			const failure = error as QuoteWriteError;
			toast.error(
				failure.fieldErrors?.form ?? failure.message ?? 'That link could not be created.'
			);
		} finally {
			linkSaving = false;
		}
	}

	// Following Jobber, the menu never lists a state the quote is already in, so it can never offer a move
	// that does nothing. Archiving an approved quote opens a small reason dialog instead of firing straight
	// away, since that is the one status the database asks an explanation for.
	const quoteMenuItems = $derived.by(() => {
		if (!saved) return [];
		const items = [];
		if (sendable && primaryAction?.label !== 'Mark as awaiting response')
			items.push({ label: 'Mark as awaiting response', icon: sendIcon, onSelect: () => send() });
		if (answerable && saved.quote.status !== 'approved')
			items.push({
				label: 'Mark as approved',
				icon: checkIcon,
				disabled: lifecycleSaving,
				onSelect: () => answer('approved')
			});
		if (answerable && saved.quote.status !== 'declined')
			items.push({
				label: 'Mark as declined',
				icon: xIcon,
				disabled: lifecycleSaving,
				onSelect: () => answer('declined')
			});
		if (answerable)
			items.push({
				label: 'Collect signature',
				icon: signatureIcon,
				disabled: lifecycleSaving,
				onSelect: () => (collectingSignature = true)
			});
		if (revisable)
			items.push({
				label: 'Start a new version',
				icon: versionsIcon,
				disabled: lifecycleSaving,
				onSelect: () => void runLifecycle('New version started', () => reviseQuote(quoteId))
			});
		// Only once something is published: a link to a quote nobody has sent points at nothing the
		// customer is allowed to see.
		if (saved.can_send && saved.quote.current_published_version_id)
			items.push({
				label: 'Copy customer link',
				icon: linkIcon,
				disabled: linkSaving,
				onSelect: () => void copyCustomerLink()
			});
		// Both open the client's own view in a new tab, the way Jobber does, and both are offered in every
		// status including draft — checking a quote before sending it is the whole point of a preview.
		items.push({
			label: 'Preview as client',
			icon: eyeIcon,
			onSelect: () => openCustomerView()
		});
		items.push({
			label: 'Print or save PDF',
			icon: printIcon,
			onSelect: () => openCustomerView(true)
		});
		items.push({
			label: 'Convert to job',
			icon: briefcaseIcon,
			disabled: true,
			onSelect: () => {}
		});
		// Available from any status, including archived - a fresh start never depends on where this one
		// ended up.
		items.push({
			label: 'Create similar quote',
			icon: copyIcon,
			disabled: creatingSimilar,
			onSelect: () => void createSimilar()
		});
		if (archivable)
			items.push({
				label: 'Archive',
				icon: archiveIcon,
				disabled: lifecycleSaving,
				onSelect: () => archive()
			});
		if (restorable)
			items.push({
				label: 'Restore',
				icon: archiveOffIcon,
				disabled: lifecycleSaving,
				onSelect: () => restore()
			});
		if (deletable)
			items.push({
				label: 'Delete',
				icon: trashIcon,
				destructive: true,
				disabled: lifecycleSaving,
				onSelect: () => (deletingQuote = true)
			});
		return items;
	});

	// Jobber swaps the whole rail for the history panel rather than opening it beside the notes. Nothing
	// about it loads with the page: hovering the button starts the fetch, so the feed is usually already
	// there by the time the click lands.
	let showHistory = $state(false);

	function warmHistory() {
		if (!quoteId) return;
		void queryClient.prefetchQuery({
			queryKey: activityKey('quote', quoteId),
			queryFn: () => fetchActivity('quote', quoteId)
		});
	}

	const clientMenuItems = $derived(
		saved?.quote.client
			? [
					{
						label: 'View client profile',
						onSelect: () =>
							void goto(resolve('/(app)/clients/[id]', { id: saved.quote.client!.id }))
					}
				]
			: []
	);

	function discardDraft() {
		editingTitle = false;
		titleDraft = '';
		editingDisclaimer = false;
		disclaimerDraft = '';
		editingIntroduction = false;
		introductionDraft = '';
		editingClientMessage = false;
		clientMessageDraft = '';
		editingVisibility = false;
		visibilityDraft = null;
		fileSelection = null;
		notePending = [];
		documentAttachments?.discardChanges();
		imageAttachments?.discardChanges();
		addedAttachments = false;
		addedImages = false;
		saveError = '';
	}

	async function refreshQuote() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: quoteDetailKey(quoteId) }),
			queryClient.invalidateQueries({ queryKey: quoteLinesKey(quoteId) }),
			queryClient.invalidateQueries({ queryKey: ['quotes', 'list'] }),
			queryClient.invalidateQueries({ queryKey: quoteCountsKey }),
			queryClient.invalidateQueries({ queryKey: notesKey('quote', quoteId) }),
			queryClient.invalidateQueries({ queryKey: activityKey('quote', quoteId) }),
			invalidatePipeline(queryClient)
		]);
	}

	async function saveDraft() {
		if (!saved?.version || saving || !isDirty) return;
		saving = true;
		saveError = '';

		try {
			// Everything below shares one draft revision, so these go one after another and each carries the
			// revision the one before it handed back. Firing them together would make the second a stale write.
			let revision = saved.version.revision;
			const filesBefore = attachmentsQuery.data ?? [];
			const hadFileChanges = pendingFileCount > 0 || clientFilesChanged;

			if (titleChanged || disclaimerChanged) {
				const result = await saveQuoteDraft(quoteId, revision, {
					title: titleChanged ? titleDraft.trim() : (saved.quote.title?.trim() ?? ''),
					contract_disclaimer: disclaimerChanged
						? disclaimerDraft.trim() || null
						: saved.version.contract_disclaimer
				});
				revision = result.revision;
				editingTitle = false;
				titleDraft = '';
				editingDisclaimer = false;
				disclaimerDraft = '';
			}

			if (introductionChanged || clientMessageChanged) {
				const result = await saveQuoteCopy(quoteId, revision, {
					introduction: introductionChanged
						? introductionDraft.trim() || null
						: saved.version.introduction,
					client_message: clientMessageChanged
						? clientMessageDraft.trim() || null
						: saved.version.client_message
				});
				revision = result.revision;
				editingIntroduction = false;
				introductionDraft = '';
				editingClientMessage = false;
				clientMessageDraft = '';
			}

			if (visibilityChanged) {
				const result = await saveQuoteVisibility(quoteId, revision, visibility);
				revision = result.revision;
				editingVisibility = false;
				visibilityDraft = null;
			}

			for (const change of [...notePending]) {
				if (change.kind === 'create')
					await createNote({ entityType: 'quote', entityId: quoteId, body: change.body });
				else if (change.kind === 'update')
					await updateNote({
						id: change.id,
						entityType: 'quote',
						entityId: quoteId,
						body: change.body
					});
				else if (change.kind === 'pin')
					await updateNote({
						id: change.id,
						entityType: 'quote',
						entityId: quoteId,
						pinned: change.pinned
					});
				else await deleteNote({ id: change.id, entityType: 'quote', entityId: quoteId });
				notePending = notePending.filter((entry) => entry !== change);
			}

			const [failedDocuments, failedImages] = await Promise.all([
				documentAttachments?.saveAll(quoteId) ?? 0,
				imageAttachments?.saveAll(quoteId) ?? 0
			]);
			const failedFiles = failedDocuments + failedImages;
			if (failedFiles > 0)
				saveError =
					failedFiles === 1
						? 'Everything else was saved, but one file did not upload. Try it again below.'
						: `Everything else was saved, but ${failedFiles} files did not upload. Try them again below.`;

			if (failedFiles === 0 && hadFileChanges) {
				const filesAfter = await fetchAttachments('quote', quoteId);
				const beforeIds = new Set(filesBefore.map((file) => file.id));
				const afterIds = new Set(filesAfter.map((file) => file.id));
				const desiredIds = [
					...new Set([
						...clientFiles.filter((id) => afterIds.has(id)),
						...filesAfter.filter((file) => !beforeIds.has(file.id)).map((file) => file.id)
					])
				];
				const differs =
					desiredIds.length !== savedClientFiles.length ||
					desiredIds.some((id) => !savedClientFiles.includes(id));
				if (differs) {
					const result = await saveQuoteVersionAttachments(
						quoteId,
						revision,
						desiredIds.map((id) => ({
							attachment_id: id,
							display_name: filesAfter.find((file) => file.id === id)?.file_name ?? 'Attachment',
							customer_visible: true
						}))
					);
					revision = result.revision;
				}
				fileSelection = null;
				addedAttachments = false;
				addedImages = false;
			}

			await refreshQuote();
		} catch (caught) {
			const writeError = caught as QuoteWriteError;
			if (writeError.reason === 'stale') {
				discardDraft();
				await refreshQuote();
				saveError = 'Someone else changed this quote. The latest version is now on screen.';
			} else {
				saveError = writeError.message || 'Those changes could not be saved.';
			}
		} finally {
			saving = false;
		}
	}

	async function saveLines(expectedRevision: number, lines: RequestPricingLineInput[]) {
		try {
			await saveQuoteLines(quoteId, expectedRevision, lines);
		} finally {
			await refreshQuote();
		}
	}
</script>

<svelte:head><title>{title || 'Quote'} · Contractor CRM</title></svelte:head>

<PageContainer>
	{#if quoteQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading quote" />
	{:else if quoteQuery.isError}
		<ErrorState description="That quote could not be loaded. Refresh and try again." />
	{:else if saved}
		<RecordDetailLayout
			class="quote-detail"
			editing={isEditing}
			dirty={isDirty}
			{saving}
			error={saveError}
			onSave={() => void saveDraft()}
			onCancel={discardDraft}
		>
			{#snippet main()}
				<WorkRecordHeader
					icon={fileDollarIcon}
					recordType="Quote"
					{title}
					statusLabel={QUOTE_STATUS_LABELS[saved.quote.status]}
					statusTone={QUOTE_STATUS_TONES[saved.quote.status]}
					{primaryAction}
					menuItems={quoteMenuItems}
					onHistory={() => (showHistory = !showHistory)}
					onHistoryHover={warmHistory}
					onEditTitle={editable
						? () => {
								titleDraft = saved.quote.title ?? '';
								editingTitle = true;
							}
						: undefined}
					{editingTitle}
					bind:titleDraft
				>
					{#snippet badges()}
						{#if readinessBadge}
							<StatusBadge status={readinessBadge.tone}>{readinessBadge.label}</StatusBadge>
						{/if}
					{/snippet}
					{#snippet summary()}
						<ClientSummaryCard
							name={saved.quote.client?.display_name ??
								saved.version?.client_display_name ??
								'No client'}
							href={saved.quote.client
								? resolve('/(app)/clients/[id]', { id: saved.quote.client.id })
								: undefined}
							addresses={[{ value: propertyLine, empty: 'No property on this quote' }]}
							phone={saved.quote.client?.phone}
							email={saved.quote.client?.email}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet facts()}<RecordFactsList facts={headerFacts} />{/snippet}
				</WorkRecordHeader>

				{#if saved.signature}
					<SectionBlock title="Signature" icon={signatureIcon} level={2}>
						<div class="quote-signature">
							{#if saved.signature.has_image}
								<img
									class="quote-signature__image"
									src={quoteSignatureImageHref(quoteId, saved.signature.quote_signature_id)}
									alt={`Signature of ${saved.signature.signer_name}`}
								/>
							{:else}
								<p class="quote-signature__typed">{saved.signature.signer_name}</p>
							{/if}
							<p class="quote-signature__meta">
								Signed by {saved.signature.signer_name} on
								{dateTimeFormat.format(new Date(saved.signature.signed_at))}, on version
								{saved.signature.version_number}.
							</p>
						</div>
					</SectionBlock>
				{/if}

				{#if editable && !showIntroduction}
					<AddSectionControl
						options={introductionOption}
						onAdd={() => {
							introductionDraft = '';
							editingIntroduction = true;
						}}
					/>
				{/if}

				{#if showIntroduction}<SectionBlock
						title="Introduction"
						icon={speakerphoneIcon}
						level={2}
						form={editingIntroduction}
					>
						{#snippet actions()}
							{#if editable && !editingIntroduction}
								<PencilButton
									onclick={() => {
										introductionDraft = saved.version?.introduction ?? '';
										editingIntroduction = true;
									}}
									label="Edit the introduction"
								/>
							{:else if introductionChanged}
								<Badge size="small" status="warning">Unsaved</Badge>
							{/if}
						{/snippet}

						{#if editingIntroduction}
							<Textarea
								id="quote-introduction"
								label="How this quote opens, above the pricing"
								rows={4}
								maxlength={10000}
								bind:value={introductionDraft}
							/>
						{:else if saved.version?.introduction}
							<p class="quote-detail__copy">{saved.version.introduction}</p>
						{:else}
							<EmptyState
								icon={speakerphoneIcon}
								title="No introduction"
								description="Say what this quote is for before the client reaches the prices."
							/>
						{/if}
					</SectionBlock>{/if}

				<ProductsAndServicesBlock
					lines={quoteLines}
					quoteChoices
					revision={saved.version?.revision ?? 0}
					subtotalMinor={saved.can_see_price ? (saved.version?.subtotal_minor ?? 0) : null}
					editable={editable && saved.can_see_price}
					showPrices={saved.can_see_price}
					currencyCode={saved.version?.currency_code ?? saved.quote.currency_code}
					attachTo={{ entityType: 'quote', entityId: quoteId }}
					emptyDescription="Add the products and services this quote covers."
					editorTotalLabel="Quote subtotal"
					saveLabel="Save pricing"
					lockedMessage={saved.version?.status === 'published'
						? 'This version has been published, so its pricing cannot be changed.'
						: saved.quote.status === 'draft'
							? 'You can view this pricing, but you do not have access to change it.'
							: 'Pricing is locked because this quote is no longer a draft.'}
					onSave={saveLines}
				>
					{#snippet clientView()}
						<QuoteClientViewBlock
							saved={savedVisibility}
							draft={visibility}
							editing={editingVisibility}
							changed={visibilityChanged}
							{editable}
							onEdit={() => {
								if (editingVisibility) {
									editingVisibility = false;
									visibilityDraft = null;
								} else {
									visibilityDraft = { ...savedVisibility };
									editingVisibility = true;
								}
							}}
							onChange={(next) => (visibilityDraft = next)}
						/>
					{/snippet}
				</ProductsAndServicesBlock>

				{#if editable && availableLowerSections.length > 0}
					<AddSectionControl
						options={lowerSectionOptions}
						onAdd={(section) => {
							if (section === 'attachments') addedAttachments = true;
							else if (section === 'images') addedImages = true;
							else if (section === 'client_message') {
								clientMessageDraft = '';
								editingClientMessage = true;
							}
						}}
					/>
				{/if}

				{#if showAttachments}
					<AttachmentsCard
						bind:this={documentAttachments}
						onPendingChange={(count: number) => (pendingDocumentCount = count)}
						entityType="quote"
						entityId={quoteId}
						{currentUserId}
						title="Attachments"
						surface="section"
						kind="documents"
						includeIds={clientDocumentIds}
					/>
				{/if}

				{#if showImages}
					<AttachmentsCard
						bind:this={imageAttachments}
						onPendingChange={(count: number) => (pendingImageCount = count)}
						entityType="quote"
						entityId={quoteId}
						{currentUserId}
						title="Images"
						surface="section"
						kind="images"
						includeIds={clientImageIds}
					/>
				{/if}

				{#if showClientMessage}<SectionBlock
						title="Client message"
						icon={messageIcon}
						level={2}
						form={editingClientMessage}
					>
						{#snippet actions()}
							{#if editable && !editingClientMessage}
								<PencilButton
									onclick={() => {
										clientMessageDraft = saved.version?.client_message ?? '';
										editingClientMessage = true;
									}}
									label="Edit the client message"
								/>
							{:else if clientMessageChanged}
								<Badge size="small" status="warning">Unsaved</Badge>
							{/if}
						{/snippet}

						{#if editingClientMessage}
							<Textarea
								id="quote-client-message"
								label="A short note to the client, under the pricing"
								rows={4}
								maxlength={5000}
								bind:value={clientMessageDraft}
							/>
						{:else if saved.version?.client_message}
							<p class="quote-detail__copy">{saved.version.client_message}</p>
						{:else}
							<EmptyState
								icon={messageIcon}
								title="No client message"
								description="Add a short note the client reads after the pricing."
							/>
						{/if}
					</SectionBlock>{/if}

				<SectionBlock
					title="Contract disclaimer"
					icon={fileTextIcon}
					level={2}
					form={editingDisclaimer}
				>
					{#snippet actions()}
						{#if editable && !editingDisclaimer}
							<PencilButton
								onclick={() => {
									disclaimerDraft = saved.version?.contract_disclaimer ?? '';
									editingDisclaimer = true;
								}}
								label="Edit the contract disclaimer"
							/>
						{:else if disclaimerChanged}
							<Badge size="small" status="warning">Unsaved</Badge>
						{/if}
					{/snippet}

					{#if editingDisclaimer}
						<Textarea
							id="quote-disclaimer"
							label="What the client is agreeing to when they approve this quote"
							rows={5}
							maxlength={5000}
							bind:value={disclaimerDraft}
						/>
					{:else if saved.version?.contract_disclaimer}
						<p class="quote-detail__disclaimer">{saved.version.contract_disclaimer}</p>
					{:else}
						<EmptyState
							icon={fileTextIcon}
							title="No contract disclaimer"
							description="Add the terms the client agrees to when they approve this quote."
						/>
					{/if}
				</SectionBlock>
			{/snippet}

			{#snippet rail()}
				{#if showHistory}
					<RailCard title="Quote history" icon={clockIcon}>
						{#snippet actions()}
							<Button size="small" variant="tertiary" onclick={() => (showHistory = false)}>
								Close
							</Button>
						{/snippet}
						<ActivityFeed entityType="quote" entityId={quoteId} {currentUserId} />
					</RailCard>
				{/if}

				<QuoteSummaryCard
					subtotalMinor={saved.can_see_price ? (saved.version?.subtotal_minor ?? 0) : null}
					discountMinor={saved.version?.discount_minor ?? 0}
					taxMinor={saved.version?.tax_minor ?? 0}
					totalMinor={saved.version?.total_minor ?? null}
					discountLabel={saved.version?.discount_name ?? null}
					taxLabel={saved.version?.tax_name ?? null}
					costMinor={saved.can_see_cost ? (saved.version?.cost_minor ?? null) : null}
					profitMinor={saved.can_see_cost ? (saved.version?.profit_minor ?? null) : null}
					marginBasisPoints={saved.can_see_cost
						? (saved.version?.margin_basis_points ?? null)
						: null}
					currencyCode={saved.version?.currency_code ?? saved.quote.currency_code}
				/>

				<QuoteDiscountCard
					{quoteId}
					revision={saved.version?.revision ?? 0}
					name={saved.version?.discount_name ?? null}
					type={saved.version?.discount_type ?? null}
					value={saved.version?.discount_value ?? null}
					discountMinor={saved.can_see_price ? (saved.version?.discount_minor ?? 0) : null}
					currencyCode={saved.version?.currency_code ?? saved.quote.currency_code}
					{editable}
					canSeePrice={saved.can_see_price}
					onSaved={refreshQuote}
				/>

				<QuoteTaxCard
					{quoteId}
					revision={saved.version?.revision ?? 0}
					propertyId={saved.quote.property_id}
					taxSource={saved.version?.tax_source ?? 'not_configured'}
					rateId={saved.version?.tax_rate_id ?? null}
					name={saved.version?.tax_name ?? null}
					rateBasisPoints={saved.version?.tax_rate_basis_points ?? 0}
					taxMinor={saved.can_see_price ? (saved.version?.tax_minor ?? 0) : null}
					currencyCode={saved.version?.currency_code ?? saved.quote.currency_code}
					{editable}
					canSeePrice={saved.can_see_price}
					canManageTaxes={saved.can_manage_taxes}
					onSaved={refreshQuote}
				/>

				<QuoteDepositCard
					{quoteId}
					revision={saved.version?.revision ?? 0}
					depositType={saved.version?.deposit_type ?? null}
					scheduleItems={saved.deposit_schedule_items}
					depositRequiredMinor={saved.can_see_price
						? (saved.version?.deposit_required_minor ?? 0)
						: null}
					depositEvents={saved.deposit_events}
					totalMinor={saved.can_see_price ? (saved.version?.total_minor ?? 0) : 0}
					currencyCode={saved.version?.currency_code ?? saved.quote.currency_code}
					{editable}
					canSeePrice={saved.can_see_price}
					canRecordDeposit={saved.can_record_deposit}
					hasPublishedVersion={Boolean(saved.quote.current_published_version_id)}
					onSaved={refreshQuote}
				/>

				<RailCard title="Notes" icon={notesIcon} count={notesQuery.data?.length}>
					<NotesPanel
						entityType="quote"
						entityId={quoteId}
						canManage={saved.can_edit}
						{currentUserId}
						pending={notePending}
						onChange={(next: NoteChange[]) => (notePending = next)}
					/>
				</RailCard>
			{/snippet}
		</RecordDetailLayout>

		{#if collectingSignature}
			<CollectSignatureDialog
				open
				clientName={saved.quote.client?.display_name ?? saved.version?.client_display_name ?? null}
				saving={lifecycleSaving}
				onClose={() => (collectingSignature = false)}
				onCollect={collectSignature}
			/>
		{/if}

		{#if quoteEmailOpen}
			<QuoteEmailDialog
				open
				{quoteId}
				quote={saved}
				onClose={() => (quoteEmailOpen = false)}
				onQueued={async () => {
					await refreshQuote();
					toast.success('Email sent');
				}}
			/>
		{/if}

		{#if archivingApproved}
			<ConfirmDialog
				open
				title="Archive this quote?"
				confirmLabel="Archive"
				loading={lifecycleSaving}
				confirmDisabled={!archiveReason.trim()}
				onConfirm={confirmArchiveApproved}
				onClose={() => (archivingApproved = false)}
			>
				<p>The client already approved this quote. Say why it's being filed away.</p>
				<Textarea
					id="quote-archive-reason"
					label="Reason"
					rows={3}
					maxlength={500}
					bind:value={archiveReason}
				/>
			</ConfirmDialog>
		{/if}

		{#if deletingQuote}
			<ConfirmDialog
				open
				title="Delete this quote?"
				tone="critical"
				confirmLabel="Delete quote"
				destructive
				loading={lifecycleSaving}
				onConfirm={confirmDelete}
				onClose={() => (deletingQuote = false)}
			>
				<p>
					“{saved.quote.title}” will be removed for good, along with its number. This cannot be
					undone.
				</p>
			</ConfirmDialog>
		{/if}
	{/if}
</PageContainer>

<style lang="scss">
	.quote-signature {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
	}

	/* White behind the ink on purpose: the drawing is a dark-ink PNG with a transparent background, so a
	 * dark theme would otherwise hand back a signature nobody can see. */
	.quote-signature__image {
		align-self: flex-start;
		max-width: 320px;
		max-height: 140px;
		padding: var(--space-small);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: #ffffff;
	}

	.quote-signature__typed {
		margin: 0;
		color: var(--color-heading);
		font-size: var(--typography--fontSize-largest);
		font-family: 'Segoe Script', 'Brush Script MT', cursive;
	}

	.quote-signature__meta {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.quote-detail__disclaimer,
	.quote-detail__copy {
		margin: 0;
		color: var(--color-text);
		line-height: var(--typography--lineHeight-large);
		white-space: pre-wrap;
	}
</style>
