<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import CreateFormHeader from '$lib/components/work/CreateFormHeader.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteClientViewBlock from '$lib/components/quotes/QuoteClientViewBlock.svelte';
	import AddSectionControl from '$lib/components/work/AddSectionControl.svelte';
	import DraftMoneyCard from '$lib/components/work/DraftMoneyCard.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import FormNotesCard from '$lib/components/forms/FormNotesCard.svelte';
	import PendingFilesCard from '$lib/components/files/PendingFilesCard.svelte';
	import RecordDiscountCard from '$lib/components/work/RecordDiscountCard.svelte';
	import RecordTaxCard from '$lib/components/work/RecordTaxCard.svelte';
	import { fetchClient, clientDetailKey, type ClientListItem } from '$lib/clients/api';
	import { createNote, notesKey } from '$lib/collaboration/api';
	import { fetchTaxPicker, taxPickerKey } from '$lib/settings/api';
	import {
		createQuote,
		saveQuoteLines,
		saveQuoteCopy,
		saveQuoteVisibility,
		saveQuoteDiscount,
		saveQuoteTax,
		syncQuoteVersionAttachments,
		quoteCountsKey,
		type QuoteVisibility,
		type QuoteDiscountInput,
		type QuoteTaxInput,
		type RequestPricingLineInput,
		type QuoteWriteError
	} from '$lib/quotes/api';
	import { firstLineProblem } from '$lib/quotes/lines';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import fileDollarIcon from '@tabler/icons/outline/file-dollar.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-check.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import speakerphoneIcon from '@tabler/icons/outline/speakerphone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';

	// Writing a quote from scratch. The number, the draft version and the address it is written against
	// all come from the database the moment this is saved, so nothing here guesses at them.
	let {
		onSaved,
		onCancel,
		currencyCode = 'USD',
		locale = 'en-US'
	}: {
		onSaved: (quote: { id: string; number: number }) => void;
		onCancel: () => void;
		currencyCode?: string;
		locale?: string;
	} = $props();

	const queryClient = useQueryClient();
	const sectionOptions = [
		{
			id: 'introduction',
			label: 'Introduction',
			icon: speakerphoneIcon,
			hint: 'How the quote opens, above the pricing'
		},
		{
			id: 'client_message',
			label: 'Client message',
			icon: messageIcon,
			hint: 'A short note to the client, under the pricing'
		}
	];
	const introductionOption = sectionOptions.filter((option) => option.id === 'introduction');

	type FormState = {
		title: string;
		client_id: string;
		property_id: string;
		introduction: string;
		client_message: string;
		contract_disclaimer: string;
		initial_note: string;
	};

	function blankForm(): FormState {
		return {
			title: '',
			client_id: '',
			property_id: '',
			introduction: '',
			client_message: '',
			contract_disclaimer: '',
			initial_note: ''
		};
	}

	let form = $state<FormState>(untrack(() => blankForm()));
	let selectedClient = $state<ClientListItem | null>(null);
	let choosingProperty = $state(false);
	let lines = $state<RequestPricingLineInput[]>([]);
	let subtotalMinor = $state(0);
	let fieldErrors = $state<Record<string, string>>({});
	const toast = getToastManager();
	let formError = $state('');
	let saving = $state(false);
	let layout = $state<RecordFormLayout>();
	let pendingFilesCard = $state<PendingFilesCard>();
	let productsAndServices = $state<ProductsAndServicesBlock>();
	let pendingFileCount = $state(0);
	let showIntroduction = $state(false);
	let showClientMessage = $state(false);
	let editingVisibility = $state(false);
	let visibilityTouched = $state(false);
	let visibility = $state<QuoteVisibility>({
		show_quantities: true,
		show_unit_prices: true,
		show_line_totals: true,
		show_totals: true
	});
	const defaultVisibility: QuoteVisibility = {
		show_quantities: true,
		show_unit_prices: true,
		show_line_totals: true,
		show_totals: true
	};
	const optionalSectionOptions = $derived(
		sectionOptions.filter((option) => {
			if (option.id === 'client_message') return !showClientMessage;
			return false;
		})
	);

	// Set once the quote itself exists, so a failed line save, note or upload can be retried without
	// writing a second quote.
	let savedQuote = $state<{ id: string; number: number; revision: number } | null>(null);
	let linesSaved = $state(false);
	let noteSaved = $state(false);
	let copySaved = $state(false);
	let visibilitySaved = $state(false);
	// Pending means chosen since the last write, so a change made after a partly failed save — even taking
	// the discount off again — is still written on the retry.
	let discountPending = $state(false);
	let taxPending = $state(false);

	// Discount and Tax are held here until Save, then written right after the quote exists, the same as
	// the introduction and client view above. Nothing reaches the database before Save is pressed.
	let discount = $state<QuoteDiscountInput | null>(null);
	let tax = $state<QuoteTaxInput | null>(null);

	// The database decides what "Business default" or "Property default" means at save time. Until then the
	// card names the rate the tax dialog offered for that choice, from the same cached list.
	const taxPickerQuery = createQuery(() => ({
		queryKey: taxPickerKey(form.property_id),
		queryFn: () => fetchTaxPicker(form.property_id),
		enabled: Boolean(tax) && Boolean(form.property_id),
		staleTime: 30_000
	}));
	const taxPreview = $derived.by(() => {
		if (!tax || tax.source === 'no_tax') return { name: null, rateBasisPoints: 0 };
		if (tax.source === 'custom')
			return { name: tax.custom_name, rateBasisPoints: tax.custom_rate_basis_points ?? 0 };
		const picker = taxPickerQuery.data;
		const resolved =
			tax.source === 'saved_rate'
				? picker?.rates.find((rate) => rate.id === tax?.rate_id)
				: tax.source === 'property_default'
					? picker?.property_default
					: picker?.business_default;
		return { name: resolved?.name ?? null, rateBasisPoints: resolved?.rate_basis_points ?? 0 };
	});

	// A preview of the chosen discount and tax for the money card, the way the line editor previews line
	// totals. The tax falls only on taxable lines, spread across the discount. The database works out the
	// real figures when the quote saves.
	const discountPreviewMinor = $derived.by(() => {
		if (!discount?.type || discount.value === null) return 0;
		const off =
			discount.type === 'percentage'
				? Math.round((subtotalMinor * discount.value) / 10_000)
				: discount.value;
		return Math.min(subtotalMinor, Math.max(0, off));
	});
	const taxPreviewMinor = $derived.by(() => {
		if (!tax || tax.source === 'no_tax' || taxPreview.rateBasisPoints <= 0 || subtotalMinor <= 0)
			return null;
		const taxable = lines.reduce(
			(sum, line) =>
				(line.line_kind ?? 'priced') === 'priced' &&
				(line.selection_kind ?? 'required') === 'required' &&
				(line.is_taxable ?? true)
					? sum + Math.round(line.quantity * line.unit_price_minor)
					: sum,
			0
		);
		const afterDiscount = taxable * ((subtotalMinor - discountPreviewMinor) / subtotalMinor);
		return Math.round((afterDiscount * taxPreview.rateBasisPoints) / 10_000);
	});

	function snapshot(values: FormState) {
		return JSON.stringify(values);
	}
	let baseline = $state(untrack(() => snapshot(form)));
	const isDirty = $derived(
		snapshot(form) !== baseline ||
			lines.length > 0 ||
			pendingFileCount > 0 ||
			visibilityTouched ||
			discountPending ||
			taxPending
	);

	// Most clients have one property, so this only asks which when there is a real choice to make.
	const clientPropertiesQuery = createQuery(() => ({
		queryKey: clientDetailKey(selectedClient?.id ?? ''),
		queryFn: () => fetchClient(selectedClient!.id),
		enabled: choosingProperty && Boolean(selectedClient),
		staleTime: 15_000
	}));
	const propertyOptions = $derived(
		(clientPropertiesQuery.data?.properties ?? []).map((property) => ({
			value: property.id,
			label: property.label || [property.address_line1, property.city].filter(Boolean).join(', ')
		}))
	);

	function chooseClient(client: ClientListItem | null) {
		selectedClient = client;
		form.property_id = client?.primary_property?.id ?? '';
		choosingProperty = false;
	}

	function readDraftLines(nextLines: RequestPricingLineInput[], nextSubtotal: number) {
		lines = nextLines;
		subtotalMinor = nextSubtotal;
	}

	async function submit() {
		if (saving) return;

		if (!form.property_id) {
			formError = selectedClient
				? 'This client has no property yet. Add one on their profile before writing a quote.'
				: 'Choose a client to continue.';
			return;
		}
		const lineProblem = firstLineProblem(lines);
		if (lineProblem) {
			formError = lineProblem;
			return;
		}

		saving = true;
		fieldErrors = {};
		formError = '';

		try {
			if (!savedQuote) {
				const created = await createQuote({
					client_id: form.client_id,
					property_id: form.property_id,
					title: form.title.trim(),
					contract_disclaimer: form.contract_disclaimer.trim() || null
				});
				savedQuote = {
					id: created.quote_id,
					number: created.quote_number,
					revision: created.revision
				};
			}

			if (!linesSaved && lines.length > 0) {
				const photos = await productsAndServices?.savePendingPhotos('quote', savedQuote.id);
				if (photos && photos.failures > 0) {
					formError =
						photos.failures === 1
							? `Quote #${savedQuote.number} was saved, but one line-item photo did not upload. Press Save to retry.`
							: `Quote #${savedQuote.number} was saved, but ${photos.failures} line-item photos did not upload. Press Save to retry.`;
					return;
				}
				const linesToSave = photos?.lines ?? lines;
				lines = linesToSave;
				const written = await saveQuoteLines(savedQuote.id, savedQuote.revision, linesToSave);
				productsAndServices?.commitPendingPhotos();
				savedQuote = { ...savedQuote, revision: written.revision };
				linesSaved = true;
			}

			if (!copySaved && (form.introduction.trim() || form.client_message.trim())) {
				const written = await saveQuoteCopy(savedQuote.id, savedQuote.revision, {
					introduction: form.introduction.trim() || null,
					client_message: form.client_message.trim() || null
				});
				savedQuote = { ...savedQuote, revision: written.revision };
				copySaved = true;
			}

			if (!visibilitySaved && visibilityTouched) {
				const written = await saveQuoteVisibility(savedQuote.id, savedQuote.revision, visibility);
				savedQuote = { ...savedQuote, revision: written.revision };
				visibilitySaved = true;
			}

			if (discountPending) {
				const written = await saveQuoteDiscount(
					savedQuote.id,
					savedQuote.revision,
					discount ?? { name: null, type: null, value: null }
				);
				savedQuote = { ...savedQuote, revision: written.revision };
				discountPending = false;
			}

			if (taxPending && tax) {
				const written = await saveQuoteTax(savedQuote.id, savedQuote.revision, tax);
				savedQuote = { ...savedQuote, revision: written.revision };
				taxPending = false;
			}

			if (!noteSaved && form.initial_note.trim()) {
				await createNote({
					entityType: 'quote',
					entityId: savedQuote.id,
					body: form.initial_note.trim()
				});
				await queryClient.invalidateQueries({ queryKey: notesKey('quote', savedQuote.id) });
				noteSaved = true;
			}

			await queryClient.invalidateQueries({ queryKey: ['quotes', 'list'] });
			await queryClient.invalidateQueries({ queryKey: quoteCountsKey });
			// A new quote is a new card on the pipeline, created by the database alongside it.
			await invalidatePipeline(queryClient);

			const failedUploads = (await pendingFilesCard?.saveAll(savedQuote.id)) ?? 0;
			if (failedUploads > 0) {
				baseline = snapshot(form);
				formError =
					failedUploads === 1
						? 'The quote was saved, but one file did not upload. Retry it below.'
						: `The quote was saved, but ${failedUploads} files did not upload. Retry them below.`;
				return;
			}
			await syncQuoteVersionAttachments(savedQuote.id);

			baseline = snapshot(form);
			toast.success(`Quote #${savedQuote.number} created`);
			onSaved({ id: savedQuote.id, number: savedQuote.number });
		} catch (caught) {
			const writeError = caught as QuoteWriteError;
			fieldErrors = writeError.fieldErrors ?? {};
			formError = savedQuote
				? `Quote #${savedQuote.number} was saved, but ${writeError.message || 'the rest could not be saved'}. Try again.`
				: writeError.message || 'That quote could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<!-- SVGs below are trusted build-time Tabler icon imports. -->
<!-- eslint-disable svelte/no-at-html-tags -->

<form
	class="quote-form concept-fields"
	onsubmit={(event) => {
		event.preventDefault();
		void submit().finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout
		title="New quote"
		icon={fileDollarIcon}
		bind:this={layout}
		error={formError}
		concept
		pageHeader={false}
		labelledBy="new-quote-title"
		tone="quote"
	>
		{#snippet main()}
			<CreateFormHeader
				id="quote-primary"
				titleId="new-quote-title"
				tone="quote"
				heading="New quote"
				description="Set out the work and its price."
				titlePlaceholder="e.g. Backyard lighting installation"
				factIcon={hashIcon}
				factLabel="Quote #"
				factValue={savedQuote ? String(savedQuote.number) : 'Given when you save'}
				icon={fileDollarIcon}
				bind:title={form.title}
				titleRequired
				titleInvalid={Boolean(fieldErrors.title)}
				titleError={fieldErrors.title ?? ''}
			>
				{#snippet client()}
					<ClientPicker
						id="quote-client"
						bind:value={form.client_id}
						required
						invalid={Boolean(fieldErrors.client_id)}
						errorMessage={fieldErrors.client_id ?? ''}
						onSelect={chooseClient}
					/>
					{#if selectedClient && (selectedClient.additional_property_count > 0 || choosingProperty)}
						{#if choosingProperty}
							<div class="quote-form__property">
								<Select
									id="quote-property"
									bind:value={form.property_id}
									options={propertyOptions}
									placeholder="Loading properties…"
									label="Property"
								/>
							</div>
						{:else}
							<div class="quote-form__change-property">
								<Button variant="quiet" size="small" onclick={() => (choosingProperty = true)}>
									Change property
								</Button>
							</div>
						{/if}
					{/if}
				{/snippet}
			</CreateFormHeader>

			{#if !showIntroduction}
				<AddSectionControl
					options={introductionOption}
					onAdd={() => (showIntroduction = true)}
					cards
					tone="quote"
				/>
			{:else}
				<SectionBlock
					title="Introduction"
					icon={speakerphoneIcon}
					tone="quote"
					hint="How the quote opens, above the pricing"
				>
					<Textarea
						id="quote-introduction"
						label="How this quote opens, above the pricing"
						rows={4}
						maxlength={10000}
						bind:value={form.introduction}
					/>
				</SectionBlock>
			{/if}

			<ProductsAndServicesBlock
				concept
				flush
				totalFoot
				icon={packageIcon}
				tone="quote"
				hint={lines.length
					? `${lines.length} ${lines.length === 1 ? 'line' : 'lines'}`
					: 'Nothing priced yet'}
				emptyDescription="Add the products and services this quote includes."
				bind:this={productsAndServices}
				alwaysEditing
				editable
				quoteChoices
				{currencyCode}
				{locale}
				editorTotalLabel="Quote subtotal"
				onDraftChange={readDraftLines}
			>
				{#snippet clientView()}
					<QuoteClientViewBlock
						saved={defaultVisibility}
						draft={visibility}
						editing={editingVisibility}
						editable
						changed={visibilityTouched}
						onEdit={() => (editingVisibility = !editingVisibility)}
						onChange={(next) => {
							visibility = next;
							visibilityTouched = true;
						}}
					/>
				{/snippet}
			</ProductsAndServicesBlock>

			<AddSectionControl
				options={optionalSectionOptions}
				cards
				tone="quote"
				onAdd={(section) => {
					if (section === 'client_message') showClientMessage = true;
				}}
			/>

			{#if showClientMessage}
				<SectionBlock
					title="Client message"
					icon={messageIcon}
					tone="quote"
					hint="A short note to the client, under the pricing"
				>
					<Textarea
						id="quote-client-message"
						label="A short note to the client, under the pricing"
						rows={4}
						maxlength={5000}
						bind:value={form.client_message}
					/>
				</SectionBlock>
			{/if}

			<SectionBlock
				title="Contract disclaimer"
				icon={fileTextIcon}
				tone="quote"
				hint="What the client agrees to when they approve this quote"
			>
				<Textarea
					id="quote-disclaimer"
					aria-label="What the client is agreeing to when they approve this quote"
					placeholder="Warranty, payment and cancellation terms the client agrees to by approving…"
					rows={5}
					maxlength={5000}
					bind:value={form.contract_disclaimer}
					invalid={Boolean(fieldErrors.contract_disclaimer)}
					errorMessage={fieldErrors.contract_disclaimer ?? ''}
				/>
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<DraftMoneyCard
				kind="quote"
				{lines}
				{subtotalMinor}
				discountMinor={discountPreviewMinor}
				taxMinor={taxPreviewMinor}
				taxLabel={taxPreview.name}
				{currencyCode}
				{locale}
			/>

			<RailCard
				tone="quote"
				title="Discount and tax"
				icon={receiptIcon}
				description="Saves with the quote"
				flush
			>
				<RecordDiscountCard
					dialogHint="New quote"
					revision={0}
					name={discount?.name ?? null}
					type={discount?.type ?? null}
					value={discount?.value ?? null}
					{currencyCode}
					{locale}
					editable
					staged
					onSave={async (_revision, payload) => {
						discount = payload.type === null ? null : payload;
						discountPending = true;
					}}
					onSaved={() => {}}
				/>

				<RecordTaxCard
					dialogHint="New quote"
					revision={0}
					propertyId={form.property_id}
					taxSource={tax?.source ?? 'not_configured'}
					rateId={tax?.rate_id ?? null}
					name={taxPreview.name}
					rateBasisPoints={taxPreview.rateBasisPoints}
					{currencyCode}
					{locale}
					editable={Boolean(form.property_id)}
					staged
					onSave={async (_revision, payload) => {
						tax = payload;
						taxPending = true;
					}}
					onSaved={() => {}}
				/>
			</RailCard>

			<FormNotesCard
				id="quote-initial-note"
				recordNoun="quote"
				bind:value={form.initial_note}
				error={fieldErrors.initial_note ?? ''}
			/>

			<PendingFilesCard
				bind:this={pendingFilesCard}
				onPendingChange={(count) => (pendingFileCount = count)}
				entityType="quote"
			/>
		{/snippet}

		{#snippet status()}
			<span class="quote-form__status-dot" aria-hidden="true"></span>
			<div class="quote-form__status-copy">
				<span class="quote-form__status-title">New quote · not saved yet</span>
				<span class="quote-form__status-hint"
					>It saves as a draft. Send it to the client from the quote page.</span
				>
			</div>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>
				<span class="quote-form__button-icon" aria-hidden="true">{@html checkIcon}</span>
				{savedQuote ? 'Save changes' : 'Save quote'}
			</Button>
		{/snippet}
	</RecordFormLayout>
</form>

<style lang="scss">
	.quote-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		height: 100%;
		min-height: 0;

		&__status-dot {
			width: 8px;
			height: 8px;
			flex: 0 0 auto;
			border-radius: var(--radius-circle);
			background: var(--color-warning);
		}
		&__status-copy {
			display: grid;
			gap: var(--space-smaller);
			min-width: 0;
		}
		&__status-title {
			color: var(--color-heading);
			font-weight: 600;
		}
		&__status-hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
		&__button-icon {
			display: inline-flex;
		}
		&__button-icon :global(svg) {
			width: 16px;
			height: 16px;
		}

		&__property {
			margin-top: var(--space-small);
		}

		&__change-property {
			margin-top: var(--space-smaller);
		}
	}
</style>
