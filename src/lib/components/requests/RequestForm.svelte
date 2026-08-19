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
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import FormNotesCard from '$lib/components/forms/FormNotesCard.svelte';
	import AttachmentsCard from '$lib/components/collaboration/AttachmentsCard.svelte';
	import { fetchClient, clientDetailKey, type ClientListItem } from '$lib/clients/api';
	import { createNote, notesKey } from '$lib/collaboration/api';
	import {
		createRequest,
		requestCountsKey,
		type RequestCreateInput,
		type RequestWriteError
	} from '$lib/requests/api';
	import { invalidatePipeline } from '$lib/pipeline/api';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import clipboardIcon from '@tabler/icons/outline/clipboard-text.svg?raw';
	import truckIcon from '@tabler/icons/outline/truck.svg?raw';
	import listIcon from '@tabler/icons/outline/list-details.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// Creating a request only. Scheduling the on-site assessment and pricing line items both need a saved
	// request to hang off, so this page stops at the same three things Jobber's own New Request form asks
	// for up front — title, client, and what the client is asking for — and hands off to the request's own
	// detail page for the rest.
	let {
		onSaved,
		onCancel
	}: {
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
	let attachmentsCard = $state<AttachmentsCard>();
	let pendingFileCount = $state(0);

	function snapshot(values: FormState) {
		return JSON.stringify(values);
	}
	let baseline = $state(untrack(() => snapshot(form)));
	const isDirty = $derived(snapshot(form) !== baseline || pendingFileCount > 0);

	// Set once a create succeeds, so a stuck file upload can be retried without creating a second request.
	let savedRequestId = $state('');

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

		saving = true;
		fieldErrors = {};
		formError = '';

		try {
			const request = await createRequest(buildValues());

			if (form.initial_note.trim()) {
				await createNote({
					entityType: 'request',
					entityId: request.id,
					body: form.initial_note.trim()
				});
				await queryClient.invalidateQueries({ queryKey: notesKey('request', request.id) });
			}

			await queryClient.invalidateQueries({ queryKey: ['requests', 'list'] });
			await queryClient.invalidateQueries({ queryKey: requestCountsKey });
			// A new request is a new card on the pipeline, created by the database along with it.
			await invalidatePipeline(queryClient);

			const failedUploads = (await attachmentsCard?.saveAll(request.id)) ?? 0;
			if (failedUploads > 0) {
				savedRequestId = request.id;
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
			}
			baseline = snapshot(form);
			onSaved(request, andAnother);
		} catch (error) {
			if (error instanceof Error && 'fieldErrors' in error) {
				fieldErrors = (error as RequestWriteError).fieldErrors ?? {};
			}
			formError = error instanceof Error ? error.message : 'That request could not be saved.';
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

<!-- eslint-disable svelte/no-at-html-tags -->
<form
	class="request-form"
	onsubmit={(event) => {
		event.preventDefault();
		void submit(false);
	}}
>
	<RecordFormLayout {title} icon={fileTextIcon}>
		{#snippet main()}
			{#if formError}
				<p class="request-form__alert" role="alert">
					<span aria-hidden="true">{@html alertTriangleIcon}</span>{formError}
				</p>
			{/if}

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

			<SectionBlock title="On-site assessment" icon={truckIcon} level={2}>
				<EmptyState
					icon={truckIcon}
					title="No visit booked"
					description="Save the request, then book the visit from its page."
				/>
			</SectionBlock>

			<SectionBlock title="Products and services" icon={listIcon} level={2}>
				<EmptyState
					icon={listIcon}
					title="Nothing priced yet"
					description="Line items land here once quoting is built. For now, price the work on the quote itself."
				/>
			</SectionBlock>
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
						onclick={() => void submit(true)}
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

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.request-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__alert {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-critical--onSurface);
			background: var(--color-critical--surface);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				display: block;
				width: 18px;
				height: 18px;
				flex: 0 0 auto;
			}
		}

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
