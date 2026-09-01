<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import PrimaryInfoCard from '$lib/components/work/PrimaryInfoCard.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteClientViewBlock from '$lib/components/quotes/QuoteClientViewBlock.svelte';
	import AddSectionControl from '$lib/components/work/AddSectionControl.svelte';
	import QuoteSummaryCard from '$lib/components/quotes/QuoteSummaryCard.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import FormNotesCard from '$lib/components/forms/FormNotesCard.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import { fetchClient, clientDetailKey, type ClientListItem } from '$lib/clients/api';
	import { createNote, fetchAttachments, notesKey } from '$lib/collaboration/api';
	import {
		createQuote,
		saveQuoteLines,
		saveQuoteCopy,
		saveQuoteVisibility,
		saveQuoteVersionAttachments,
		quoteCountsKey,
		type QuoteVisibility,
		type RequestPricingLineInput,
		type QuoteWriteError
	} from '$lib/quotes/api';
	import { firstLineProblem } from '$lib/quotes/lines';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import fileDollarIcon from '@tabler/icons/outline/file-dollar.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import speakerphoneIcon from '@tabler/icons/outline/speakerphone.svg?raw';
	import messageIcon from '@tabler/icons/outline/message.svg?raw';
	import paperclipIcon from '@tabler/icons/outline/paperclip.svg?raw';
	import photoIcon from '@tabler/icons/outline/photo.svg?raw';

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
		{ id: 'introduction', label: 'Introduction', icon: speakerphoneIcon },
		{ id: 'attachments', label: 'Attachments', icon: paperclipIcon },
		{ id: 'images', label: 'Images', icon: photoIcon },
		{ id: 'client_message', label: 'Client Message', icon: messageIcon }
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
	let formError = $state('');
	let saving = $state(false);
	let layout = $state<RecordFormLayout>();
	let documentAttachments = $state<AttachmentsCard>();
	let imageAttachments = $state<AttachmentsCard>();
	let productsAndServices = $state<ProductsAndServicesBlock>();
	let pendingDocumentCount = $state(0);
	let pendingImageCount = $state(0);
	let showIntroduction = $state(false);
	let showClientMessage = $state(false);
	let showAttachments = $state(false);
	let showImages = $state(false);
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
	const pendingFileCount = $derived(pendingDocumentCount + pendingImageCount);
	const optionalSectionOptions = $derived(
		sectionOptions.filter((option) => {
			if (option.id === 'attachments') return !showAttachments;
			if (option.id === 'images') return !showImages;
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
	let filesLinked = $state(false);

	function snapshot(values: FormState) {
		return JSON.stringify(values);
	}
	let baseline = $state(untrack(() => snapshot(form)));
	const isDirty = $derived(
		snapshot(form) !== baseline || lines.length > 0 || pendingFileCount > 0 || visibilityTouched
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

			const [failedDocuments, failedImages] = await Promise.all([
				documentAttachments?.saveAll(savedQuote.id) ?? 0,
				imageAttachments?.saveAll(savedQuote.id) ?? 0
			]);
			const failedUploads = failedDocuments + failedImages;
			if (failedUploads > 0) {
				baseline = snapshot(form);
				formError =
					failedUploads === 1
						? 'The quote was saved, but one file did not upload. Retry it below.'
						: `The quote was saved, but ${failedUploads} files did not upload. Retry them below.`;
				return;
			}

			if (!filesLinked && (showAttachments || showImages)) {
				const files = await fetchAttachments('quote', savedQuote.id);
				if (files.length > 0) {
					const written = await saveQuoteVersionAttachments(
						savedQuote.id,
						savedQuote.revision,
						files.map((file) => ({
							attachment_id: file.id,
							display_name: file.file_name,
							customer_visible: true
						}))
					);
					savedQuote = { ...savedQuote, revision: written.revision };
				}
				filesLinked = true;
			}

			baseline = snapshot(form);
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

<form
	class="quote-form"
	onsubmit={(event) => {
		event.preventDefault();
		void submit().finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout title="New Quote" icon={fileDollarIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			<PrimaryInfoCard
				id="quote-primary"
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
							<button
								type="button"
								class="quote-form__change-property"
								onclick={() => (choosingProperty = true)}
							>
								Change property
							</button>
						{/if}
					{/if}
				{/snippet}
				{#snippet fields()}
					<Input
						id="quote-number"
						label="Quote #"
						readonly
						tabindex={-1}
						value={savedQuote ? String(savedQuote.number) : ''}
						placeholder="Given when you save"
					/>
				{/snippet}
			</PrimaryInfoCard>

			{#if !showIntroduction}
				<AddSectionControl options={introductionOption} onAdd={() => (showIntroduction = true)} />
			{:else}
				<SectionBlock title="Introduction" icon={speakerphoneIcon} form>
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
				onAdd={(section) => {
					if (section === 'attachments') showAttachments = true;
					else if (section === 'images') showImages = true;
					else if (section === 'client_message') showClientMessage = true;
				}}
			/>

			{#if showAttachments}
				<AttachmentsCard
					bind:this={documentAttachments}
					onPendingChange={(count) => (pendingDocumentCount = count)}
					entityType="quote"
					entityId={savedQuote?.id}
					title="Attachments"
					surface="section"
					kind="documents"
				/>
			{/if}

			{#if showImages}
				<AttachmentsCard
					bind:this={imageAttachments}
					onPendingChange={(count) => (pendingImageCount = count)}
					entityType="quote"
					entityId={savedQuote?.id}
					title="Images"
					surface="section"
					kind="images"
				/>
			{/if}

			{#if showClientMessage}
				<SectionBlock title="Client message" icon={messageIcon} form>
					<Textarea
						id="quote-client-message"
						label="A short note to the client, under the pricing"
						rows={4}
						maxlength={5000}
						bind:value={form.client_message}
					/>
				</SectionBlock>
			{/if}

			<SectionBlock title="Contract disclaimer" icon={fileTextIcon} form>
				<Textarea
					id="quote-disclaimer"
					label="What the client is agreeing to when they approve this quote"
					rows={5}
					maxlength={5000}
					bind:value={form.contract_disclaimer}
					invalid={Boolean(fieldErrors.contract_disclaimer)}
					errorMessage={fieldErrors.contract_disclaimer ?? ''}
				/>
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<QuoteSummaryCard {subtotalMinor} {currencyCode} {locale} />

			<FormNotesCard
				id="quote-initial-note"
				bind:value={form.initial_note}
				error={fieldErrors.initial_note ?? ''}
			/>
		{/snippet}

		{#snippet actions()}
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>
				{savedQuote ? 'Save changes' : 'Save Quote'}
			</Button>
		{/snippet}
	</RecordFormLayout>
</form>

<style lang="scss">
	.quote-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__property {
			margin-top: var(--space-small);
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
