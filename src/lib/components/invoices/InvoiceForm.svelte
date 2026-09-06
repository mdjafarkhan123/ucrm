<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import PrimaryInfoCard from '$lib/components/work/PrimaryInfoCard.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteSummaryCard from '$lib/components/quotes/QuoteSummaryCard.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { calendarDateFromString, calendarDateToString } from '$lib/components/ui/date-time';
	import { fetchClient, clientDetailKey, type ClientListItem } from '$lib/clients/api';
	import {
		createInvoice,
		fetchInvoicePaymentTerms,
		invoicePaymentTermsKey,
		type InvoiceLineInput,
		type InvoiceSourceInput,
		type InvoiceWriteError
	} from '$lib/invoices/api';
	import type { RequestPricingLine, RequestPricingLineInput } from '$lib/quotes/api';
	import { firstLineProblem } from '$lib/quotes/lines';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';

	// Billing a customer directly, without a job behind it. The invoice number, its snapshots and all its money
	// come from the database the moment it saves, so nothing here guesses at them. The whole thing — the bill,
	// its lines and its frozen snapshots — is written in one command, so there is nothing half-made to clean up
	// if it fails.
	// Billing a job fills the same form rather than opening a second one: the contractor still edits lines,
	// terms and subject before saving. The only thing the seed adds is `sources` — the work this bill claims,
	// which travels with the save so the draft and its claims are written together.
	let {
		onSaved,
		onCancel,
		currencyCode = 'USD',
		locale = 'en-US',
		seed = null
	}: {
		onSaved: (invoice: { id: string; number: number }) => void;
		onCancel: () => void;
		currencyCode?: string;
		locale?: string;
		seed?: {
			clientId: string;
			clientName: string;
			subject: string;
			propertyId: string | null;
			lines: RequestPricingLineInput[];
			sources: InvoiceSourceInput[];
		} | null;
	} = $props();

	const queryClient = useQueryClient();

	type FormState = {
		subject: string;
		client_id: string;
		// The one service property the bill is for. '' means none — a direct invoice need not name a property,
		// and the client's billing address stands in.
		property_id: string;
		// '' = the client/account default term; a term id; or 'custom' for a typed due date.
		term_choice: string;
		issue_date: string;
		custom_due_date: string;
	};

	function blankForm(): FormState {
		return {
			subject: '',
			client_id: '',
			property_id: '',
			term_choice: '',
			issue_date: '',
			custom_due_date: ''
		};
	}

	let form = $state<FormState>(untrack(() => blankForm()));
	let selectedClient = $state<ClientListItem | null>(null);
	let choosingProperty = $state(false);
	let lines = $state<RequestPricingLineInput[]>([]);
	let subtotalMinor = $state(0);
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let layout = $state<RecordFormLayout>();

	// One idempotency key per save intent: the same details retried keep it, so a double click or a network
	// retry gets the first invoice back; changed details mint a new one.
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	function snapshot(values: FormState) {
		return JSON.stringify(values);
	}
	let baseline = $state(untrack(() => snapshot(blankForm())));
	// Lines are compared by value, not by count, so changing a price on a pre-filled bill counts as a change
	// and re-filling the form it opened with does not.
	let baselineLines = $state('[]');
	const isDirty = $derived(snapshot(form) !== baseline || JSON.stringify(lines) !== baselineLines);

	// The seed lands once, a beat after mount. Its client, subject and property fill the form here; its lines
	// go through the shared editor below (via `seededLines`), which owns and re-emits them. Keyed on the seed
	// identity rather than run bare, so a re-render never re-fills over their edits. The line baseline stays
	// blank on purpose, so a bill that opened pre-filled reads as ready to save from the first paint.
	let seededFrom = $state<string | null>(null);
	$effect(() => {
		if (!seed) return;
		const key = seed.sources.map((source) => `${source.kind}:${source.job_id}`).join(',');
		if (seededFrom === key) return;
		seededFrom = key;
		untrack(() => {
			form.client_id = seed.clientId;
			form.subject = seed.subject;
			form.property_id = seed.propertyId ?? '';
			baseline = snapshot(form);
		});
	});

	// The seed carries the job's priced lines in the send shape; the editor renders the saved shape, so this
	// fills in the position and totals it needs. Ids are only browser-side keys here — the whole set is
	// replaced on save — so a stable synthetic id per row is all the editor and its drag handles want.
	const seededLines = $derived<RequestPricingLine[]>(
		seed
			? seed.lines.map((line, index) => ({
					id: `seed-${index}`,
					position: index,
					catalog_item_id: line.catalog_item_id,
					category: line.category,
					is_labor: line.is_labor,
					name: line.name,
					description: line.description ?? null,
					unit_label: line.unit_label ?? null,
					quantity: line.quantity,
					unit_price_minor: line.unit_price_minor,
					unit_cost_minor: line.unit_cost_minor,
					is_taxable: line.is_taxable ?? true,
					line_total_minor: line.quantity * line.unit_price_minor,
					line_cost_total_minor: line.quantity * line.unit_cost_minor,
					image_attachment_id: line.image_attachment_id ?? null,
					line_kind: line.line_kind ?? 'priced',
					selection_kind: line.selection_kind ?? 'required',
					is_recommended: line.is_recommended ?? false
				}))
			: []
	);

	// The organization's named payment terms. Warmed from the list on the way in when possible; the form still
	// opens instantly and the picker fills as soon as they arrive.
	const termsQuery = createQuery(() => ({
		queryKey: invoicePaymentTermsKey,
		queryFn: fetchInvoicePaymentTerms,
		staleTime: 60_000
	}));
	const termOptions = $derived([
		{ value: '', label: "Client's default terms" },
		...(termsQuery.data ?? []).map((term) => ({ value: term.id, label: term.name })),
		{ value: 'custom', label: 'Custom due date' }
	]);

	// Most clients have one property, so this only asks which when there is a real choice to make.
	const clientPropertiesQuery = createQuery(() => ({
		queryKey: clientDetailKey(selectedClient?.id ?? ''),
		queryFn: () => fetchClient(selectedClient!.id),
		enabled: choosingProperty && Boolean(selectedClient),
		staleTime: 15_000
	}));
	const propertyOptions = $derived([
		{ value: '', label: 'No property' },
		...(clientPropertiesQuery.data?.properties ?? []).map((property) => ({
			value: property.id,
			label: property.label || [property.address_line1, property.city].filter(Boolean).join(', ')
		}))
	]);

	function chooseClient(client: ClientListItem | null) {
		selectedClient = client;
		form.property_id = client?.primary_property?.id ?? '';
		choosingProperty = false;
	}

	function readDraftLines(nextLines: RequestPricingLineInput[], nextSubtotal: number) {
		lines = nextLines;
		subtotalMinor = nextSubtotal;
	}

	// An invoice line bills priced product or service work — no headings, notes, or add-ons — so the editor's
	// draft lines map straight across, with position set from their order and no internal cost carried.
	function invoiceLines(): InvoiceLineInput[] {
		return lines.map((line, index) => ({
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
	}

	// A short, stable fingerprint of what the person is saving, so the command can tell a replay of the same
	// invoice from a fresh one carrying the same key. FNV-1a over the ordered payload keeps it well under the
	// column's limit.
	function fingerprint(value: unknown): string {
		const json = JSON.stringify(value);
		let hash = 0x811c9dc5;
		for (let index = 0; index < json.length; index++) {
			hash ^= json.charCodeAt(index);
			hash = Math.imul(hash, 0x01000193);
		}
		return `v1:${(hash >>> 0).toString(16)}`;
	}

	async function submit() {
		if (saving) return;

		fieldErrors = {};
		formError = '';

		if (!form.subject.trim()) {
			fieldErrors = { subject: 'Give this invoice a subject.' };
			return;
		}
		if (!form.client_id) {
			formError = 'Choose a client to continue.';
			return;
		}
		if (lines.length === 0) {
			formError = 'Add at least one line before saving.';
			return;
		}
		const lineProblem = firstLineProblem(lines);
		if (lineProblem) {
			formError = lineProblem;
			return;
		}
		if (form.term_choice === 'custom' && !form.custom_due_date) {
			fieldErrors = { custom_due_date: 'Pick the date this invoice is due.' };
			return;
		}

		const core = {
			client_id: form.client_id,
			subject: form.subject.trim(),
			lines: invoiceLines(),
			service_property_ids: form.property_id ? [form.property_id] : [],
			issue_date: form.issue_date || null,
			payment_term_id: form.term_choice && form.term_choice !== 'custom' ? form.term_choice : null,
			custom_due_date: form.term_choice === 'custom' ? form.custom_due_date : null,
			// Part of the fingerprint on purpose: the same lines billed against different work are two
			// different bills, and a replay must not return the wrong one.
			...(seed && seed.sources.length > 0 ? { sources: seed.sources } : {})
		};
		const hash = fingerprint(core);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			const result = await createInvoice({
				...core,
				idempotency_key: idempotencyKey,
				request_hash: hash
			});
			await queryClient.invalidateQueries({ queryKey: ['invoices', 'list'] });
			await queryClient.invalidateQueries({ queryKey: ['invoices', 'counts'] });
			// Billing a job changes the job too — its reminders are answered and it leaves "Requires
			// invoicing" — so everything that draws jobs is refetched, along with what is still billable.
			if (seed && seed.sources.length > 0) {
				await queryClient.invalidateQueries({ queryKey: ['jobs'] });
				await queryClient.invalidateQueries({ queryKey: ['invoices', 'billable-work'] });
			}
			baseline = snapshot(form);
			baselineLines = JSON.stringify(lines);
			onSaved({ id: result.invoice_id, number: result.invoice_number });
		} catch (caught) {
			const writeError = caught as InvoiceWriteError;
			fieldErrors = writeError.fieldErrors ?? {};
			formError = fieldErrors.form || writeError.message || 'That invoice could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<form
	class="invoice-form"
	onsubmit={(event) => {
		event.preventDefault();
		void submit().finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout title="New Invoice" icon={receiptIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			<PrimaryInfoCard
				id="invoice-primary"
				icon={receiptIcon}
				bind:title={form.subject}
				titleLabel="Subject"
				titleRequired
				titleInvalid={Boolean(fieldErrors.subject)}
				titleError={fieldErrors.subject ?? ''}
			>
				{#snippet client()}
					<ClientPicker
						id="invoice-client"
						bind:value={form.client_id}
						initialLabel={seed?.clientName ?? ''}
						required
						invalid={Boolean(fieldErrors.client_id)}
						errorMessage={fieldErrors.client_id ?? ''}
						onSelect={chooseClient}
					/>
					{#if selectedClient && (selectedClient.additional_property_count > 0 || choosingProperty)}
						{#if choosingProperty}
							<div class="invoice-form__property">
								<Select
									id="invoice-property"
									bind:value={form.property_id}
									options={propertyOptions}
									placeholder="Loading properties…"
									label="Service property"
								/>
							</div>
						{:else}
							<button
								type="button"
								class="invoice-form__change-property"
								onclick={() => (choosingProperty = true)}
							>
								Change property
							</button>
						{/if}
					{/if}
				{/snippet}
				{#snippet fields()}
					<Input
						id="invoice-number"
						label="Invoice #"
						readonly
						tabindex={-1}
						value=""
						placeholder="Given when you save"
					/>
				{/snippet}
			</PrimaryInfoCard>

			<ProductsAndServicesBlock
				alwaysEditing
				editable
				lines={seededLines}
				{currencyCode}
				{locale}
				editorTotalLabel="Invoice subtotal"
				emptyDescription="Add the products and services this invoice bills for."
				onDraftChange={readDraftLines}
			/>

			<SectionBlock title="Terms & dates" icon={calendarIcon} form>
				<div class="invoice-form__dates">
					<div class="invoice-form__date">
						<CalendarPicker
							id="invoice-issue-date"
							label="Invoice date"
							value={calendarDateFromString(form.issue_date)}
							onchange={(value) => (form.issue_date = calendarDateToString(value))}
						/>
						<p class="invoice-form__hint">Defaults to today if left blank.</p>
					</div>

					<Select
						id="invoice-terms"
						label="Payment terms"
						bind:value={form.term_choice}
						options={termOptions}
					/>

					{#if form.term_choice === 'custom'}
						<div class="invoice-form__date">
							<CalendarPicker
								id="invoice-due-date"
								label="Due date"
								value={calendarDateFromString(form.custom_due_date)}
								minValue={calendarDateFromString(form.issue_date)}
								onchange={(value) => (form.custom_due_date = calendarDateToString(value))}
							/>
							{#if fieldErrors.custom_due_date}
								<p class="invoice-form__error">{fieldErrors.custom_due_date}</p>
							{/if}
						</div>
					{/if}
				</div>
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<QuoteSummaryCard title="Invoice total" {subtotalMinor} {currencyCode} {locale} />
		{/snippet}

		{#snippet actions()}
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>
				Save Invoice
			</Button>
		{/snippet}
	</RecordFormLayout>
</form>

<style lang="scss">
	.invoice-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__property {
			margin-top: var(--space-small);
		}

		&__dates {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__date {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-destructive);
			font-size: var(--typography--fontSize-small);
		}

		&__change-property {
			margin-top: var(--space-smaller);
			padding: 0;
			border: 0;
			color: var(--color-interactive);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				color: var(--color-interactive--hover);
				text-decoration: underline;
			}
			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}
	}
</style>
