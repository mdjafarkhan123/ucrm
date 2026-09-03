<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import PrimaryInfoCard from '$lib/components/work/PrimaryInfoCard.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteSummaryCard from '$lib/components/quotes/QuoteSummaryCard.svelte';
	import JobVisitsBlock from '$lib/components/jobs/JobVisitsBlock.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import { fetchClient, clientDetailKey, type ClientListItem } from '$lib/clients/api';
	import type { JobCreateSeed } from '$lib/jobs/createDraft';
	import {
		createJob,
		jobCountsKey,
		type JobScopeLineInput,
		type JobWriteError
	} from '$lib/jobs/api';
	import type { RequestPricingLineInput } from '$lib/quotes/api';
	import { firstLineProblem } from '$lib/quotes/lines';
	import toolsIcon from '@tabler/icons/outline/tools.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';

	// Booking a one-off job directly, without a quote behind it. The job number and its money all come from
	// the database the moment it saves, so nothing here guesses at them. The whole thing — the job, its scope
	// and its visits — is written in one command, so there is nothing half-made to clean up if it fails.
	let {
		onSaved,
		onCancel,
		currencyCode = 'USD',
		locale = 'en-US',
		seed = null
	}: {
		onSaved: (job: { id: string; number: number }) => void;
		onCancel: () => void;
		currencyCode?: string;
		locale?: string;
		/** A draft handed over from Schedule's compact create form via More Options: the client, property,
		 * title and first visit the person already chose, so the full form opens filled instead of blank. */
		seed?: JobCreateSeed | null;
	} = $props();

	const queryClient = useQueryClient();

	type FormState = {
		title: string;
		client_id: string;
		property_id: string;
		invoice_on_close: boolean;
	};

	function blankForm(): FormState {
		return {
			title: '',
			client_id: '',
			property_id: '',
			invoice_on_close: true
		};
	}

	// When Schedule hands a draft over, the form opens with the client, property and title already chosen; the
	// baseline below stays blank so that seeded work reads as dirty and Save is live from the first paint.
	function initialForm(): FormState {
		if (!seed) return blankForm();
		return {
			title: seed.title,
			client_id: seed.client?.id ?? '',
			property_id: seed.property_id,
			invoice_on_close: true
		};
	}

	let form = $state<FormState>(untrack(() => initialForm()));
	let selectedClient = $state<ClientListItem | null>(untrack(() => seed?.client ?? null));
	let choosingProperty = $state(false);
	let lines = $state<RequestPricingLineInput[]>([]);
	let subtotalMinor = $state(0);
	let visitCount = $state(0);
	let scheduleKind = $state<'one_off' | 'recurring'>('one_off');
	let visitsBlock = $state<JobVisitsBlock>();
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);
	let layout = $state<RecordFormLayout>();

	// One idempotency key per save intent: the same details retried keep it, so a double click or a network
	// retry gets the first job back; changed details mint a new one, so a genuine re-save is never mistaken
	// for a replay.
	let idempotencyKey = crypto.randomUUID();
	let lastHash = '';

	function snapshot(values: FormState) {
		return JSON.stringify(values);
	}
	let baseline = $state(untrack(() => snapshot(blankForm())));
	const isDirty = $derived(snapshot(form) !== baseline || lines.length > 0 || visitCount > 0);

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

	// A job's scope is only ever priced product or service work — no headings, notes, or optional add-ons —
	// so the editor's draft lines map straight across, with position set from their order.
	function scopeLines(): JobScopeLineInput[] {
		return lines.map((line, index) => ({
			position: index,
			category: line.category,
			is_labor: line.is_labor,
			source_catalog_item_id: line.catalog_item_id,
			name: line.name,
			description: line.description ?? null,
			unit_label: line.unit_label ?? null,
			quantity: line.quantity,
			unit_price_minor: line.unit_price_minor,
			unit_cost_minor: line.unit_cost_minor,
			is_taxable: line.is_taxable ?? true
		}));
	}

	// A short, stable fingerprint of what the person is saving, so the command can tell a replay of the same
	// job from a fresh one carrying the same key. FNV-1a over the ordered payload keeps it well under the
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

		if (!form.client_id) {
			formError = 'Choose a client to continue.';
			return;
		}
		if (!form.property_id) {
			formError = selectedClient
				? 'This client has no property yet. Add one on their profile before booking a job.'
				: 'Choose a client to continue.';
			return;
		}
		const lineProblem = firstLineProblem(lines);
		if (lineProblem) {
			formError = lineProblem;
			return;
		}
		const collected = visitsBlock?.collect();
		if (!collected || !collected.ok) {
			formError = collected?.message ?? 'Add at least one visit before saving.';
			return;
		}
		// A one-off has to name its days. A recurring job builds its own, and an as-needed one deliberately
		// starts with none, so neither is asked for a visit here.
		if (collected.job_type === 'one_off' && collected.visits.length === 0) {
			formError = 'Add at least one visit before saving.';
			return;
		}

		const core = {
			client_id: form.client_id,
			property_id: form.property_id,
			title: form.title.trim(),
			// Jobber's create form carries no job-level instructions — each visit carries its own — so the
			// command's optional job instructions go in as nothing here.
			instructions: null,
			invoice_on_close: form.invoice_on_close,
			job_type: collected.job_type,
			is_as_needed: collected.is_as_needed,
			recurrence: collected.recurrence,
			lines: scopeLines(),
			visits: collected.visits
		};
		const hash = fingerprint(core);
		if (hash !== lastHash) {
			idempotencyKey = crypto.randomUUID();
			lastHash = hash;
		}

		saving = true;
		try {
			const result = await createJob({
				...core,
				idempotency_key: idempotencyKey,
				request_hash: hash
			});
			await queryClient.invalidateQueries({ queryKey: ['jobs', 'list'] });
			await queryClient.invalidateQueries({ queryKey: jobCountsKey });
			baseline = snapshot(form);
			onSaved({ id: result.job_id, number: result.job_number });
		} catch (caught) {
			const writeError = caught as JobWriteError;
			fieldErrors = writeError.fieldErrors ?? {};
			formError = fieldErrors.form || writeError.message || 'That job could not be saved.';
		} finally {
			saving = false;
		}
	}
