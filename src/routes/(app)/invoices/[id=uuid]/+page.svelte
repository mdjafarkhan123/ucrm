<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import RecordCard from '$lib/components/layout/RecordCard.svelte';
	import Tabs from '$lib/components/ui/Tabs.svelte';
	import TabPanel from '$lib/components/ui/TabPanel.svelte';
	import ProfitFeatureCard from '$lib/components/work/ProfitFeatureCard.svelte';
	import type { RecordFact } from '$lib/components/work/types';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import { recordLifecycle } from '$lib/components/work/record-lifecycle';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteSummaryCard from '$lib/components/quotes/QuoteSummaryCard.svelte';
	import RecordDiscountCard from '$lib/components/work/RecordDiscountCard.svelte';
	import RecordTaxCard from '$lib/components/work/RecordTaxCard.svelte';
	import RecordAdjustmentsCard from '$lib/components/work/RecordAdjustmentsCard.svelte';
	import InvoiceEmailDialog from '$lib/components/invoices/InvoiceEmailDialog.svelte';
	import CollectPaymentDialog from '$lib/components/invoices/CollectPaymentDialog.svelte';
	import AddDepositDialog from '$lib/components/invoices/AddDepositDialog.svelte';
	import InvoiceLifecycleDialog from '$lib/components/invoices/InvoiceLifecycleDialog.svelte';
	import ReplaceInvoiceDialog from '$lib/components/invoices/ReplaceInvoiceDialog.svelte';
	import RecordFilesCard from '$lib/components/files/RecordFilesCard.svelte';
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchInvoice,
		invoiceDetailKey,
		fetchInvoicePaymentTerms,
		invoicePaymentTermsKey,
		saveInvoiceDetails,
		saveInvoiceLines,
		saveInvoiceDiscount,
		saveInvoiceTax,
		saveInvoiceContractDisclaimer,
		issueInvoice,
		queueInvoiceEmail,
		issueInvoiceAccessLink,
		recordInvoicePayment,
		applyInvoiceCredit,
		fetchInvoiceCredit,
		invoiceCreditKey,
		invoiceCreditPrefix,
		sendPaymentReceipt,
		runInvoiceLifecycleAction,
		sendInvoiceVoidNotice,
		startInvoiceReplacement,
		activateInvoiceReplacement,
		deleteInvoice,
		setInvoiceOnlinePartialPayments,
		invoiceCountsKey,
		type InvoiceWriteError,
		type InvoiceLifecycleAction,
		type InvoiceLineInput,
		type ApplyInvoiceCreditInput,
		type RecordInvoicePaymentInput,
		type RecordInvoicePaymentResult,
		type InvoicePaymentHistoryEntry,
		clientOpenInvoicesKey,
		fetchClientOpenInvoices
	} from '$lib/invoices/api';
	import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
	import { diffInvoiceDocument } from '$lib/invoices/document-history';
	import { INVOICE_VOID_REASON_LABELS, type InvoiceVoidReason } from '$lib/invoices/lifecycle';
	import { INVOICE_PAYMENT_METHOD_LABELS } from '$lib/invoices/payment-methods';
	import type {
		RequestPricingLine,
		RequestPricingLineInput,
		QuoteTaxSource
	} from '$lib/quotes/api';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import cashOffIcon from '@tabler/icons/outline/cash-off.svg?raw';
	import undoIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import historyIcon from '@tabler/icons/outline/history.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import filePencilIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import calendarDueIcon from '@tabler/icons/outline/calendar-time.svg?raw';
	import piggyBankIcon from '@tabler/icons/outline/pig-money.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const invoiceId = $derived(page.params.id ?? '');

	const invoiceQuery = createQuery(() => ({
		queryKey: invoiceDetailKey(invoiceId),
		queryFn: () => fetchInvoice(invoiceId),
		enabled: Boolean(invoiceId),
		staleTime: 15_000
	}));
	const saved = $derived(invoiceQuery.data);
	const classic = $derived(page.data.presentation === 'classic');

	// Following Jobber: an issued bill stays editable, including after full payment. The database has always
	// allowed this (`lock_invoice_for_edit` only ever refused voided and replaced), so this just stops the
	// browser being a stricter gate than the server — every edit still goes into `document_history` below.
	const isDraft = $derived(saved?.invoice.derived_status === 'draft');
	const isVoided = $derived(saved?.invoice.derived_status === 'voided');
	const editable = $derived(Boolean(saved?.can_edit) && !isVoided && !saved?.invoice.is_replaced);
	// A handful of moves stay draft-only regardless: issuing (Send/Mark as Sent), deleting, and the contract
	// disclaimer, which `update_invoice_contract_disclaimer` itself refuses once the document is frozen.
	const draftEditable = $derived(
		Boolean(saved?.can_edit) && isDraft && !saved?.invoice.is_replaced
	);
	const canSeePrice = $derived(Boolean(saved?.can_see_price));

	// An issued bill still worth emailing or linking to: it has left draft, has not been voided, and is not a
	// superseded document whose correction or rebill is the one to send instead. Sending a draft is the
	// primary action; resending and the customer link live in the menu for these.
	const issuedAndLive = $derived(
		Boolean(
			saved?.invoice.issued_at &&
			saved.invoice.derived_status !== 'voided' &&
			!saved.invoice.is_replaced
		)
	);

	const subject = $derived(
		saved?.invoice.subject?.trim() || `Invoice #${saved?.invoice.invoice_number ?? ''}`
	);
	// A plain `if`/`return`, not a ternary: checking resolve()'s own route-id type together with
	// `undefined` in one conditional expression is what tips TypeScript over its complexity limit
	// (svelte-check: "union type that is too complex to represent"). A separate return per branch
	// checks each one on its own instead.
	const clientHref = $derived.by((): string | undefined => {
		if (!saved?.client) return undefined;
		return resolve('/(app)/clients/[id=uuid]', { id: saved.client.id });
	});

	// --- Staged edits (subject + terms + disclaimer), saved together by the bottom bar ---------------------
	let editingTitle = $state(false);
	let titleDraft = $state('');
	let editingTerms = $state(false);
	let termChoiceDraft = $state('');
	let issueDateDraft = $state('');
	let customDueDateDraft = $state('');
	let editingDisclaimer = $state(false);
	let disclaimerDraft = $state('');
	let saving = $state(false);
	let saveError = $state('');

	// The invoice's current terms, read back from the frozen snapshot: a custom due date, a named term, or the
	// client/account default the command resolved.
	const currentTermChoice = $derived.by(() => {
		if (!saved) return '';
		if (saved.invoice.due_date_source === 'custom') return 'custom';
		const termId = saved.invoice.payment_term_snapshot?.term_id;
		return typeof termId === 'string' ? termId : '';
	});
	const currentIssueDate = $derived(saved?.invoice.issue_date ?? '');
	const currentCustomDue = $derived(
		saved?.invoice.due_date_source === 'custom' ? (saved?.invoice.due_date ?? '') : ''
	);

	const titleChanged = $derived(
		editingTitle && titleDraft.trim() !== (saved?.invoice.subject?.trim() ?? '')
	);
	const termsChanged = $derived(
		editingTerms &&
			(termChoiceDraft !== currentTermChoice ||
				issueDateDraft !== currentIssueDate ||
				(termChoiceDraft === 'custom' && customDueDateDraft !== currentCustomDue))
	);
	const disclaimerChanged = $derived(
		editingDisclaimer &&
			disclaimerDraft.trim() !== (saved?.invoice.contract_disclaimer?.trim() ?? '')
	);
	const isEditing = $derived(editingTitle || editingTerms || editingDisclaimer);
	const isDirty = $derived(titleChanged || termsChanged || disclaimerChanged);

	// The named terms, loaded only once the terms block is opened; warmed on hover of its pencil.
	const termsQuery = createQuery(() => ({
		queryKey: invoicePaymentTermsKey,
		queryFn: fetchInvoicePaymentTerms,
		enabled: editingTerms,
		staleTime: 60_000
	}));
	const termOptions = $derived([
		{ value: '', label: "Client's default terms" },
		...(termsQuery.data ?? []).map((term) => ({ value: term.id, label: term.name })),
		{ value: 'custom', label: 'Custom due date' }
	]);
	function warmTerms() {
		void queryClient.prefetchQuery({
			queryKey: invoicePaymentTermsKey,
			queryFn: fetchInvoicePaymentTerms
		});
	}

	// --- Formatting -------------------------------------------------------------------------------------
	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	});
	// A `date` column arrives as `YYYY-MM-DD`; `new Date` on that reads it as UTC midnight and shifts the day
	// back one in negative-offset timezones. Appending `T00:00` parses it as local midnight so the calendar
	// date is kept — the same convention JobVisitsSection uses.
	function formatDay(value: string) {
		return dateFormat.format(new Date(`${value}T00:00`));
	}
	const money = $derived(
		new Intl.NumberFormat(saved?.locale ?? 'en-US', {
			style: 'currency',
			currency: saved?.invoice.currency_code ?? 'USD'
		})
	);
	function formatMoney(amountMinor: number | null | undefined) {
		if (typeof amountMinor !== 'number') return '—';
		return money.format(amountMinor / 100);
	}

	const currentTermLabel = $derived.by(() => {
		if (!saved) return '';
		if (saved.invoice.due_date_source === 'custom') return 'Custom due date';
		const name = saved.invoice.payment_term_snapshot?.name;
		return typeof name === 'string' ? name : "Client's default";
	});

	const headerFacts = $derived([
		{ label: 'Invoice #', value: saved ? String(saved.invoice.invoice_number) : null },
		...(saved?.progress
			? [
					{
						label: 'Payment stage',
						value: `Payment ${saved.progress.installment_number} \u00b7 ${saved.progress.description}`,
						wrap: true
					}
				]
			: []),
		{
			label: 'Invoice date',
			value: saved ? formatDay(saved.invoice.issue_date) : null
		},
		{ label: 'Due', value: saved ? formatDay(saved.invoice.due_date) : null },
		...(saved?.invoice.issued_at
			? [{ label: 'Issued', value: dateTimeFormat.format(new Date(saved.invoice.issued_at)) }]
			: []),
		...(saved?.delivery.last_sent
			? [
					{
						label: 'Sent',
						value: dateTimeFormat.format(new Date(saved.delivery.last_sent.sent_at))
					}
				]
			: []),
		...(saved?.delivery.views.first_viewed_at
			? [
					{
						label: 'Viewed',
						value: dateTimeFormat.format(new Date(saved.delivery.views.first_viewed_at))
					}
				]
			: [])
	]);

	// --- Classic header ----------------------------------------------------------------------------------
	// classic.pen "Invoice details · 1440": where the bill came from after its number, the work journey with
	// how long is left to pay, and four dates — invoice date, due, sent and viewed.
	const monthDay = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });
	const shortDateTime = new Intl.DateTimeFormat(undefined, {
		month: 'short',
		day: 'numeric',
		hour: 'numeric',
		minute: '2-digit'
	});
	function shortDay(value: string) {
		return monthDay.format(new Date(`${value}T00:00`));
	}

	const invoiceMeta = $derived.by(() => {
		if (!saved) return undefined;
		const parts = [];
		if (saved.source) parts.push(`From job #${saved.source.job.job_number}`);
		if (saved.progress) parts.push(`Payment ${saved.progress.installment_number}`);
		return parts.length ? parts.join(' \u00b7 ') : undefined;
	});

	// Whole days from today to the due date, in the browser's own calendar.
	const daysToDue = $derived.by(() => {
		if (!saved) return 0;
		const now = new Date();
		const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
		const due = new Date(`${saved.invoice.due_date}T00:00`);
		return Math.round((due.getTime() - today.getTime()) / 86_400_000);
	});
	// Only an open bill counts down; a draft, a paid or a closed one says what it is instead.
	const dueText = $derived.by(() => {
		if (!saved) return '';
		if (saved.invoice.is_replaced) return 'Replaced';
		if (isVoided) return 'Voided';
		if (saved.invoice.derived_status === 'paid') return 'Paid in full';
		if (!isOpenIssued) return `Due ${shortDay(saved.invoice.due_date)}`;
		if (daysToDue === 0) return 'Due today';
		if (daysToDue === 1) return 'Due tomorrow';
		if (daysToDue > 1) return `Due in ${daysToDue} days`;
		return daysToDue === -1 ? '1 day overdue' : `${-daysToDue} days overdue`;
	});

	const classicLifecycle = $derived.by(() => {
		if (!saved) return [];
		const status = INVOICE_STATUS_LABELS[saved.invoice.derived_status];
		const source = saved.source;
		const paid = saved.invoice.derived_status === 'paid';
		const remaining = saved.money?.remaining_minor;
		return recordLifecycle('invoice', isOpenIssued ? dueText : status, {
			...(source?.request_id
				? {
						request: {
							label: 'Request',
							detail: 'Converted',
							complete: true,
							href: resolve('/(app)/requests/[id=uuid]', { id: source.request_id })
						}
					}
				: {}),
			...(source?.quote
				? {
						quote: {
							label: `Quote #${source.quote.quote_number}`,
							detail: source.quote.decided_at
								? `Approved ${monthDay.format(new Date(source.quote.decided_at))}`
								: 'Converted',
							complete: true,
							href: resolve('/(app)/quotes/[id=uuid]', { id: source.quote.id })
						}
					}
				: {}),
			...(source || saved.progress
				? {
						job: {
							label: source ? `Job #${source.job.job_number}` : 'Job',
							detail: saved.progress?.description ?? 'Invoiced',
							complete: true,
							href: resolve('/(app)/jobs/[id=uuid]', {
								id: source?.job.id ?? saved.progress!.job_id
							})
						}
					}
				: {}),
			paid: paid
				? { label: 'Paid', detail: 'Paid in full', complete: true }
				: {
						label: 'Paid',
						detail:
							isOpenIssued && typeof remaining === 'number'
								? `${formatMoney(remaining)} left`
								: undefined
					}
		});
	});

	// A bill due the day it is dated says so; otherwise the date, with a named term beside it ("Oct 20 · Net
	// 14"). A custom date or the client's default has no short name worth repeating.
	const dueFact = $derived.by(() => {
		if (!saved) return '';
		if (saved.invoice.due_date === saved.invoice.issue_date) return 'On receipt';
		const day = shortDay(saved.invoice.due_date);
		const name = saved.invoice.payment_term_snapshot?.name;
		return saved.invoice.due_date_source !== 'custom' && typeof name === 'string' && name
			? `${day} \u00b7 ${name}`
			: day;
	});

	const classicFacts = $derived.by<RecordFact[]>(() => {
		if (!saved) return [];
		return [
			{
				label: 'Invoice date',
				value: shortDay(saved.invoice.issue_date),
				icon: calendarIcon
			},
			{
				label: 'Due',
				value: dueFact,
				icon: calendarDueIcon,
				tone: saved.invoice.derived_status === 'past_due' ? 'waiting' : 'neutral'
			},
			{
				label: 'Sent',
				value: saved.delivery.last_sent
					? shortDateTime.format(new Date(saved.delivery.last_sent.sent_at))
					: null,
				empty: saved.invoice.issued_at ? 'Marked as sent' : 'Not sent yet',
				icon: sendIcon,
				tone: 'neutral'
			},
			{
				label: 'Viewed',
				value: saved.delivery.views.first_viewed_at
					? shortDateTime.format(new Date(saved.delivery.views.first_viewed_at))
					: null,
				empty: 'Not viewed yet',
				icon: eyeIcon,
				tone: 'neutral'
			}
		];
	});

	// --- Classic Balance card and History ----------------------------------------------------------------
	const balanceFigures = $derived.by(() => {
		const money = saved?.money;
		if (!money) return null;
		const closed = Boolean(saved?.invoice.is_replaced) || isVoided;
		const total = money.total_minor;
		const paidMinor = closed ? 0 : money.allocated_minor;
		const owed = closed ? 0 : money.remaining_minor;
		const paidShare = total > 0 ? Math.min(1, paidMinor / total) : 0;
		const paidPercent = Math.round(paidShare * 100);
		// A voided or replaced bill owes nothing, so the card says why instead of drawing a split.
		const closedNote = saved?.invoice.is_replaced
			? 'Replaced \u2014 the newer invoice carries the balance'
			: isVoided
				? 'Voided \u2014 nothing is owed on this invoice'
				: null;
		return { total, paidMinor, owed, paidShare, paidPercent, closedNote };
	});

	// What the payments on this bill add up to: applied money less anything taken back off it.
	const paymentsTotal = $derived(
		(saved?.payment_history ?? []).reduce(
			(sum, entry) => sum + (entry.entry_type === 'unapplied' ? -1 : 1) * entry.amount_minor,
			0
		)
	);
	let historyTab = $state('payments');
	const historyTabs = $derived([
		{
			value: 'payments',
			label: 'Payments',
			count: saved?.payment_history?.length ? formatMoney(paymentsTotal) : 0
		},
		{ value: 'edits', label: 'Edits', count: saved?.document_history?.length ?? 0 }
	]);

	function showHistoryCard() {
		document
			.getElementById('invoice-history')
			?.scrollIntoView({ behavior: 'smooth', block: 'start' });
	}

	const clientFirstName = $derived(
		(saved?.client?.company_name || saved?.client?.display_name || '').trim().split(/\s+/)[0] ||
			'Your client'
	);

	// A billing line from the frozen snapshot, read defensively — it is display-only and the shape comes from
	// the database's own jsonb, never edited here.
	const billingLine = $derived.by(() => {
		const snapshot = saved?.invoice.billing_address_snapshot as Record<string, unknown> | null;
		if (!snapshot) return null;
		const parts = [
			snapshot.address_line1,
			snapshot.address_line2,
			snapshot.city,
			snapshot.state_region,
			snapshot.postal_code
		].filter((part): part is string => typeof part === 'string' && part.length > 0);
		return parts.length ? parts.join(', ') : null;
	});

	const clientMenuItems = $derived(
		saved?.client
			? [
					{
						label: 'View client profile',
						onSelect: () => void goto(resolve('/(app)/clients/[id=uuid]', { id: saved.client!.id }))
					}
				]
			: []
	);

	// The client's view of this invoice, in its own tab, with our sidebar left behind. `print` asks that tab
	// to open the print dialog as soon as it has drawn, so `Print or save PDF` is one press rather than a
	// page and then an instruction — the same as quotes.
	function openCustomerView(print = false) {
		if (!invoiceId) return;
		const path = resolve('/(app)/invoices/[id=uuid]/preview', { id: invoiceId });
		window.open(print ? `${path}?print=1` : path, '_blank', 'noopener');
	}

	// --- Correcting an issued bill / rebilling a voided one (D3, D4, D6) ---------------------------------
	// A correction or rebill starts as a draft copy; it replaces the original only when activated, from its
	// own page, through the Replace dialog. Until then it cannot be sent or paid on its own.
	const isReplacementDraft = $derived(isDraft && Boolean(saved?.invoice.predecessor_invoice_id));
	// The database also refuses a written-off or by-hand-closed bill ("undo that first"); the menu leaves the
	// move out rather than offer one that can only fail.
	const canCorrect = $derived(
		Boolean(saved?.can_create) &&
			issuedAndLive &&
			!saved?.invoice.written_off_at &&
			!saved?.invoice.marked_received_at
	);
	const canRebill = $derived(Boolean(saved?.can_create) && isVoided && !saved?.invoice.is_replaced);

	let replacementStarting = $state(false);

	async function startReplacement(action: 'correct' | 'rebill') {
		if (!saved || replacementStarting) return;
		replacementStarting = true;
		try {
			const { invoice_id } = await startInvoiceReplacement(
				invoiceId,
				action === 'correct' ? { action, expected_revision: saved.invoice.revision } : { action }
			);
			await queryClient.invalidateQueries({ queryKey: ['invoices', 'list'] });
			await goto(resolve('/(app)/invoices/[id=uuid]', { id: invoice_id }));
		} catch (caught) {
			toast.error((caught as InvoiceWriteError).message ?? 'That correction could not be started.');
		} finally {
			replacementStarting = false;
		}
	}

	// The bill this draft replaces: its number for the banner, and its totals for the Replace dialog.
	const predecessorId = $derived(saved?.invoice.predecessor_invoice_id ?? null);
	let replaceOpen = $state(false);
	const predecessorQuery = createQuery(() => ({
		queryKey: invoiceDetailKey(predecessorId ?? ''),
		queryFn: () => fetchInvoice(predecessorId!),
		enabled: Boolean(predecessorId) && replaceOpen,
		staleTime: 15_000
	}));
	const predecessor = $derived(predecessorQuery.data);

	function warmPredecessor() {
		if (!predecessorId) return;
		void queryClient.prefetchQuery({
			queryKey: invoiceDetailKey(predecessorId),
			queryFn: () => fetchInvoice(predecessorId),
			staleTime: 15_000
		});
	}

	async function confirmReplace(method: 'sent' | 'marked_sent', differenceMinor: number) {
		if (!saved) return;
		const result = await activateInvoiceReplacement(invoiceId, {
			expected_revision: saved.invoice.revision,
			previewed_difference_minor: differenceMinor,
			method,
			idempotency_key: crypto.randomUUID(),
			request_hash: fingerprint({ id: invoiceId, action: 'activate', method, differenceMinor })
		});
		let emailed = method === 'sent';
		if (emailed) {
			try {
				await queueInvoiceEmail(invoiceId, crypto.randomUUID());
			} catch (cause) {
				emailed = false;
				toast.error(
					`Invoice replaced, but the email was not sent: ${(cause as InvoiceWriteError).message}`
				);
			}
		}
		await Promise.all([
			refreshInvoice(),
			queryClient.invalidateQueries({ queryKey: ['invoices', 'detail'] }),
			queryClient.invalidateQueries({ queryKey: ['payments'] })
		]);
		toast.success(
			`Invoice #${result.predecessor_invoice_number} replaced${emailed ? ' · client emailed' : ''}`
		);
	}

	// One primary action follows state, per the behavior contract: Send for a draft still waiting to go out;
	// Collect Payment once it is issued and still owes money; nothing forced once it is closed. A draft can
	// still take money (D1 — Save-and-Collect), but that path is Jobber's create-flow shortcut, not this
	// screen's ongoing primary action, so Send wins here whenever the draft can still be sent.
	type PrimaryAction = {
		label: string;
		icon?: string;
		loading?: boolean;
		onclick: () => void;
		onhover?: () => void;
	};
	const canCollect = $derived(
		Boolean(
			saved?.can_record_payment &&
			canSeePrice &&
			issuedAndLive &&
			(saved?.money?.remaining_minor ?? 0) > 0
		)
	);
	const primaryAction = $derived.by<PrimaryAction | undefined>(() => {
		if (!saved) return undefined;
		if (isReplacementDraft && draftEditable && saved.can_send)
			return {
				label: 'Replace invoice',
				icon: classic ? copyIcon : undefined,
				onclick: () => (replaceOpen = true),
				onhover: warmPredecessor
			};
		if (draftEditable && saved.can_send)
			return {
				label: 'Send invoice',
				icon: classic ? sendIcon : undefined,
				onclick: () => (emailOpen = true)
			};
		if (canCollect)
			return {
				label: 'Collect payment',
				icon: classic ? creditCardIcon : undefined,
				onclick: () => (collectPaymentOpen = true),
				onhover: warmOpenInvoices
			};
		return undefined;
	});

	// The supported close/correction transitions, each gated on the bill's live status plus its own permission.
	// An open issued bill can be voided or written off as bad debt; correction moves show only from the state
	// they undo. Historical status-only closures may be reopened but no new ones can be created. Every command re-checks all of this and
	// void additionally refuses while ordinary payments are still on the bill (D2) — that refusal comes back
	// into the dialog.
	const isOpenIssued = $derived(
		saved?.invoice.derived_status === 'awaiting_payment' ||
			saved?.invoice.derived_status === 'past_due'
	);
	// A progress bill is one stage of a job's payment schedule. The job owns every amount on it — the stage
	// value, and the split of that value across the job's lines — so this screen shows them and edits none
	// of them. Correcting one goes through the correction chain, the same route the void refusal points at.
	const progress = $derived(saved?.progress ?? null);
	const isProgress = $derived(progress !== null);
	const progressLockedMessage =
		'This invoice bills one stage of the job\u2019s payment schedule, so the job owns its amounts. ' +
		'Change the schedule on the job, or correct this invoice.';

	// Void is never offered on a progress bill. `void_invoice` refuses one outright — cancelling a single
	// stage of a payment schedule would leave the schedule describing money nobody is being asked for — so
	// the menu leaves the move out rather than offering a button that can only fail.
	const canVoid = $derived(Boolean(saved?.can_void) && isOpenIssued && !isProgress);
	const canWriteOff = $derived(Boolean(saved?.can_bad_debt) && isOpenIssued);
	const canRestoreWriteOff = $derived(
		Boolean(saved?.can_bad_debt) && saved?.invoice.derived_status === 'bad_debt'
	);
	const canReopen = $derived(
		Boolean(saved?.can_record_payment) && Boolean(saved?.invoice.marked_received_at)
	);

	// Following Jobber, the menu never offers a move the bill cannot make from where it is. Resend and the
	// customer link show only for an issued, live bill; Mark as Sent only for a draft. Preview and Print are
	// offered in every status — checking a bill before sending it is the whole point of a preview. The
	// close/reopen moves sit at the bottom of the list.
	const invoiceMenuItems = $derived.by(() => {
		if (!saved) return [];
		const items = [];
		if (issuedAndLive && saved.can_send)
			items.push({ label: 'Resend invoice', icon: sendIcon, onSelect: () => (emailOpen = true) });
		if (issuedAndLive && saved.can_send)
			items.push({
				label: 'Copy customer link',
				icon: linkIcon,
				disabled: linkSaving,
				onSelect: () => void copyClientLink()
			});
		if (draftEditable && saved.can_send && !isReplacementDraft)
			items.push({
				label: 'Mark as Sent',
				icon: checkIcon,
				disabled: marking,
				onSelect: () => void markAsSent()
			});
		items.push({ label: 'Preview as client', icon: eyeIcon, onSelect: () => openCustomerView() });
		items.push({
			label: 'Print or save PDF',
			icon: printIcon,
			onSelect: () => openCustomerView(true)
		});

		if (canCorrect)
			items.push({
				label: 'Correct invoice',
				icon: filePencilIcon,
				disabled: replacementStarting,
				onSelect: () => void startReplacement('correct')
			});
		if (canRebill)
			items.push({
				label: 'Rebill invoice',
				icon: copyIcon,
				disabled: replacementStarting,
				onSelect: () => void startReplacement('rebill')
			});

		if (canReopen)
			items.push({
				label: 'Reopen invoice',
				icon: undoIcon,
				onSelect: () => (lifecycleMode = 'reopen')
			});
		if (canWriteOff)
			items.push({
				label: 'Write off balance',
				icon: cashOffIcon,
				destructive: true,
				onSelect: () => (lifecycleMode = 'write_off')
			});
		if (canRestoreWriteOff)
			items.push({
				label: 'Undo write-off',
				icon: undoIcon,
				onSelect: () => (lifecycleMode = 'restore_write_off')
			});
		if (canVoid)
			items.push({
				label: 'Void invoice',
				icon: banIcon,
				destructive: true,
				onSelect: () => (lifecycleMode = 'void')
			});

		return items;
	});

	// The read-only lines, mapped into the shape the shared pricing block draws.
	const invoiceLines = $derived<RequestPricingLine[]>(
		(saved?.lines ?? []).map((line) => ({
			...line,
			catalog_item_id: null,
			is_labor: false,
			category: line.category ?? 'service',
			quantity: line.quantity ?? 0,
			unit_price_minor: line.unit_price_minor ?? 0,
			unit_cost_minor: 0,
			line_total_minor: line.line_total_minor ?? 0,
			line_cost_total_minor: 0,
			image_file_id: null
		}))
	);

	// --- Saving details ----------------------------------------------------------------------------------
	async function refreshInvoice() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: invoiceDetailKey(invoiceId) }),
			queryClient.invalidateQueries({ queryKey: ['invoices', 'list'] }),
			queryClient.invalidateQueries({ queryKey: invoiceCountsKey }),
			// Adding a deposit spends the client's spare money, and a payment recorded here may create some.
			queryClient.invalidateQueries({ queryKey: invoiceCreditPrefix })
		]);
	}

	function discard() {
		editingTitle = false;
		titleDraft = '';
		editingTerms = false;
		editingDisclaimer = false;
		disclaimerDraft = '';
		saveError = '';
	}

	async function save() {
		if (!saved || saving || !isDirty) return;
		saving = true;
		saveError = '';

		const choice = editingTerms ? termChoiceDraft : currentTermChoice;
		const customDue = editingTerms ? customDueDateDraft : currentCustomDue;
		if (choice === 'custom' && !customDue) {
			saveError = 'Pick the date this invoice is due.';
			saving = false;
			return;
		}

		try {
			// Everything below shares one draft revision, so these go one after another and each carries the
			// revision the one before it handed back — firing them together would make the second a stale write.
			let revision = saved.invoice.revision;

			if (titleChanged || termsChanged) {
				const result = await saveInvoiceDetails(invoiceId, revision, {
					subject: titleChanged ? titleDraft.trim() : saved.invoice.subject,
					issue_date: (editingTerms ? issueDateDraft : currentIssueDate) || null,
					payment_term_id: choice && choice !== 'custom' ? choice : null,
					custom_due_date: choice === 'custom' ? customDue : null
				});
				revision = result.revision;
			}

			if (disclaimerChanged) {
				const result = await saveInvoiceContractDisclaimer(
					invoiceId,
					revision,
					disclaimerDraft.trim() || null
				);
				revision = result.revision;
			}

			discard();
			await refreshInvoice();
			toast.success('Invoice saved');
		} catch (caught) {
			const writeError = caught as InvoiceWriteError;
			if (writeError.reason === 'stale') {
				discard();
				await refreshInvoice();
				saveError = 'Someone else changed this invoice. The latest version is now on screen.';
			} else {
				saveError =
					writeError.fieldErrors?.form ?? writeError.message ?? 'Those changes could not be saved.';
			}
		} finally {
			saving = false;
		}
	}

	// --- Lines -------------------------------------------------------------------------------------------
	async function saveLines(expectedRevision: number, lines: RequestPricingLineInput[]) {
		const payload: InvoiceLineInput[] = lines
			.filter((line) => (line.line_kind ?? 'priced') === 'priced')
			.map((line, index) => ({
				position: index,
				category: line.category,
				source_catalog_item_id: line.catalog_item_id,
				name: line.name,
				description: line.description ?? null,
				unit_label: line.unit_label ?? null,
				quantity: line.quantity,
				unit_price_minor: line.unit_price_minor,
				is_taxable: line.is_taxable ?? true,
				service_date: line.service_date ?? null
			}));
		await saveInvoiceLines(invoiceId, expectedRevision, payload);
		await refreshInvoice();
		toast.success('Lines saved');
	}

	// --- Lifecycle: Mark as Sent / Delete ----------------------------------------------------------------
	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	let marking = $state(false);
	async function markAsSent() {
		if (!saved || marking) return;
		marking = true;
		try {
			await issueInvoice(
				invoiceId,
				saved.invoice.revision,
				'marked_sent',
				crypto.randomUUID(),
				fingerprint({ id: invoiceId, action: 'marked_sent', revision: saved.invoice.revision })
			);
			await refreshInvoice();
			toast.success('Invoice marked as sent');
		} catch (caught) {
			toast.error((caught as InvoiceWriteError).message ?? 'That invoice could not be issued.');
		} finally {
			marking = false;
		}
	}

	// --- Sending & the customer link ---------------------------------------------------------------------
	// The dialog is presentational; the page owns the send because a draft is issued first (issue_invoice,
	// method 'sent') and only then delivered, the same lifecycle Mark as Sent already runs here. An issued
	// bill skips the issue step and only re-queues the email, so one confirm handler covers Send and Resend.
	let emailOpen = $state(false);
	let sending = $state(false);
	let sendError = $state('');

	async function confirmSend() {
		if (!saved || sending) return;
		sending = true;
		sendError = '';
		try {
			if (isDraft) {
				await issueInvoice(
					invoiceId,
					saved.invoice.revision,
					'sent',
					crypto.randomUUID(),
					fingerprint({ id: invoiceId, action: 'sent', revision: saved.invoice.revision })
				);
			}
			await queueInvoiceEmail(invoiceId, crypto.randomUUID());
			emailOpen = false;
			toast.success('Invoice sent');
		} catch (caught) {
			sendError = (caught as InvoiceWriteError).message ?? 'That invoice could not be sent.';
		} finally {
			// Always re-read: if issuing a draft succeeded but the email failed, the bill is now issued (same
			// as Mark as Sent) and the dialog turns into a plain Resend, so a retry no longer re-issues.
			await refreshInvoice();
			sending = false;
		}
	}

	// --- Collect Payment ---------------------------------------------------------------------------------
	let collectPaymentOpen = $state(false);

	function saveInvoicePayment({
		reason: _reason,
		...payload
	}: Omit<RecordInvoicePaymentInput, 'client_id'> & { reason: string | null }) {
		if (!saved?.client) throw new Error('This invoice has no client to record payment against.');
		return recordInvoicePayment(invoiceId, { client_id: saved.client.id, ...payload });
	}

	// The client's other unpaid bills, which the Collect dialog lists; started when its button is reached.
	function warmOpenInvoices() {
		const clientId = saved?.client?.id;
		if (!clientId) return;
		void queryClient.prefetchQuery({
			queryKey: clientOpenInvoicesKey(clientId),
			queryFn: () => fetchClientOpenInvoices(clientId, invoiceId),
			staleTime: 15_000
		});
	}

	// The money is already recorded by the time this runs, so the receipt is reported separately from it: a
	// receipt that could not be queued is a delivery problem, never a reason to make a recorded payment look
	// like it failed. Same two-entry-point shape as Jobber, whose New Payment screen offers exactly this.
	async function onPaymentSaved(result: RecordInvoicePaymentResult, emailReceipt: boolean) {
		// One payment can settle several of the client's bills, so every open bill and bill page is stale.
		await Promise.all([
			refreshInvoice(),
			queryClient.invalidateQueries({ queryKey: ['invoices', 'detail'] }),
			queryClient.invalidateQueries({ queryKey: ['invoices', 'client-open'] })
		]);
		if (!emailReceipt) {
			toast.success('Payment recorded');
			return;
		}
		try {
			await sendPaymentReceipt(result.payment_event_id, crypto.randomUUID());
			toast.success('Payment recorded — receipt emailed');
		} catch (cause) {
			toast.success('Payment recorded');
			toast.error((cause as InvoiceWriteError).message);
		}
	}

	// --- Add deposit (put the client's spare money on this invoice) ----------------------------------------
	let addDepositOpen = $state(false);

	// Offered only when there is spare money to spend on a bill that still owes. Jobber's row is always there;
	// ours would open an empty list, so it waits until the client actually has credit.
	const canAddDeposit = $derived(
		canCollect && Boolean(saved?.client) && (saved?.client_balance?.available_credit_minor ?? 0) > 0
	);

	// The list is behind the button, so it loads when the pointer or keyboard reaches it, and stays cached.
	function prefetchInvoiceCredit() {
		if (!saved?.client) return;
		const clientId = saved.client.id;
		void queryClient.prefetchQuery({
			queryKey: invoiceCreditKey(clientId),
			queryFn: () => fetchInvoiceCredit(invoiceId, clientId),
			staleTime: 15_000
		});
	}

	function saveInvoiceCredit(input: ApplyInvoiceCreditInput) {
		return applyInvoiceCredit(invoiceId, input);
	}

	async function onDepositAdded() {
		await refreshInvoice();
		toast.success('Deposit added');
	}

	// --- Lifecycle: void / bad debt / historical closure correction --------------------------------------
	// The dialog owns the fields and the retry fingerprint; the page owns the write and what follows. Which
	// menu item was pressed decides the mode and, after it lands, the toast.
	let lifecycleMode = $state<InvoiceLifecycleAction['action'] | null>(null);

	const LIFECYCLE_DONE: Record<InvoiceLifecycleAction['action'], string> = {
		void: 'Invoice voided',
		write_off: 'Balance written off',
		restore_write_off: 'Write-off undone',
		reopen: 'Invoice reopened'
	};

	function saveLifecycle(
		action: InvoiceLifecycleAction,
		idempotencyKey: string,
		requestHash: string
	) {
		return runInvoiceLifecycleAction(invoiceId, action, idempotencyKey, requestHash);
	}

	async function onLifecycleSaved({ notifyClient }: { notifyClient: boolean }) {
		const done = lifecycleMode ? LIFECYCLE_DONE[lifecycleMode] : 'Invoice updated';
		if (!notifyClient) {
			await refreshInvoice();
			toast.success(done);
			return;
		}
		// The void has already happened, so a failed email is reported on its own and never undoes it. The
		// banner then offers the send again.
		try {
			await sendInvoiceVoidNotice(invoiceId);
			toast.success(`${done} · client emailed`);
		} catch (cause) {
			toast.error(`${done}, but the email was not sent: ${voidNoticeFailure(cause)}`);
		}
		await refreshInvoice();
	}

	// Where the cancellation email would go: only for a bill the client was given (sent or marked sent) and
	// who has an email address (D9).
	const voidNoticeEmail = $derived(
		saved?.invoice.issued_at && saved.client?.email ? saved.client.email : null
	);

	function voidNoticeFailure(cause: unknown) {
		const failure = cause as InvoiceWriteError;
		return failure.fieldErrors?.form ?? failure.message ?? 'please try again.';
	}

	// The later send, from the Voided banner, when the dialog's email was skipped or failed.
	let voidNoticeSending = $state(false);

	async function sendVoidNoticeNow() {
		if (voidNoticeSending || !invoiceId) return;
		voidNoticeSending = true;
		try {
			await sendInvoiceVoidNotice(invoiceId);
			await refreshInvoice();
			toast.success('Cancellation email sent');
		} catch (cause) {
			toast.error(voidNoticeFailure(cause));
		} finally {
			voidNoticeSending = false;
		}
	}

	// The void reason / bad-debt note shown as a line under the header once the bill is in that state.
	const closureBanner = $derived.by(() => {
		if (!saved) return null;
		if (saved.invoice.voided_at) {
			const reason = saved.invoice.void_reason
				? INVOICE_VOID_REASON_LABELS[saved.invoice.void_reason as InvoiceVoidReason]
				: null;
			return {
				tone: 'voided' as const,
				title: `Voided on ${dateTimeFormat.format(new Date(saved.invoice.voided_at))}${
					reason ? ` · ${reason}` : ''
				}`,
				note: saved.invoice.void_note
			};
		}
		if (saved.invoice.written_off_at) {
			return {
				tone: 'bad-debt' as const,
				title: `Written off as bad debt on ${dateTimeFormat.format(
					new Date(saved.invoice.written_off_at)
				)}`,
				note: saved.invoice.write_off_note
			};
		}
		if (saved.invoice.marked_received_at) {
			return {
				tone: 'received' as const,
				title: `Closed as received on ${dateTimeFormat.format(
					new Date(saved.invoice.marked_received_at)
				)}`,
				note: null
			};
		}
		return null;
	});

	// The customer's own link. Nothing is created by looking at a bill, so this press makes the recipient and
	// the door together; pressing it again rotates the old link off, which is what staff mean by "send the
	// link again". The raw URL comes back exactly once, so it goes straight to the clipboard.
	let linkSaving = $state(false);

	async function copyClientLink() {
		if (linkSaving || !invoiceId) return;
		linkSaving = true;
		try {
			const link = await issueInvoiceAccessLink(invoiceId);
			await navigator.clipboard.writeText(link.url);
			toast.success(`Link copied. Send it to ${link.recipient_email}.`);
		} catch (caught) {
			toast.error((caught as InvoiceWriteError).message ?? 'That link could not be created.');
		} finally {
			linkSaving = false;
		}
	}

	// "Allow partial online payments" (Jobber's per-invoice switch, off by default, never on progress bills). It
	// is a setting on how the customer may pay, not part of the bill, so it saves the moment it is flipped.
	const showOnlinePayments = $derived(
		Boolean(saved?.online_payments.offered) &&
			!isProgress &&
			!isVoided &&
			!saved?.invoice.is_replaced &&
			saved?.invoice.derived_status !== 'paid'
	);
	let partialSaving = $state(false);

	async function togglePartialPayments(allowed: boolean) {
		partialSaving = true;
		try {
			await setInvoiceOnlinePartialPayments(invoiceId, allowed);
			await queryClient.invalidateQueries({ queryKey: invoiceDetailKey(invoiceId) });
			toast.success(
				allowed ? 'Partial online payments allowed' : 'Partial online payments turned off'
			);
		} catch (caught) {
			await queryClient.invalidateQueries({ queryKey: invoiceDetailKey(invoiceId) });
			toast.error((caught as InvoiceWriteError).message ?? 'That setting could not be saved.');
		} finally {
			partialSaving = false;
		}
	}

	let deleting = $state(false);
	async function removeDraft() {
		if (!saved || deleting) return;
		deleting = true;
		const invoiceNumber = saved.invoice.invoice_number;
		try {
			await deleteInvoice(
				invoiceId,
				saved.invoice.revision,
				crypto.randomUUID(),
				fingerprint({ id: invoiceId, action: 'delete', revision: saved.invoice.revision })
			);
			// The invoice is gone — drop its detail query rather than refetch a 404, and refresh only the
			// list and counts that still exist. Then leave for the list.
			queryClient.removeQueries({ queryKey: invoiceDetailKey(invoiceId) });
			void queryClient.invalidateQueries({ queryKey: ['invoices', 'list'] });
			void queryClient.invalidateQueries({ queryKey: invoiceCountsKey });
			toast.success(`Invoice #${invoiceNumber} deleted`);
			await goto(resolve('/(app)/invoices'));
		} catch (caught) {
			toast.error((caught as InvoiceWriteError).message ?? 'That invoice could not be deleted.');
		} finally {
			deleting = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#snippet adjustments()}
	{#if saved}
		<RecordAdjustmentsCard>
			<RecordDiscountCard
				revision={saved.invoice.revision}
				name={saved.money?.discount_name ?? null}
				type={saved.money?.discount_type ?? null}
				value={saved.money?.discount_value ?? null}
				discountMinor={canSeePrice ? (saved.money?.discount_minor ?? 0) : null}
				currencyCode={saved.invoice.currency_code}
				locale={saved.locale}
				editable={editable && !isProgress}
				{canSeePrice}
				recordNoun="invoice"
				onSave={(revision, payload) => saveInvoiceDiscount(invoiceId, revision, payload)}
				onSaved={refreshInvoice}
			/>

			<RecordTaxCard
				revision={saved.invoice.revision}
				propertyId={(saved.invoice.service_properties?.[0]?.property_id as string) ?? ''}
				taxSource={(saved.money?.tax_source ?? 'not_configured') as QuoteTaxSource}
				rateId={saved.money?.tax_rate_id ?? null}
				name={saved.money?.tax_name ?? null}
				rateBasisPoints={saved.money?.tax_rate_basis_points ?? 0}
				taxMinor={canSeePrice ? (saved.money?.tax_minor ?? 0) : null}
				currencyCode={saved.invoice.currency_code}
				locale={saved.locale}
				editable={editable && !isProgress}
				{canSeePrice}
				canManageTaxes={false}
				recordNoun="invoice"
				unsetHint="This invoice is not taxed yet."
				onSave={(revision, payload) => saveInvoiceTax(invoiceId, revision, payload)}
				onSaved={refreshInvoice}
			/>
		</RecordAdjustmentsCard>
	{/if}
{/snippet}

{#snippet termsActions()}
	{#if saved && editable && !editingTerms}
		<PencilButton
			onclick={() => {
				termChoiceDraft = currentTermChoice;
				issueDateDraft = currentIssueDate;
				customDueDateDraft = currentCustomDue;
				editingTerms = true;
			}}
			onhover={warmTerms}
			label="Edit the terms and dates"
		/>
	{:else if termsChanged}
		<Badge size="small" status="warning">Unsaved</Badge>
	{/if}
{/snippet}

{#snippet termsEditor()}
	<div class="invoice-detail__terms-edit">
		<CalendarPicker
			id="invoice-issue-date"
			label="Invoice date"
			value={calendarDateFromString(issueDateDraft)}
			onchange={(value) => (issueDateDraft = calendarDateToString(value))}
		/>
		<Select
			id="invoice-terms"
			label="Payment terms"
			bind:value={termChoiceDraft}
			options={termOptions}
		/>
		{#if termChoiceDraft === 'custom'}
			<CalendarPicker
				id="invoice-due-date"
				label="Due date"
				value={calendarDateFromString(customDueDateDraft)}
				minValue={calendarDateFromString(issueDateDraft)}
				onchange={(value) => (customDueDateDraft = calendarDateToString(value))}
			/>
		{/if}
	</div>
{/snippet}

{#snippet disclaimerActions()}
	{#if saved && draftEditable && !editingDisclaimer}
		<PencilButton
			onclick={() => {
				disclaimerDraft = saved.invoice.contract_disclaimer ?? '';
				editingDisclaimer = true;
			}}
			label="Edit the contract disclaimer"
		/>
	{:else if disclaimerChanged}
		<Badge size="small" status="warning">Unsaved</Badge>
	{/if}
{/snippet}

{#snippet disclaimerEditor()}
	<Textarea
		id="invoice-disclaimer"
		label="What the customer is agreeing to by paying this bill"
		rows={5}
		maxlength={5000}
		bind:value={disclaimerDraft}
	/>
{/snippet}

{#snippet partialToggle()}
	{#if saved}
		<Toggle
			id="invoice-online-partial"
			label="Allow partial payments"
			description="Your client can choose to pay less than the full balance online."
			checked={saved.online_payments.partial_allowed}
			disabled={!saved.can_edit || partialSaving}
			labelSide="start"
			onchange={(allowed) => void togglePartialPayments(allowed)}
		/>
	{/if}
{/snippet}

{#snippet paymentLabel(entry: InvoicePaymentHistoryEntry)}
	{entry.entry_type === 'unapplied'
		? 'Payment removed'
		: entry.source === 'deposit'
			? 'Deposit applied'
			: 'Payment received'}
	{#if entry.method}
		&middot; {INVOICE_PAYMENT_METHOD_LABELS[entry.method]}
	{/if}
{/snippet}

{#snippet paymentMeta(entry: InvoicePaymentHistoryEntry)}
	{entry.payment_date
		? formatDay(entry.payment_date)
		: dateFormat.format(new Date(entry.created_at))}
	{#if entry.reference}
		&middot; Ref {entry.reference}
	{/if}
{/snippet}

<svelte:head><title>{subject || 'Invoice'} · Contractor CRM</title></svelte:head>

<PageContainer>
	{#if invoiceQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading invoice" />
	{:else if invoiceQuery.isError}
		<ErrorState description="That invoice could not be loaded. Refresh and try again." />
	{:else if saved}
		<RecordDetailLayout
			class="invoice-detail"
			editing={isEditing}
			dirty={isDirty}
			{saving}
			error={saveError}
			onSave={() => void save()}
			onCancel={discard}
		>
			{#snippet main()}
				<WorkRecordHeader
					lifecycle={classic
						? classicLifecycle
						: recordLifecycle('invoice', INVOICE_STATUS_LABELS[saved.invoice.derived_status], {
								...(saved.progress
									? {
											job: {
												label: 'Job',
												detail: saved.progress.description,
												href: resolve('/(app)/jobs/[id=uuid]', { id: saved.progress.job_id })
											}
										}
									: {}),
								...(saved.invoice.derived_status === 'paid'
									? { paid: { label: 'Paid', detail: 'Paid in full', complete: true } }
									: {})
							})}
					recordNumber={saved.invoice.invoice_number}
					meta={classic ? invoiceMeta : undefined}
					onHistory={classic && canSeePrice ? showHistoryCard : undefined}
					icon={receiptIcon}
					recordType="Invoice"
					menuItems={invoiceMenuItems}
					title={subject}
					titleLabel="Invoice subject"
					statusLabel={INVOICE_STATUS_LABELS[saved.invoice.derived_status]}
					statusTone={INVOICE_STATUS_TONES[saved.invoice.derived_status]}
					onEditTitle={editable
						? () => {
								titleDraft = saved.invoice.subject;
								editingTitle = true;
							}
						: undefined}
					{editingTitle}
					bind:titleDraft
					{primaryAction}
				>
					{#snippet summary()}
						<ClientSummaryCard
							clientId={saved.client?.id}
							email={page.data.presentation === 'classic' ? saved.client?.email : undefined}
							name={saved.client?.company_name || saved.client?.display_name || 'No client'}
							href={clientHref}
							addresses={[{ value: billingLine, empty: 'No billing address on this invoice' }]}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet facts()}
						{#if !classic}
							<RecordFactsList facts={headerFacts} />
						{:else if editingTerms}
							<div class="invoice-terms">
								<div class="invoice-terms__head">
									<h2 class="invoice-terms__title">Terms and dates</h2>
									{@render termsActions()}
								</div>
								{@render termsEditor()}
							</div>
						{:else}
							<div class="invoice-facts">
								<RecordFactsList facts={classicFacts} />
								{#if editable}<span class="invoice-facts__edit">{@render termsActions()}</span>{/if}
							</div>
						{/if}
					{/snippet}
					{#snippet badges()}
						{#if draftEditable}
							<Button
								size="small"
								variant="tertiary"
								variation="destructive"
								onclick={() => void removeDraft()}
								loading={deleting}
							>
								Delete draft
							</Button>
						{/if}
					{/snippet}
				</WorkRecordHeader>

				{#if closureBanner}
					<div
						class="invoice-detail__closure"
						class:invoice-detail__closure--voided={closureBanner.tone === 'voided'}
						class:invoice-detail__closure--bad-debt={closureBanner.tone === 'bad-debt'}
						class:invoice-detail__closure--received={closureBanner.tone === 'received'}
						role="note"
					>
						<p class="invoice-detail__closure-title">{closureBanner.title}</p>
						{#if closureBanner.note}
							<p class="invoice-detail__closure-note">{closureBanner.note}</p>
						{/if}
						{#if closureBanner.tone === 'voided'}
							{#if saved.delivery.void_notice}
								<p class="invoice-detail__closure-note">
									Cancellation emailed to {saved.delivery.void_notice.recipient_email} on
									{dateTimeFormat.format(new Date(saved.delivery.void_notice.sent_at))}.
								</p>
							{:else if voidNoticeEmail && saved.can_void}
								<div class="invoice-detail__closure-action">
									<p class="invoice-detail__closure-note">The client has not been told.</p>
									<Button
										variant="secondary"
										size="small"
										loading={voidNoticeSending}
										onclick={() => void sendVoidNoticeNow()}
									>
										Email cancellation
									</Button>
								</div>
							{/if}
						{/if}
					</div>
				{/if}

				{#if isReplacementDraft}
					<div class="invoice-detail__closure invoice-detail__closure--replacement" role="note">
						<p class="invoice-detail__closure-title">
							{saved.invoice.replacement_kind === 'rebill' ? 'Rebill' : 'Correction'} of an earlier invoice
						</p>
						<div class="invoice-detail__closure-action">
							<p class="invoice-detail__closure-note">
								Edit it here, then press Replace invoice. Until then the original is still the bill.
							</p>
							{#if predecessorId}
								<a
									class="invoice-detail__closure-link"
									href={resolve('/(app)/invoices/[id=uuid]', { id: predecessorId })}
								>
									Open the original
								</a>
							{/if}
						</div>
					</div>
				{:else if saved.invoice.is_replaced && saved.invoice.replaced_by_invoice_id}
					<div class="invoice-detail__closure invoice-detail__closure--replacement" role="note">
						<p class="invoice-detail__closure-title">
							Replaced on {dateTimeFormat.format(new Date(saved.invoice.replaced_at ?? ''))}
						</p>
						<a
							class="invoice-detail__closure-link"
							href={resolve('/(app)/invoices/[id=uuid]', {
								id: saved.invoice.replaced_by_invoice_id
							})}
						>
							Open the invoice that replaced it
						</a>
					</div>
				{/if}

				<ProductsAndServicesBlock
					lines={invoiceLines}
					revision={saved.invoice.revision}
					editable={editable && canSeePrice && !isProgress}
					showPrices={canSeePrice}
					showServiceDate
					progressColumn={isProgress}
					lockedMessage={isProgress ? progressLockedMessage : ''}
					subtotalMinor={canSeePrice ? (saved.money?.subtotal_minor ?? 0) : null}
					totals={{
						discountMinor: saved.money?.discount_minor ?? 0,
						discountLabel: saved.money?.discount_name ?? null,
						taxMinor: saved.money?.tax_minor ?? 0,
						taxLabel: saved.money?.tax_name ?? null,
						totalMinor: saved.money?.total_minor ?? null,
						totalLabel: 'Invoice total'
					}}
					currencyCode={saved.invoice.currency_code}
					locale={saved.locale}
					editorTotalLabel="Invoice subtotal"
					saveLabel="Save lines"
					emptyDescription="Add the products and services this invoice bills for."
					onSave={saveLines}
				/>

				{#if classic}
					{#if canSeePrice}
						<RecordCard
							title="History"
							subtitle="Payments and changes on this invoice"
							id="invoice-history"
							class="invoice-history"
						>
							<Tabs
								tabs={historyTabs}
								bind:value={historyTab}
								label="Invoice history"
								variant="card"
							>
								<TabPanel value="payments">
									{#if saved.payment_history?.length}
										<ul class="invoice-history__list">
											{#each saved.payment_history as entry (entry.id)}
												{@const tone =
													entry.entry_type === 'unapplied'
														? 'rose'
														: entry.source === 'deposit'
															? 'blue'
															: 'green'}
												<li class="invoice-history__row">
													<span
														class={`invoice-history__icon invoice-history__icon--${tone}`}
														aria-hidden="true"
														>{@html entry.entry_type === 'unapplied'
															? undoIcon
															: entry.source === 'deposit'
																? piggyBankIcon
																: cashIcon}</span
													>
													<div class="invoice-history__main">
														{#if entry.payment_event_id}
															<a
																class="invoice-history__label invoice-history__label--link"
																href={resolve('/(app)/payments/[id=uuid]', {
																	id: entry.payment_event_id
																})}>{@render paymentLabel(entry)}</a
															>
														{:else}
															<span class="invoice-history__label"
																>{@render paymentLabel(entry)}</span
															>
														{/if}
														<span class="invoice-history__meta">{@render paymentMeta(entry)}</span>
													</div>
													<span
														class="invoice-history__amount"
														class:invoice-history__amount--negative={entry.entry_type ===
															'unapplied'}
													>
														{entry.entry_type === 'unapplied' ? '−' : ''}{formatMoney(
															entry.amount_minor
														)}
													</span>
												</li>
											{/each}
										</ul>
									{:else}
										<p class="invoice-history__empty">
											No payments yet. Payments recorded against this invoice show up here.
										</p>
									{/if}
								</TabPanel>
								<TabPanel value="edits">
									{#if saved.document_history?.length}
										<ul class="invoice-history__list">
											{#each saved.document_history as entry (entry.id)}
												{@const changes = diffInvoiceDocument(entry.before, entry.after, {
													formatMoney,
													formatDay
												})}
												<li class="invoice-history__row invoice-history__row--edit">
													<span
														class="invoice-history__icon invoice-history__icon--neutral"
														aria-hidden="true">{@html filePencilIcon}</span
													>
													<div class="invoice-history__main">
														<span class="invoice-history__label">
															{entry.actor_name ?? 'Someone'} edited the invoice
														</span>
														<span class="invoice-history__meta">
															{dateTimeFormat.format(new Date(entry.created_at))}
															{#if changes.length}
																&middot; {changes.length} change{changes.length === 1 ? '' : 's'}
															{/if}
														</span>
														{#if changes.length}
															<ul class="invoice-history__changes">
																{#each changes as change (change.label)}
																	<li>
																		<span class="invoice-history__field">{change.label}</span>
																		<span>{change.before} &rarr; {change.after}</span>
																	</li>
																{/each}
															</ul>
														{/if}
													</div>
												</li>
											{/each}
										</ul>
									{:else}
										<p class="invoice-history__empty">
											No edits yet. Changes made after the invoice is sent show up here.
										</p>
									{/if}
								</TabPanel>
							</Tabs>
						</RecordCard>
					{/if}

					<RecordCard
						title="Contract disclaimer"
						subtitle="What the client agrees to by paying this bill"
						id="invoice-disclaimer-card"
					>
						{#snippet actions()}{@render disclaimerActions()}{/snippet}
						<div class="invoice-record__row">
							{#if editingDisclaimer}
								{@render disclaimerEditor()}
							{:else if saved.invoice.contract_disclaimer}
								<p class="invoice-detail__disclaimer">{saved.invoice.contract_disclaimer}</p>
							{:else}
								<p class="invoice-record__empty">No contract disclaimer on this invoice.</p>
							{/if}
						</div>
					</RecordCard>
				{:else}
					<SectionBlock title="Terms & dates" icon={calendarIcon} level={2} form={editingTerms}>
						{#snippet actions()}{@render termsActions()}{/snippet}

						{#if editingTerms}
							{@render termsEditor()}
						{:else}
							<dl class="invoice-detail__terms">
								<div class="invoice-detail__term">
									<dt>Invoice date</dt>
									<dd>{formatDay(saved.invoice.issue_date)}</dd>
								</div>
								<div class="invoice-detail__term">
									<dt>Due</dt>
									<dd>{formatDay(saved.invoice.due_date)}</dd>
								</div>
								<div class="invoice-detail__term">
									<dt>Terms</dt>
									<dd>{currentTermLabel}</dd>
								</div>
							</dl>
						{/if}
					</SectionBlock>

					<SectionBlock
						title="Contract disclaimer"
						icon={fileTextIcon}
						level={2}
						form={editingDisclaimer}
					>
						{#snippet actions()}{@render disclaimerActions()}{/snippet}

						{#if editingDisclaimer}
							{@render disclaimerEditor()}
						{:else if saved.invoice.contract_disclaimer}
							<p class="invoice-detail__disclaimer">{saved.invoice.contract_disclaimer}</p>
						{:else}
							<EmptyState
								icon={fileTextIcon}
								title="No contract disclaimer"
								description="Add the terms the customer agrees to by paying this bill."
							/>
						{/if}
					</SectionBlock>

					{#if canSeePrice}
						<SectionBlock title="Financial history" icon={cashIcon} level={2}>
							{#if saved.payment_history?.length}
								<ul class="invoice-detail__history">
									{#each saved.payment_history as entry (entry.id)}
										<li class="invoice-detail__history-row">
											<div class="invoice-detail__history-main">
												<!-- A recorded payment has a screen of its own; a reused quote deposit does
											     not, so only the payment rows are links. -->
												{#if entry.payment_event_id}
													<a
														class="invoice-detail__history-label invoice-detail__history-link"
														href={resolve('/(app)/payments/[id=uuid]', {
															id: entry.payment_event_id
														})}
													>
														{@render paymentLabel(entry)}
													</a>
												{:else}
													<span class="invoice-detail__history-label">
														{@render paymentLabel(entry)}
													</span>
												{/if}
												<span class="invoice-detail__history-meta">
													{@render paymentMeta(entry)}
												</span>
											</div>
											<span
												class="invoice-detail__history-amount"
												class:invoice-detail__history-amount--negative={entry.entry_type ===
													'unapplied'}
											>
												{entry.entry_type === 'unapplied' ? '−' : ''}{formatMoney(
													entry.amount_minor
												)}
											</span>
										</li>
									{/each}
								</ul>
							{:else}
								<EmptyState
									icon={cashIcon}
									title="No payments yet"
									description="Payments recorded against this invoice will show up here."
								/>
							{/if}
						</SectionBlock>
					{/if}

					{#if canSeePrice && saved.document_history?.length}
						<SectionBlock title="Invoice history" icon={historyIcon} level={2}>
							<ul class="invoice-detail__revisions">
								{#each saved.document_history as entry (entry.id)}
									{@const changes = diffInvoiceDocument(entry.before, entry.after, {
										formatMoney,
										formatDay
									})}
									<li class="invoice-detail__revision">
										<div class="invoice-detail__revision-head">
											<span class="invoice-detail__revision-actor">
												{entry.actor_name ?? 'Someone'} edited the invoice
											</span>
											<span class="invoice-detail__revision-meta">
												{dateTimeFormat.format(new Date(entry.created_at))}
												{#if changes.length}
													&middot; {changes.length} change{changes.length === 1 ? '' : 's'}
												{/if}
											</span>
										</div>
										{#if changes.length}
											<ul class="invoice-detail__revision-changes">
												{#each changes as change (change.label)}
													<li>
														<span class="invoice-detail__revision-field">{change.label}</span>
														<span class="invoice-detail__revision-diff">
															{change.before} &rarr; {change.after}
														</span>
													</li>
												{/each}
											</ul>
										{/if}
									</li>
								{/each}
							</ul>
						</SectionBlock>
					{/if}
				{/if}
			{/snippet}

			{#snippet rail()}
				{#if classic}
					{#if canSeePrice && balanceFigures && saved.money}
						<ProfitFeatureCard
							label="Balance due"
							eyebrow="Balance due"
							value={formatMoney(balanceFigures.owed)}
							chip={{ label: dueText, icon: calendarDueIcon }}
							pillIcon={checkIcon}
							margin={!balanceFigures.closedNote && balanceFigures.paidMinor > 0
								? `${balanceFigures.paidPercent}% paid`
								: null}
							subline={balanceFigures.closedNote ??
								`of the ${formatMoney(balanceFigures.total)} invoice total`}
							showBar={!balanceFigures.closedNote}
							parts={balanceFigures.closedNote
								? []
								: [
										{
											key: 'paid',
											label: 'Paid',
											amount: formatMoney(balanceFigures.paidMinor),
											share: balanceFigures.paidShare,
											percent: balanceFigures.paidPercent,
											tone: 'green'
										},
										{
											key: 'balance',
											label: 'Balance',
											amount: formatMoney(balanceFigures.owed),
											share: 1 - balanceFigures.paidShare,
											percent: 100 - balanceFigures.paidPercent,
											tone: 'muted'
										}
									]}
						>
							{#if saved.client_balance || canAddDeposit}
								<div class="invoice-balance__footer">
									{#if saved.client_balance}
										<div class="invoice-balance__row">
											<span>Client account balance</span>
											<strong>{formatMoney(saved.client_balance.account_balance_minor)}</strong>
										</div>
									{/if}
									{#if canAddDeposit && saved.client_balance}
										<div class="invoice-balance__credit">
											<p>
												{formatMoney(saved.client_balance.available_credit_minor)} of {clientFirstName}&rsquo;s
												money is not on any invoice yet.
											</p>
											<button
												type="button"
												class="invoice-balance__deposit"
												onmouseenter={prefetchInvoiceCredit}
												onfocus={prefetchInvoiceCredit}
												onclick={() => (addDepositOpen = true)}
											>
												<span aria-hidden="true">{@html piggyBankIcon}</span>Add deposit
											</button>
										</div>
									{/if}
								</div>
							{/if}
						</ProfitFeatureCard>
					{/if}

					{#if showOnlinePayments}
						<RecordCard
							title="Online payment"
							subtitle={`${clientFirstName} can pay from the invoice link`}
							size="rail"
							id="invoice-online-payment"
						>
							<div class="invoice-online">{@render partialToggle()}</div>
						</RecordCard>
					{/if}

					{@render adjustments()}

					<RecordFilesCard
						entityType="invoice"
						entityId={invoiceId}
						recordLabel="this invoice"
						pickerLabel="On this invoice"
						clientId={saved.client?.id ?? null}
						clientLabel={saved.client?.company_name || saved.client?.display_name || null}
						canManage={editable}
						title="Photos and files"
						look="record"
					/>
				{:else}
					<QuoteSummaryCard
						title="Invoice total"
						subtotalMinor={canSeePrice ? (saved.money?.subtotal_minor ?? 0) : null}
						discountMinor={saved.money?.discount_minor ?? 0}
						taxMinor={saved.money?.tax_minor ?? 0}
						totalMinor={saved.money?.total_minor ?? null}
						discountLabel={saved.money?.discount_name ?? null}
						taxLabel={saved.money?.tax_name ?? null}
						currencyCode={saved.invoice.currency_code}
						locale={saved.locale}
					/>

					{#if canSeePrice && saved.money}
						<RailCard title="Balance" icon={cashIcon}>
							<dl class="invoice-detail__balance">
								<div class="invoice-detail__balance-row">
									<dt>Invoice balance</dt>
									<dd class="invoice-detail__balance-amount">
										{formatMoney(
											saved.invoice.is_replaced || isVoided ? 0 : saved.money.remaining_minor
										)}
									</dd>
								</div>
								{#if saved.client_balance}
									<div class="invoice-detail__balance-row">
										<dt>Client account balance</dt>
										<dd>{formatMoney(saved.client_balance.account_balance_minor)}</dd>
									</div>
								{/if}
							</dl>
							{#if canAddDeposit && saved.client_balance}
								<div class="invoice-detail__credit">
									<p class="invoice-detail__credit-note">
										{formatMoney(saved.client_balance.available_credit_minor)} of this client&rsquo;s
										money is not on any invoice yet.
									</p>
									<Button
										variant="secondary"
										size="small"
										onhover={prefetchInvoiceCredit}
										onclick={() => (addDepositOpen = true)}
									>
										Add deposit
									</Button>
								</div>
							{/if}
						</RailCard>
					{/if}

					{#if showOnlinePayments}
						<RailCard title="Online payment" icon={creditCardIcon}>
							{@render partialToggle()}
						</RailCard>
					{/if}

					{@render adjustments()}

					<RecordFilesCard
						entityType="invoice"
						entityId={invoiceId}
						recordLabel="this invoice"
						pickerLabel="On this invoice"
						clientId={saved.client?.id ?? null}
						clientLabel={saved.client?.company_name || saved.client?.display_name || null}
						canManage={editable}
					/>
				{/if}
			{/snippet}
		</RecordDetailLayout>

		{#if emailOpen}
			<InvoiceEmailDialog
				open
				recipient={saved.client?.email ?? null}
				invoiceNumber={saved.invoice.invoice_number}
				{isDraft}
				{sending}
				error={sendError}
				onClose={() => (emailOpen = false)}
				onConfirm={() => void confirmSend()}
			/>
		{/if}

		{#if collectPaymentOpen && saved.money}
			<CollectPaymentDialog
				open
				clientId={saved.client?.id ?? ''}
				pinned={[
					{
						id: invoiceId,
						number: saved.invoice.invoice_number,
						detail: 'This invoice',
						owedMinor: saved.money.remaining_minor
					}
				]}
				currencyCode={saved.invoice.currency_code}
				locale={saved.locale}
				onClose={() => (collectPaymentOpen = false)}
				onSave={saveInvoicePayment}
				onSaved={onPaymentSaved}
			/>
		{/if}

		{#if addDepositOpen && saved.money && saved.client}
			<AddDepositDialog
				open
				{invoiceId}
				invoiceNumber={saved.invoice.invoice_number}
				clientId={saved.client.id}
				remainingMinor={saved.money.remaining_minor}
				currencyCode={saved.invoice.currency_code}
				locale={saved.locale}
				onClose={() => (addDepositOpen = false)}
				onSave={saveInvoiceCredit}
				onSaved={onDepositAdded}
			/>
		{/if}

		{#if replaceOpen && saved.money}
			<ReplaceInvoiceDialog
				open
				kind={saved.invoice.replacement_kind === 'rebill' ? 'rebill' : 'correction'}
				original={predecessor?.money
					? {
							number: predecessor.invoice.invoice_number,
							totalMinor: predecessor.money.total_minor,
							paidMinor: predecessor.invoice.voided_at ? 0 : predecessor.money.allocated_minor
						}
					: null}
				loadError={predecessorQuery.isError}
				newTotalMinor={saved.money.total_minor}
				currencyCode={saved.invoice.currency_code}
				locale={saved.locale}
				clientEmail={saved.client?.email ?? null}
				onClose={() => (replaceOpen = false)}
				onConfirm={confirmReplace}
			/>
		{/if}

		{#if lifecycleMode}
			<InvoiceLifecycleDialog
				open
				mode={lifecycleMode}
				invoiceNumber={saved.invoice.invoice_number}
				clientEmail={voidNoticeEmail}
				onClose={() => (lifecycleMode = null)}
				onSave={saveLifecycle}
				onSaved={onLifecycleSaved}
			/>
		{/if}
	{/if}
</PageContainer>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.invoice-detail__terms,
	.invoice-detail__balance {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
	}

	.invoice-detail__term,
	.invoice-detail__balance-row {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);

		dt {
			color: var(--color-text--secondary);
		}
		dd {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}
	}

	.invoice-detail__credit {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-small);
		margin-top: var(--space-base);
		padding-top: var(--space-base);
		border-top: var(--border-base) solid var(--color-border);
	}

	.invoice-detail__credit-note {
		margin: 0;
		color: var(--color-text);
		font-size: var(--typography--fontSize-small);
	}

	.invoice-detail__balance-amount {
		font-size: var(--typography--fontSize-large);
	}

	.invoice-detail__terms-edit {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.invoice-detail__disclaimer {
		margin: 0;
		color: var(--color-text);
		line-height: var(--typography--lineHeight-large);
		white-space: pre-wrap;
	}

	.invoice-detail__closure {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-left-width: 3px;
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}

	.invoice-detail__closure--voided {
		border-left-color: var(--color-critical);
	}

	.invoice-detail__closure--replacement {
		border-left-color: var(--color-interactive);
	}

	.invoice-detail__closure-link {
		align-self: flex-start;
		font-weight: 600;
		color: var(--color-interactive);

		&:hover {
			text-decoration: underline;
		}
	}

	.invoice-detail__closure--bad-debt {
		border-left-color: var(--color-warning);
	}

	.invoice-detail__closure--received {
		border-left-color: var(--color-success);
	}

	.invoice-detail__closure-title {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.invoice-detail__closure-action {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small);
	}

	.invoice-detail__closure-note {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-large);
		white-space: pre-wrap;
	}

	.invoice-detail__history {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.invoice-detail__history-row {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.invoice-detail__history-main {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		min-width: 0;
	}

	.invoice-detail__history-label {
		color: var(--color-heading);
		font-weight: 600;
	}

	a.invoice-detail__history-link {
		color: var(--color-interactive);

		&:hover {
			text-decoration: underline;
		}
	}

	.invoice-detail__history-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.invoice-detail__history-amount {
		flex-shrink: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.invoice-detail__history-amount--negative {
		color: var(--color-critical);
	}

	.invoice-detail__revisions {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.invoice-detail__revision {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		padding-bottom: var(--space-base);
		border-bottom: var(--border-base) solid var(--color-border);

		&:last-child {
			padding-bottom: 0;
			border-bottom: none;
		}
	}

	.invoice-detail__revision-head {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.invoice-detail__revision-actor {
		color: var(--color-heading);
		font-weight: 600;
	}

	.invoice-detail__revision-meta {
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.invoice-detail__revision-changes {
		display: flex;
		flex-direction: column;
		gap: var(--space-smaller);
		margin: 0;
		padding: 0;
		list-style: none;

		li {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-smaller);
			font-size: var(--typography--fontSize-small);
		}
	}

	.invoice-detail__revision-field {
		flex-shrink: 0;
		min-width: 6rem;
		color: var(--color-text--secondary);
	}

	.invoice-detail__revision-diff {
		color: var(--color-text);
	}
	// classic.pen "Invoice details · 1440" ------------------------------------------------------------------

	// The header's four dates with the terms pencil at the end of the row.
	.invoice-facts {
		display: flex;
		align-items: center;
		gap: 12px;

		:global(.record-facts) {
			flex: 1 1 auto;
			min-width: 0;
		}

		&__edit {
			flex: 0 0 auto;
		}
	}

	.invoice-terms {
		display: flex;
		flex-direction: column;
		gap: 14px;
		font-family: var(--classic2-font);

		&__head {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
		}

		&__title {
			margin: 0;
			color: var(--classic2-ink);
			font-size: var(--classic2-font-label);
			font-weight: 600;
		}

		.invoice-detail__terms-edit {
			display: grid;
			grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
		}
	}

	.invoice-record {
		&__row {
			padding: 18px 24px 20px;
			border-top: 1px solid var(--classic2-divider);
			font-family: var(--classic2-font);

			.invoice-detail__disclaimer {
				color: var(--classic2-body);
				font-size: var(--classic2-font-body);
				line-height: 1.6;
			}
		}

		&__empty {
			margin: 0;
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-label);
		}
	}

	:global(.invoice-history .tabs__list) {
		border-bottom: 1px solid var(--classic2-divider);
	}

	.invoice-history {
		&__list {
			margin: 0;
			padding: 0;
			list-style: none;
			font-family: var(--classic2-font);
		}

		&__row {
			display: flex;
			align-items: center;
			gap: 14px;
			padding: 14px 24px;

			& + & {
				border-top: 1px solid var(--classic2-divider);
			}

			&--edit {
				align-items: flex-start;
			}
		}

		&__icon {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 36px;
			height: 36px;
			border-radius: 999px;

			:global(svg) {
				width: 17px;
				height: 17px;
			}

			&--green {
				background: var(--classic2-green-tint);
				color: var(--classic2-green);
			}

			&--blue {
				background: var(--classic2-blue-tint);
				color: var(--classic2-blue);
			}

			&--rose {
				background: var(--classic2-rose-tint);
				color: var(--classic2-rose);
			}

			&--neutral {
				background: var(--classic2-surface-soft);
				color: var(--classic2-secondary);
			}
		}

		&__main {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			gap: 3px;
			min-width: 0;
		}

		&__label {
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
			font-weight: 600;

			&--link {
				align-self: flex-start;
				color: var(--classic2-green);
				text-decoration: none;

				&:hover {
					text-decoration: underline;
				}

				&:focus-visible {
					border-radius: 4px;
					outline: 2px solid var(--classic2-green);
					outline-offset: 2px;
				}
			}
		}

		&__meta {
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-label);
		}

		&__amount {
			flex: 0 0 auto;
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
			font-weight: 700;

			&--negative {
				color: var(--classic2-rose);
			}
		}

		&__changes {
			display: flex;
			flex-direction: column;
			gap: 4px;
			margin: 6px 0 0;
			padding: 0;
			list-style: none;
			color: var(--classic2-body);
			font-size: var(--classic2-font-label);

			li {
				display: flex;
				flex-wrap: wrap;
				gap: 6px;
			}
		}

		&__field {
			min-width: 6rem;
			color: var(--classic2-secondary);
		}

		&__empty {
			margin: 0;
			padding: 18px 24px 20px;
			color: var(--classic2-secondary);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-label);
		}
	}

	// The Balance card's footer, on the dark featured card.
	.invoice-balance {
		&__footer {
			display: flex;
			flex-direction: column;
			gap: 12px;
			padding-top: 14px;
			border-top: 1px solid var(--classic2-feature-line);
		}

		&__row {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: 12px;
			font-size: var(--classic2-font-label);

			span {
				color: var(--classic2-feature-label);
				font-weight: 500;
			}

			strong {
				color: var(--classic2-white);
				font-weight: 700;
			}
		}

		&__credit {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: 10px;
			padding: 12px;
			border-radius: 12px;
			background: var(--classic2-feature-chip);

			p {
				margin: 0;
				color: var(--classic2-feature-label);
				font-size: var(--classic2-font-label);
				font-weight: 500;
				line-height: 1.35;
			}
		}

		&__deposit {
			display: inline-flex;
			align-items: center;
			gap: 8px;
			height: 34px;
			padding: 0 14px;
			border: 0;
			border-radius: var(--classic2-radius-control);
			background: var(--classic2-white);
			color: var(--classic2-on-white);
			font-family: var(--classic2-font);
			font-size: var(--classic2-font-label);
			font-weight: 600;
			cursor: pointer;

			span {
				display: inline-flex;
			}

			:global(svg) {
				width: 16px;
				height: 16px;
			}

			&:hover {
				opacity: 0.9;
			}

			&:focus-visible {
				outline: 2px solid var(--classic2-white);
				outline-offset: 2px;
			}
		}
	}

	// The partial-payments switch sits in a soft inset under the card heading.
	.invoice-online {
		margin: 0 20px 20px;
		padding: 14px 16px;
		border-radius: 14px;
		background: var(--classic2-surface-soft);
	}

	// The voided / written-off / replaced notes under the header, as a calm Classic card with a tone edge.
	:global(:root:has(.app-shell[data-presentation='classic'])) .invoice-detail__closure {
		gap: 4px;
		padding: 16px 24px;
		border: 1px solid var(--classic2-border);
		border-left-width: 4px;
		border-radius: var(--classic2-radius-card);
		background: var(--classic2-surface);
		font-family: var(--classic2-font);

		&.invoice-detail__closure--voided {
			border-left-color: var(--classic2-rose);
		}

		&.invoice-detail__closure--bad-debt {
			border-left-color: var(--classic2-amber);
		}

		&.invoice-detail__closure--received {
			border-left-color: var(--classic2-green);
		}

		&.invoice-detail__closure--replacement {
			border-left-color: var(--classic2-blue);
		}

		.invoice-detail__closure-title {
			color: var(--classic2-ink);
			font-size: var(--classic2-font-body);
		}

		.invoice-detail__closure-note {
			color: var(--classic2-secondary);
			font-size: var(--classic2-font-label);
		}

		.invoice-detail__closure-link {
			color: var(--classic2-green);
			font-size: var(--classic2-font-label);
			text-decoration: none;
		}
	}
</style>
