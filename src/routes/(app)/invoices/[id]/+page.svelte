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
	import Badge from '$lib/components/ui/Badge.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteSummaryCard from '$lib/components/quotes/QuoteSummaryCard.svelte';
	import RecordDiscountCard from '$lib/components/work/RecordDiscountCard.svelte';
	import RecordTaxCard from '$lib/components/work/RecordTaxCard.svelte';
	import InvoiceEmailDialog from '$lib/components/invoices/InvoiceEmailDialog.svelte';
	import CollectPaymentDialog from '$lib/components/invoices/CollectPaymentDialog.svelte';
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
		deleteInvoice,
		invoiceCountsKey,
		type InvoiceWriteError,
		type InvoiceLineInput
	} from '$lib/invoices/api';
	import { INVOICE_STATUS_LABELS, INVOICE_STATUS_TONES } from '$lib/invoices/statuses';
	import {
		INVOICE_PAYMENT_METHOD_LABELS,
		type InvoicePaymentMethod
	} from '$lib/invoices/payment-methods';
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

	// A draft is the only state this part edits in place; issuing freezes the document, and editing an issued
	// bill is a later part's concern. So the pencils, the line editor and the discount/tax cards all turn on
	// only for a draft the reader may change.
	const isDraft = $derived(saved?.invoice.derived_status === 'draft');
	const editable = $derived(Boolean(saved?.can_edit) && isDraft && !saved?.invoice.is_replaced);
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
						onSelect: () => void goto(resolve('/(app)/clients/[id]', { id: saved.client!.id }))
					}
				]
			: []
	);

	// The client's view of this invoice, in its own tab, with our sidebar left behind. `print` asks that tab
	// to open the print dialog as soon as it has drawn, so `Print or save PDF` is one press rather than a
	// page and then an instruction — the same as quotes.
	function openCustomerView(print = false) {
		if (!invoiceId) return;
		const path = resolve('/(app)/invoices/[id]/preview', { id: invoiceId });
		window.open(print ? `${path}?print=1` : path, '_blank', 'noopener');
	}

	// One primary action follows state, per the behavior contract: Send for a draft still waiting to go out;
	// Collect Payment once it is issued and still owes money; nothing forced once it is closed. A draft can
	// still take money (D1 — Save-and-Collect), but that path is Jobber's create-flow shortcut, not this
	// screen's ongoing primary action, so Send wins here whenever the draft can still be sent.
	type PrimaryAction = { label: string; loading?: boolean; onclick: () => void };
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
		if (editable && saved.can_send)
			return { label: 'Send invoice', onclick: () => (emailOpen = true) };
		if (canCollect) return { label: 'Collect payment', onclick: () => (collectPaymentOpen = true) };
		return undefined;
	});

	// Following Jobber, the menu never offers a move the bill cannot make from where it is. Resend and the
	// customer link show only for an issued, live bill; Mark as Sent only for a draft. Preview and Print are
	// offered in every status — checking a bill before sending it is the whole point of a preview.
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
		if (editable && saved.can_send)
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
			image_attachment_id: null
		}))
	);

	// --- Saving details ----------------------------------------------------------------------------------
	async function refreshInvoice() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: invoiceDetailKey(invoiceId) }),
			queryClient.invalidateQueries({ queryKey: ['invoices', 'list'] }),
			queryClient.invalidateQueries({ queryKey: invoiceCountsKey })
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
				is_taxable: line.is_taxable ?? true
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

	// --- Collect Payment (single invoice) ----------------------------------------------------------------
	let collectPaymentOpen = $state(false);

	function saveInvoicePayment(payload: {
		amount_minor: number;
		method: InvoicePaymentMethod;
		payment_date: string;
		reference: string | null;
		note: string | null;
		idempotency_key: string;
		request_hash: string;
	}) {
		if (!saved?.client) throw new Error('This invoice has no client to record payment against.');
		return recordInvoicePayment(invoiceId, { client_id: saved.client.id, ...payload });
	}

	async function onPaymentSaved() {
		await refreshInvoice();
		toast.success('Payment recorded');
	}

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
							name={saved.client?.company_name || saved.client?.display_name || 'No client'}
							href={saved.client
								? resolve('/(app)/clients/[id]', { id: saved.client.id })
								: undefined}
							addresses={[{ value: billingLine, empty: 'No billing address on this invoice' }]}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet facts()}<RecordFactsList facts={headerFacts} />{/snippet}
					{#snippet badges()}
						{#if editable}
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

				<ProductsAndServicesBlock
					lines={invoiceLines}
					revision={saved.invoice.revision}
					editable={editable && canSeePrice}
					showPrices={canSeePrice}
					subtotalMinor={canSeePrice ? (saved.money?.subtotal_minor ?? 0) : null}
					currencyCode={saved.invoice.currency_code}
					locale={saved.locale}
					editorTotalLabel="Invoice subtotal"
					saveLabel="Save lines"
					emptyDescription="Add the products and services this invoice bills for."
					onSave={saveLines}
				/>

				<SectionBlock title="Terms & dates" icon={calendarIcon} level={2} form={editingTerms}>
					{#snippet actions()}
						{#if editable && !editingTerms}
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

					{#if editingTerms}
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
					{#snippet actions()}
						{#if editable && !editingDisclaimer}
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
				</SectionBlock>

				{#if canSeePrice}
					<SectionBlock title="Financial history" icon={cashIcon} level={2}>
						{#if saved.payment_history?.length}
							<ul class="invoice-detail__history">
								{#each saved.payment_history as entry (entry.id)}
									<li class="invoice-detail__history-row">
										<div class="invoice-detail__history-main">
											<span class="invoice-detail__history-label">
												{entry.entry_type === 'unapplied'
													? 'Payment removed'
													: entry.source === 'deposit'
														? 'Deposit applied'
														: 'Payment received'}
												{#if entry.method}
													&middot; {INVOICE_PAYMENT_METHOD_LABELS[entry.method]}
												{/if}
											</span>
											<span class="invoice-detail__history-meta">
												{entry.payment_date
													? formatDay(entry.payment_date)
													: dateFormat.format(new Date(entry.created_at))}
												{#if entry.reference}
													&middot; Ref {entry.reference}
												{/if}
											</span>
										</div>
										<span
											class="invoice-detail__history-amount"
											class:invoice-detail__history-amount--negative={entry.entry_type ===
												'unapplied'}
										>
											{entry.entry_type === 'unapplied' ? '−' : ''}{formatMoney(entry.amount_minor)}
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
			{/snippet}

			{#snippet rail()}
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
									{formatMoney(saved.money.remaining_minor)}
								</dd>
							</div>
							{#if saved.client_balance}
								<div class="invoice-detail__balance-row">
									<dt>Client account balance</dt>
									<dd>{formatMoney(saved.client_balance.account_balance_minor)}</dd>
								</div>
							{/if}
						</dl>
					</RailCard>
				{/if}

				<RecordDiscountCard
					revision={saved.invoice.revision}
					name={saved.money?.discount_name ?? null}
					type={saved.money?.discount_type ?? null}
					value={saved.money?.discount_value ?? null}
					discountMinor={canSeePrice ? (saved.money?.discount_minor ?? 0) : null}
					currencyCode={saved.invoice.currency_code}
					locale={saved.locale}
					{editable}
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
					{editable}
					{canSeePrice}
					canManageTaxes={false}
					recordNoun="invoice"
					unsetHint="This invoice is not taxed yet."
					onSave={(revision, payload) => saveInvoiceTax(invoiceId, revision, payload)}
					onSaved={refreshInvoice}
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
				invoiceNumber={saved.invoice.invoice_number}
				remainingMinor={saved.money.remaining_minor}
				currencyCode={saved.invoice.currency_code}
				locale={saved.locale}
				onClose={() => (collectPaymentOpen = false)}
				onSave={saveInvoicePayment}
				onSaved={onPaymentSaved}
			/>
		{/if}
	{/if}
</PageContainer>

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
</style>