</script>

<form
	class="job-form"
	onsubmit={(event) => {
		event.preventDefault();
		void submit().finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout title="New Job" icon={toolsIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			<PrimaryInfoCard
				id="job-primary"
				icon={toolsIcon}
				bind:title={form.title}
				titleRequired
				titleInvalid={Boolean(fieldErrors.title)}
				titleError={fieldErrors.title ?? ''}
			>
				{#snippet client()}
					<ClientPicker
						id="job-client"
						bind:value={form.client_id}
						required
						initialClient={seed?.client ?? null}
						invalid={Boolean(fieldErrors.client_id)}
						errorMessage={fieldErrors.client_id ?? ''}
						onSelect={chooseClient}
					/>
					{#if selectedClient && (selectedClient.additional_property_count > 0 || choosingProperty)}
						{#if choosingProperty}
							<div class="job-form__property">
								<Select
									id="job-property"
									bind:value={form.property_id}
									options={propertyOptions}
									placeholder="Loading properties…"
									label="Property"
								/>
							</div>
						{:else}
							<button
								type="button"
								class="job-form__change-property"
								onclick={() => (choosingProperty = true)}
							>
								Change property
							</button>
						{/if}
					{/if}
				{/snippet}
				{#snippet fields()}
					<Input
						id="job-number"
						label="Job #"
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
				{currencyCode}
				{locale}
				editorTotalLabel="Job subtotal"
				emptyDescription="Add the products and services this job includes."
				onDraftChange={readDraftLines}
			/>

			<JobVisitsBlock
				bind:this={visitsBlock}
				jobTitle={form.title}
				{locale}
				seed={seed?.first_visit ?? null}
				onCountChange={(count) => (visitCount = count)}
				onKindChange={(kind) => (scheduleKind = kind)}
			/>

			<SectionBlock title="Billing" icon={receiptIcon} form>
				{#if scheduleKind === 'recurring'}
					<p class="job-form__billing-note">
						Repeating work is billed on its own schedule. You can set that up on the job once it is
						saved.
					</p>
				{:else}
					<Checkbox
						id="job-invoice-on-close"
						label="Remind me to invoice when I close the job"
						description="The job shows up under “Requires invoicing” once it is done, so it is not forgotten."
						bind:checked={form.invoice_on_close}
					/>
				{/if}
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<QuoteSummaryCard title="Job total" {subtotalMinor} {currencyCode} {locale} />
		{/snippet}

		{#snippet actions()}
			<Button variant="tertiary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>Save Job</Button>
		{/snippet}
	</RecordFormLayout>
</form>

<style lang="scss">
	.job-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__property {
			margin-top: var(--space-small);
		}

		&__billing-note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: 1.45;
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
