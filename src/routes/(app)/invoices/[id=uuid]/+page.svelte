<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import PageContainer from '$lib/components/layout/PageContainer.svelte';
	import RecordTrack from '$lib/components/work/RecordTrack.svelte';
	import { RECORD_CHAIN_KEY_PREFIX } from '$lib/work/record-chain';
	import RecordDetailLayout from '$lib/components/layout/RecordDetailLayout.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
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
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import MoneyFeatureCard from '$lib/components/work/MoneyFeatureCard.svelte';
	import InvoiceHistoryCard from '$lib/components/invoices/InvoiceHistoryCard.svelte';
	import RecordDiscountCard from '$lib/components/work/RecordDiscountCard.svelte';
	import RecordTaxCard from '$lib/components/work/RecordTaxCard.svelte';
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
		clientOpenInvoicesKey,
		fetchClientOpenInvoices
	} from '$lib/invoices/api';
	import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
	import { INVOICE_VOID_REASON_LABELS, type InvoiceVoidReason } from '$lib/invoices/lifecycle';
	import type {
		RequestPricingLine,
		RequestPricingLineInput,
		QuoteTaxSource
	} from '$lib/quotes/api';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import creditCardIcon from '@tabler/icons/outline/credit-card.svg?raw';
	import calendarDueIcon from '@tabler/icons/outline/calendar-due.svg?raw';
	import depositIcon from '@tabler/icons/outline/pig-money.svg?raw';
	import eyeIcon from '@tabler/icons/outline/eye.svg?raw';
	import printIcon from '@tabler/icons/outline/printer.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import banIcon from '@tabler/icons/outline/ban.svg?raw';
	import cashOffIcon from '@tabler/icons/outline/cash-off.svg?raw';
	import undoIcon from '@tabler/icons/outline/arrow-back-up.svg?raw';
	import filePencilIcon from '@tabler/icons/outline/file-pencil.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';

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
	function openTermsEditor() {
		termChoiceDraft = currentTermChoice;
		issueDateDraft = currentIssueDate;
		customDueDateDraft = currentCustomDue;
		editingTerms = true;
	}
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

	// The header's facts strip reads shorter than the page's other dates: no year for this year's dates.
	function shortDay(value: string) {
		const date = new Date(`${value}T00:00`);
		return new Intl.DateTimeFormat(undefined, {
			day: 'numeric',
			month: 'short',
			...(date.getFullYear() === new Date().getFullYear() ? {} : { year: 'numeric' })
		}).format(date);
	}
	function shortDateTime(iso: string) {
		const date = new Date(iso);
		return new Intl.DateTimeFormat(undefined, {
			day: 'numeric',
			month: 'short',
			hour: 'numeric',
			minute: '2-digit',
			...(date.getFullYear() === new Date().getFullYear() ? {} : { year: 'numeric' })
		}).format(date);
	}

	// "Net 14" beside the due date, when the invoice follows a named term rather than a hand-picked day.
	const dueTermName = $derived.by(() => {
		if (!saved || saved.invoice.due_date_source === 'custom') return null;
		const name = saved.invoice.payment_term_snapshot?.name;
		return typeof name === 'string' && name ? name : null;
	});

	const headerFacts = $derived([
		...(saved?.progress
			? [
					{
						label: 'Payment stage',
						value: `Payment ${saved.progress.installment_number} \u00b7 ${saved.progress.description}`,
						wrap: true,
						icon: receiptIcon
					}
				]
			: []),
		{
			label: 'Invoice date',
			value: saved ? shortDay(saved.invoice.issue_date) : null,
			icon: calendarIcon
		},
		{
			label: 'Due',
			value: saved
				? `${shortDay(saved.invoice.due_date)}${dueTermName ? ` \u00b7 ${dueTermName}` : ''}`
				: null,
			icon: calendarDueIcon
		},
		// A bill marked as sent by hand has an issue time but no email to name.
		...(saved?.delivery.last_sent
			? [
					{
						label: 'Sent',
						value: shortDateTime(saved.delivery.last_sent.sent_at),
						icon: sendIcon
					}
				]
			: saved?.invoice.issued_at
				? [{ label: 'Issued', value: shortDateTime(saved.invoice.issued_at), icon: checkIcon }]
				: []),
		...(saved?.delivery.views.first_viewed_at
			? [
					{
						label: 'Viewed',
						value: shortDateTime(saved.delivery.views.first_viewed_at),
						icon: eyeIcon
					}
				]
			: [])
	]);

	// --- The balance card and the totals under the lines ----------------------------------------------------
	const settledAway = $derived(Boolean(saved?.invoice.is_replaced) || isVoided);
	// A bill closed as paid owes nothing, even when the money was received outside the ledger.
	const closedPaid = $derived(saved?.invoice.derived_status === 'paid');
	const remainingMinor = $derived(
		settledAway || closedPaid ? 0 : (saved?.money?.remaining_minor ?? 0)
	);
	const paidMinor = $derived(
		settledAway
			? 0
			: closedPaid
				? (saved?.money?.total_minor ?? 0)
				: (saved?.money?.allocated_minor ?? 0)
	);
	const paidPercent = $derived.by(() => {
		const total = saved?.money?.total_minor ?? 0;
		if (total <= 0 || paidMinor <= 0) return 0;
		return Math.min(100, Math.round((paidMinor / total) * 100));
	});

	// How far off the due date is, by the viewer's calendar day. Only worth saying while money is owed.
	const dueChip = $derived.by(() => {
		if (!saved || !isOpenIssued || remainingMinor <= 0) return undefined;
		const today = new Date();
		today.setHours(0, 0, 0, 0);
		const due = new Date(`${saved.invoice.due_date}T00:00`);
		const days = Math.round((due.getTime() - today.getTime()) / 86_400_000);
		if (days === 0) return 'Due today';
		if (days > 0) return `Due in ${days} ${days === 1 ? 'day' : 'days'}`;
		return `${-days} ${days === -1 ? 'day' : 'days'} overdue`;
	});

	// The work dates on the lines, for the products card's quiet line.
	const productsHint = $derived.by(() => {
		const lines = saved?.lines ?? [];
		const count = lines.filter((line) => (line.line_kind ?? 'priced') === 'priced').length;
		if (count === 0) return undefined;
		const days = lines
			.map((line) => line.service_date)
			.filter((day): day is string => Boolean(day))
			.sort();
		const items = `${count} ${count === 1 ? 'item' : 'items'}`;
		if (days.length === 0) return items;
		const first = days[0];
		const last = days[days.length - 1];
		return first === last
			? `${items} \u00b7 work done ${shortDay(first)}`
			: `${items} \u00b7 work done ${shortDay(first)} \u2013 ${shortDay(last)}`;
	});

	const totalRows = $derived.by(() => {
		if (!saved?.money || !canSeePrice) return undefined;
		const money = saved.money;
		const rows = [
			{
				label: isProgress ? 'Due this invoice' : 'Subtotal',
				value: formatMoney(money.subtotal_minor)
			}
		];
		if (money.discount_minor > 0)
			rows.push({
				label: money.discount_name || 'Discount',
				value: `\u2212${formatMoney(money.discount_minor)}`
			});
		if (money.tax_minor > 0 || (money.tax_name && money.tax_rate_basis_points > 0))
			rows.push({ label: money.tax_name || 'Tax', value: formatMoney(money.tax_minor) });
		rows.push({ label: 'Invoice total', value: formatMoney(money.total_minor) });
		return rows;
	});

	// The history button in the header takes the reader to the edits.
	let historyTab = $state('payments');
	function showHistory() {
		historyTab = 'edits';
		const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
		document
			.getElementById('invoice-history')
			?.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
	}

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

	// Where the work was done, for the header's address and its Directions button; the billing address
	// stands in for an invoice that carries no property.
	const siteLine = $derived.by(() => {
		const site = saved?.invoice.service_properties?.[0] as Record<string, unknown> | undefined;
		if (!site) return null;
		const parts = [
			site.address_line1,
			site.address_line2,
			site.city,
			site.state_region,
			site.postal_code
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
				onclick: () => (replaceOpen = true),
				onhover: warmPredecessor
			};
		if (draftEditable && saved.can_send)
			return { label: 'Send invoice', icon: sendIcon, onclick: () => (emailOpen = true) };
		if (canCollect)
			return {
				label: 'Collect payment',
				icon: creditCardIcon,
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
			queryClient.invalidateQueries({ queryKey: RECORD_CHAIN_KEY_PREFIX }),
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

<svelte:head><title>{subject || 'Invoice'} · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->

<PageContainer variant="open">
	{#if invoiceQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading invoice" />
	{:else if invoiceQuery.isError}
		<ErrorState description="That invoice could not be loaded. Refresh and try again." />
	{:else if saved}
		<RecordDetailLayout
			class="invoice-detail"
			cards
			concept
			editing={isEditing}
			dirty={isDirty}
			{saving}
			error={saveError}
			onSave={() => void save()}
			onCancel={discard}
		>
			{#snippet main()}
				<WorkRecordHeader
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
					onHistory={canSeePrice ? showHistory : undefined}
				>
					{#snippet summary()}
						<ClientSummaryCard
							quickContact
							name={saved.client?.company_name || saved.client?.display_name || 'No client'}
							avatarId={saved.client?.id}
							href={clientHref}
							addresses={[{ value: siteLine ?? billingLine, empty: 'No address on this invoice' }]}
							phone={saved.client?.phone}
							email={saved.client?.email}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet track()}
						<RecordTrack
							kind="invoice"
							id={invoiceId}
							clientName={saved.client?.company_name || saved.client?.display_name || undefined}
							clientIsCompany={Boolean(saved.client?.company_name)}
						/>
					{/snippet}
					{#snippet facts()}
						<div class="invoice-detail__facts">
							<RecordFactsList facts={headerFacts} class="invoice-detail__facts-list" />
							{#if editable && !editingTerms}
								<PencilButton
									size="base"
									onclick={openTermsEditor}
									onhover={warmTerms}
									label="Edit the terms and dates"
								/>
							{/if}
						</div>
					{/snippet}
					{#snippet badges()}
						<span class="invoice-detail__number">Invoice #{saved.invoice.invoice_number}</span>
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
									{`Cancellation emailed to ${saved.delivery.void_notice.recipient_email} on ${dateTimeFormat.format(new Date(saved.delivery.void_notice.sent_at))}.`}
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
					currencyCode={saved.invoice.currency_code}
					locale={saved.locale}
					editorTotalLabel="Invoice subtotal"
					saveLabel="Save lines"
					emptyDescription="Add the products and services this invoice bills for."
					hint={productsHint}
					{totalRows}
					flush
					onSave={saveLines}
				/>

				{#if editingTerms}
					<SectionBlock tone="invoice" title="Terms & dates" icon={calendarIcon} level={2}>
						{#snippet actions()}
							{#if termsChanged}
								<Badge size="small" status="warning">Unsaved</Badge>
							{/if}
						{/snippet}

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
					</SectionBlock>
				{/if}

				{#if canSeePrice}
					<InvoiceHistoryCard
						id="invoice-history"
						payments={saved.payment_history ?? []}
						edits={saved.document_history ?? []}
						bind:tab={historyTab}
						{formatMoney}
						{formatDay}
						formatDate={(iso) => dateFormat.format(new Date(iso))}
						formatDateTime={(iso) => dateTimeFormat.format(new Date(iso))}
					/>
				{/if}

				<SectionBlock
					tone="invoice"
					title="Contract disclaimer"
					hint="What the client agrees to by paying this bill"
					level={2}
					class="section-block--flush"
				>
					{#snippet actions()}
						{#if draftEditable && !editingDisclaimer}
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

					<div class="invoice-detail__disclaimer-body">
						{#if editingDisclaimer}
							<Textarea
								id="invoice-disclaimer"
								label="What the customer is agreeing to by paying this bill"
								rows={5}
								maxlength={5000}
								bind:value={disclaimerDraft}
							/>
						{:else if saved.invoice.contract_disclaimer}
							<p class="invoice-detail__disclaimer">{saved.invoice.contract_disclaimer}</p>
						{:else}
							<EmptyState
								icon={fileTextIcon}
								title="No contract disclaimer"
								description="Add the terms the customer agrees to by paying this bill."
							/>
						{/if}
					</div>
				</SectionBlock>
			{/snippet}

			{#snippet rail()}
				{#if canSeePrice && saved.money}
					<MoneyFeatureCard
						record
						icon={receiptIcon}
						eyebrow="Balance due"
						value={formatMoney(remainingMinor)}
						badge={dueChip}
						badgeIcon={calendarDueIcon}
						pill={paidPercent > 0 ? `${paidPercent}% paid` : undefined}
						note={`of the ${formatMoney(saved.money.total_minor)} invoice total`}
						breakdown={saved.money.total_minor > 0 && !settledAway
							? [
									{
										label: 'Paid',
										value: formatMoney(paidMinor),
										share: paidMinor,
										tone: 'success',
										percent: `${paidPercent}%`
									},
									{
										label: 'Balance',
										value: formatMoney(remainingMinor),
										share: remainingMinor,
										tone: 'muted',
										percent: `${100 - paidPercent}%`
									}
								]
							: undefined}
						details={saved.client_balance
							? [
									{
										label: 'Client account balance',
										value: formatMoney(saved.client_balance.account_balance_minor)
									}
								]
							: undefined}
					>
						{#if canAddDeposit && saved.client_balance}
							<p class="invoice-detail__credit-note">
								{formatMoney(saved.client_balance.available_credit_minor)} of this client&rsquo;s money
								is not on any invoice yet.
							</p>
							<!-- The card is dark in the light theme and light in the dark theme, so a white
							     bordered button stands out against it either way. -->
							<div class="invoice-detail__deposit">
								<Button
									variant="secondary"
									onhover={prefetchInvoiceCredit}
									onclick={() => (addDepositOpen = true)}
								>
									{@html depositIcon}
									Add deposit
								</Button>
							</div>
						{/if}
					</MoneyFeatureCard>
				{/if}

				{#if showOnlinePayments}
					<RailCard
						tone="invoice"
						title="Online payment"
						description="Your client can pay from their invoice link"
					>
						<div class="invoice-detail__online">
							<Toggle
								id="invoice-online-partial"
								label="Allow partial payments"
								description="Your client can choose to pay less than the full balance online."
								checked={saved.online_payments.partial_allowed}
								disabled={!saved.can_edit || partialSaving}
								labelSide="start"
								onchange={(allowed) => void togglePartialPayments(allowed)}
							/>
						</div>
					</RailCard>
				{/if}

				<RailCard tone="invoice" title="Discount and tax" flush>
					<RecordDiscountCard
						embedded
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
						embedded
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
				</RailCard>

				<RecordFilesCard
					entityType="invoice"
					entityId={invoiceId}
					recordLabel="this invoice"
					pickerLabel="On this invoice"
					title="Photos and files"
					clientId={saved.client?.id ?? null}
					clientLabel={saved.client?.company_name || saved.client?.display_name || null}
					canManage={editable}
				/>
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

<style lang="scss">
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

	.invoice-detail__number {
		color: var(--color-text--secondary);
		font-size: 12px;
		font-weight: 600;
		letter-spacing: 0.6px;
		text-transform: uppercase;
	}

	// The facts and the terms pencil share the strip's row.
	.invoice-detail__facts {
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.invoice-detail__facts :global(.invoice-detail__facts-list) {
		flex: 1 1 auto;
		flex-wrap: nowrap;
		min-width: 0;
	}
	// A long value wraps under its label rather than being cut off.
	.invoice-detail__facts :global(.record-facts__row) {
		padding-inline: 14px;
	}
	.invoice-detail__facts :global(.record-facts__row:first-child) {
		padding-left: 0;
	}
	.invoice-detail__facts :global(.record-facts__row dt) {
		white-space: nowrap;
	}
	.invoice-detail__facts :global(.record-facts__row dd) {
		overflow: visible;
		white-space: normal;
	}

	.invoice-detail__disclaimer-body {
		padding: 16px 24px 22px;
		border-top: var(--border-base) solid var(--color-border);
	}

	.invoice-detail__credit-note {
		margin: 0;
	}

	.invoice-detail__deposit {
		display: flex;
	}

	.invoice-detail__online {
		padding: 14px 16px;
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle);
	}
	.invoice-detail__online :global(.toggle) {
		display: flex;
		width: 100%;
	}
</style>
