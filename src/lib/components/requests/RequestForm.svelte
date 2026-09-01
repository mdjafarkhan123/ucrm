<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import PrimaryInfoCard from '$lib/components/work/PrimaryInfoCard.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import FormNotesCard from '$lib/components/forms/FormNotesCard.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import AssessmentBlock from '$lib/components/requests/AssessmentBlock.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import { fetchClient, clientDetailKey, type ClientListItem } from '$lib/clients/api';
	import { createNote, notesKey } from '$lib/collaboration/api';
	import {
		createRequest,
		saveAssessment,
		requestCountsKey,
		type RequestCreateInput,
		type RequestWriteError
	} from '$lib/requests/api';
	import {
		saveRequestPricing,
		requestPricingKey,
		type RequestPricingLineInput
	} from '$lib/quotes/api';
	import { firstLineProblem } from '$lib/quotes/lines';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import clipboardIcon from '@tabler/icons/outline/clipboard-text.svg?raw';

	// The whole New Request page, the way Jobber writes one: title, client, what they are asking for, the
	// on-site visit and the line items all on one page, with a single Save at the bottom. The visit and the
	// pricing are records of their own, so they are held in memory here and written straight after the
	// request itself exists — nobody has to save a half-finished request to get at them.
	let {
		currencyCode = 'USD',
		locale = 'en-US',
		onSaved,
		onCancel
	}: {
		currencyCode?: string;
		locale?: string;
		onSaved: (request: { id: string; title: string }, andAnother: boolean) => void;
		onCancel: () => void;
	} = $props();

	const queryClient = useQueryClient();

	type FormState = {
		title: string;
		client_id: string;
		property_id: string;
		description: string;
		initial_note: string;
	};

	function blankForm(): FormState {
		return { title: '', client_id: '', property_id: '', description: '', initial_note: '' };
	}

	let form = $state<FormState>(untrack(() => blankForm()));
	let selectedClient = $state<ClientListItem | null>(null);
	let choosingProperty = $state(false);
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let layout = $state<RecordFormLayout>();
	let attachmentsCard = $state<AttachmentsCard>();
	let pendingFileCount = $state(0);

	// The visit and the line items live outside `form` because each one is its own record with its own
	// write. They still count towards the page being dirty, so Save turns on for them like any other field.
	let assessmentBlock = $state<AssessmentBlock>();
	let productsAndServices = $state<ProductsAndServicesBlock>();
	let visitBooked = $state(false);
	let lines = $state<RequestPricingLineInput[]>([]);

	function snapshot(values: FormState) {
		return JSON.stringify(values);
	}
	let baseline = $state(untrack(() => snapshot(form)));
	const isDirty = $derived(
		snapshot(form) !== baseline || pendingFileCount > 0 || visitBooked || lines.length > 0
	);

	// Set once a create succeeds, so a stuck file upload can be retried without creating a second request.
	// The visit and the pricing carry their own flags for the same reason: a retry after a half-failed save
	// must not book the visit twice.
	let savedRequestId = $state('');
	let visitSaved = $state(false);
	let pricingSaved = $state(false);
	let noteSaved = $state(false);

	// The block draws its own running total, so only the rows themselves matter up here.
	function readDraftLines(nextLines: RequestPricingLineInput[]) {
		lines = nextLines;
	}

	// A client with more than one property needs a way to say which this request is for. Most clients only
	// have the one, so this stays hidden until there is an actual choice to make.
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

	function buildValues(): RequestCreateInput {
		return {
			client_id: form.client_id,
			property_id: form.property_id,
			title: form.title.trim(),
			description: form.description.trim()
		};
	}

	async function submit(andAnother: boolean) {
		if (saving || !isDirty) return;
		if (!form.property_id) {
			formError = selectedClient
				? 'This client has no property yet. Add one on their profile before creating a request.'
				: 'Choose a client to continue.';
			return;
		}

		// Both extra records get checked before anything is written, so a bad date or a nameless line stops
		// the save rather than leaving a request behind with half of what was typed into it.
		const visit = assessmentBlock?.collectDraft() ?? { ok: true as const, draft: null };
		if (!visit.ok) {
			formError = visit.message;
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
			const request = savedRequestId
				? { id: savedRequestId, title: form.title.trim() }
				: await createRequest(buildValues());
			savedRequestId = request.id;

			if (!visitSaved && visit.draft) {
				await saveAssessment(request.id, visit.draft);
				visitSaved = true;
			}

			if (!pricingSaved && lines.length > 0) {
				const photos = await productsAndServices?.savePendingPhotos('request', request.id);
				if (photos && photos.failures > 0) {
					formError =
						photos.failures === 1
							? 'The request was created, but one line-item photo did not upload. Press Save again to retry.'
							: `The request was created, but ${photos.failures} line-item photos did not upload. Press Save again to retry.`;
					return;
				}
				const linesToSave = photos?.lines ?? lines;
				lines = linesToSave;
				// A brand new request has never been priced, so revision 0 is the version being edited.
				await saveRequestPricing(request.id, 0, linesToSave);
				productsAndServices?.commitPendingPhotos();
				await queryClient.invalidateQueries({ queryKey: requestPricingKey(request.id) });
				pricingSaved = true;
			}

			if (!noteSaved && form.initial_note.trim()) {
				await createNote({
					entityType: 'request',
					entityId: request.id,
					body: form.initial_note.trim()
				});
				await queryClient.invalidateQueries({ queryKey: notesKey('request', request.id) });
				noteSaved = true;
			}

			await queryClient.invalidateQueries({ queryKey: ['requests', 'list'] });
			await queryClient.invalidateQueries({ queryKey: requestCountsKey });
			// A new request is a new card on the pipeline, created by the database along with it.
			await invalidatePipeline(queryClient);

			const failedUploads = (await attachmentsCard?.saveAll(request.id)) ?? 0;
			if (failedUploads > 0) {
				baseline = snapshot(form);
				formError =
					failedUploads === 1
						? 'The request was saved, but one file did not upload. Retry it below.'
						: `The request was saved, but ${failedUploads} files did not upload. Retry them below.`;
				return;
			}

			if (andAnother) {
				form = blankForm();
				selectedClient = null;
				choosingProperty = false;
				savedRequestId = '';
				visitBooked = false;
				visitSaved = false;
				lines = [];
				pricingSaved = false;
				noteSaved = false;
			}
			baseline = snapshot(form);
			onSaved(request, andAnother);
		} catch (error) {
			if (error instanceof Error && 'fieldErrors' in error) {
				fieldErrors = (error as RequestWriteError).fieldErrors ?? {};
			}
			const message = error instanceof Error ? error.message : 'That request could not be saved.';
			// The request itself is already in. Say so, otherwise the only sensible-looking move is to fill
			// the form in again and end up with two of them.
			formError = savedRequestId
				? `The request was created, but something else on the page did not save: ${message} Press Save again to finish it.`
				: message;
		} finally {
			saving = false;
		}
	}

	const dateFormat = new Intl.DateTimeFormat('en-GB', {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const requestedOn = dateFormat.format(new Date());

	const title = 'New Request';
</script>

<form
	class="request-form"
	onsubmit={(event) => {
		event.preventDefault();
		void submit(false).finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout {title} icon={fileTextIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			<PrimaryInfoCard
				bind:title={form.title}
				titleRequired
				titleInvalid={Boolean(fieldErrors.title)}
				titleError={fieldErrors.title ?? ''}
			>
				{#snippet client()}
					<ClientPicker
						id="request-client"
						bind:value={form.client_id}
						required
						invalid={Boolean(fieldErrors.client_id)}
						errorMessage={fieldErrors.client_id ?? ''}
						onSelect={chooseClient}
					/>
					{#if selectedClient && (selectedClient.additional_property_count > 0 || choosingProperty)}
						{#if choosingProperty}
							<div class="request-form__property">
								<Select
									id="request-property"
									bind:value={form.property_id}
									options={propertyOptions}
									placeholder="Loading properties…"
									ariaLabel="Property"
								/>
							</div>
						{:else}
							<button
								type="button"
								class="request-form__change-property"
								onclick={() => (choosingProperty = true)}
							>
								Change property
							</button>
						{/if}
					{/if}
				{/snippet}
				{#snippet fields()}
					<p class="request-form__requested-on">Requested on: <strong>{requestedOn}</strong></p>
				{/snippet}
			</PrimaryInfoCard>

			<SectionBlock title="Service overview" icon={clipboardIcon} form>
				<Textarea
					id="request-description"
					label="Please provide as much information as you can"
					rows={6}
					bind:value={form.description}
				/>
			</SectionBlock>

			<AssessmentBlock
				bind:this={assessmentBlock}
				draft
				assessment={null}
				onDraftChange={(booked) => (visitBooked = booked)}
			/>

			<ProductsAndServicesBlock
				bind:this={productsAndServices}
				alwaysEditing
				editable
				{currencyCode}
				{locale}
				editorTotalLabel="Request subtotal"
				onDraftChange={readDraftLines}
			/>
		{/snippet}

		{#snippet rail()}
			<FormNotesCard
				id="request-initial-note"
				bind:value={form.initial_note}
				error={fieldErrors.initial_note ?? ''}
			/>

			<AttachmentsCard
				bind:this={attachmentsCard}
				onPendingChange={(count) => (pendingFileCount = count)}
				entityType="request"
				entityId={savedRequestId || undefined}
			/>
		{/snippet}

		{#snippet actions()}
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<div class="request-form__actions-primary">
				{#if !savedRequestId}
					<Button
						variant="secondary"
						onclick={() => void submit(true).finally(() => layout?.revealError())}
						disabled={saving || !isDirty}
					>
						Save & Create Another
					</Button>
				{/if}
				<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>
					{savedRequestId ? 'Save changes' : 'Save Request'}
				</Button>
			</div>
		{/snippet}
	</RecordFormLayout>
</form>

<style lang="scss">
	.request-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__requested-on {
			margin: 0;
			padding: var(--space-small) 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			strong {
				color: var(--color-heading);
			}
		}

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
				text-decoration: underline;
			}
		}

		&__actions-primary {
			display: flex;
			gap: var(--space-small);
		}
	}

	@media (max-width: 767px) {
		.request-form__actions-primary {
			flex-direction: column;
		}
	}
</style>
