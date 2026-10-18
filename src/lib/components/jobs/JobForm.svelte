<script lang="ts">
	import { setContext, untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import NotifyCustomerCheckbox from '$lib/components/schedule/NotifyCustomerCheckbox.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { customerNoticeToast } from '$lib/schedule/customer-notices';
	import PickedClient from '$lib/components/work/PickedClient.svelte';
	import MoneyFeatureCard from '$lib/components/work/MoneyFeatureCard.svelte';
	import ClientPicker from '$lib/components/work/ClientPicker.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import JobVisitsBlock from '$lib/components/jobs/JobVisitsBlock.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import { resolve } from '$app/paths';
	import { requestDetailKey, requestCountsKey } from '$lib/requests/api';
	import { requestPricingKey } from '$lib/quotes/api';
	import { activityKey } from '$lib/collaboration/api';
	import { invalidatePipeline } from '$lib/pipeline/api';
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
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import packageIcon from '@tabler/icons/outline/package.svg?raw';
	import receiptIcon from '@tabler/icons/outline/file-dollar.svg?raw';
	import cashIcon from '@tabler/icons/outline/cash-banknote.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';
	import inboxIcon from '@tabler/icons/outline/inbox.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';

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
		onSaved: (job: { id: string; number: number; fromRequest: boolean }) => void;
		onCancel: () => void;
		currencyCode?: string;
		locale?: string;
		/** A draft handed over from Schedule's compact create form via More Options, or from "Convert to job"
		 * on a request: the client, property, title and work the person already chose, so the full form opens
		 * filled instead of blank. */
		seed?: JobCreateSeed | null;
	} = $props();

	const queryClient = useQueryClient();
	// The job concept (New job `zUFDO`): every block on this form is its own card with the shared Card header.
	setContext('concept-job-details', true);

	// "Convert to job" on a request, the way Jobber does it: this same form, filled in from the request.
	// Nothing about the request changes until the job saves — that one save converts it.
	const sourceRequest = untrack(() => seed?.request ?? null);

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
	// Client reminders Part 4: the "Notify customer" box, ticked by default; it only shows while the booking
	// confirmation is switched on.
	let notifyCustomer = $state(true);
	let noticeVisible = $state(false);
	const toast = getToastManager();
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

	// Most clients have one property, so this only asks which when there is a real choice to make. Once
	// asked, the list stays loaded so the chosen property's address can be shown in the client box.
	let propertiesWanted = $state(false);
	const clientPropertiesQuery = createQuery(() => ({
		queryKey: clientDetailKey(selectedClient?.id ?? ''),
		queryFn: () => fetchClient(selectedClient!.id),
		enabled: propertiesWanted && Boolean(selectedClient),
		staleTime: 15_000
	}));
	const propertyOptions = $derived(
		(clientPropertiesQuery.data?.properties ?? []).map((property) => ({
			value: property.id,
			label: property.label || [property.address_line1, property.city].filter(Boolean).join(', ')
		}))
	);

	// "Change client" swaps the client box back to the search field until someone else is picked.
	let changingClient = $state(false);

	function addressLine(property: {
		address_line1: string;
		city: string;
		state_region: string | null;
		postal_code: string | null;
	}) {
		const region = [property.state_region, property.postal_code].filter(Boolean).join(' ');
		return [property.address_line1, property.city, region].filter(Boolean).join(', ');
	}

	function firstName(name: string) {
		return name.trim().split(/\s+/)[0] ?? name;
	}

	// The property the job is at, read from the client's full list once it has loaded and from the
	// client's primary property before then.
	const jobProperty = $derived.by(() => {
		const listed = clientPropertiesQuery.data?.properties.find(
			(property) => property.id === form.property_id
		);
		const primary = selectedClient?.primary_property;
		const property = listed ?? (primary && primary.id === form.property_id ? primary : null);
		return property ? { line: addressLine(property), label: property.label } : null;
	});
	const propertyCount = $derived(selectedClient ? 1 + selectedClient.additional_property_count : 0);
	const propertyHint = $derived.by(() => {
		if (!selectedClient) return '';
		const parts = [jobProperty?.label ?? ''];
		if (sourceRequest) parts.push('the property on the request');
		else if (propertyCount > 1) {
			parts.push(`${firstName(selectedClient.display_name)} has ${propertyCount} properties`);
		}
		return parts.filter(Boolean).join(' · ');
	});

	function chooseClient(client: ClientListItem | null) {
		selectedClient = client;
		form.property_id = client?.primary_property?.id ?? '';
		choosingProperty = false;
		if (client) changingClient = false;
	}

	function changeProperty() {
		propertiesWanted = true;
		choosingProperty = true;
	}

	// The rail's Job total card lists each line with the same preview arithmetic the line editor shows; the
	// database works out the real figures when the job saves.
	const money = $derived(
		new Intl.NumberFormat(locale, { style: 'currency', currency: currencyCode })
	);
	// The card keys its rows by label, so a name used twice is numbered.
	const railRows = $derived.by(() => {
		const seen = new Map<string, number>();
		return lines
			.filter((line) => line.name.trim())
			.map((line) => {
				const name = line.name.trim();
				const times = (seen.get(name) ?? 0) + 1;
				seen.set(name, times);
				return {
					label: times > 1 ? `${name} (${times})` : name,
					value: money.format(Math.round(line.quantity * line.unit_price_minor) / 100)
				};
			});
	});

	// What the save bar says will happen besides saving the job.
	const saveHint = $derived.by(() => {
		if (sourceRequest) return 'The request is marked Converted when you save';
		if (selectedClient && notifyCustomer && noticeVisible && scheduleKind === 'one_off') {
			return `${firstName(selectedClient.display_name)} gets the booking email when you save`;
		}
		return '';
	});

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
			is_taxable: line.is_taxable ?? true,
			// Only a photo already on the source request's lines survives; the command drops any other.
			...(sourceRequest ? { image_file_id: line.image_file_id ?? null } : {})
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

	// The request is now Converted and its Pipeline card Won, so everything that showed it as live work —
	// the request itself, its list and counts, its history, the board and the Won tile — is out of date.
	async function refreshSourceRequest(requestId: string) {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: requestDetailKey(requestId) }),
			queryClient.invalidateQueries({ queryKey: requestPricingKey(requestId) }),
			queryClient.invalidateQueries({ queryKey: ['requests', 'list'] }),
			queryClient.invalidateQueries({ queryKey: requestCountsKey }),
			queryClient.invalidateQueries({ queryKey: activityKey('request', requestId) }),
			invalidatePipeline(queryClient)
		]);
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
			...(sourceRequest ? { request_id: sourceRequest.id } : {}),
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
				request_hash: hash,
				notify_customer: notifyCustomer && noticeVisible
			});
			const noticeMessage = customerNoticeToast(result.customer_notice);
			if (noticeMessage) toast.info(noticeMessage);
			await queryClient.invalidateQueries({ queryKey: ['jobs', 'list'] });
			await queryClient.invalidateQueries({ queryKey: jobCountsKey });
			if (sourceRequest) await refreshSourceRequest(sourceRequest.id);
			baseline = snapshot(form);
			onSaved({
				id: result.job_id,
				number: result.job_number,
				fromRequest: Boolean(sourceRequest)
			});
		} catch (caught) {
			const writeError = caught as JobWriteError;
			fieldErrors = writeError.fieldErrors ?? {};
			formError = fieldErrors.form || writeError.message || 'That job could not be saved.';
			// Somebody converted the request while this form was open; what the request page shows is stale.
			if (sourceRequest && writeError.reason === 'already_converted') {
				void refreshSourceRequest(sourceRequest.id);
			}
		} finally {
			saving = false;
		}
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<form
	class="job-form"
	onsubmit={(event) => {
		event.preventDefault();
		void submit().finally(() => layout?.revealError());
	}}
>
	<RecordFormLayout
		concept
		title="New job"
		description="Who it is for, what you will do and when. Deposits, notes and files are added on the job once it is saved."
		icon={hammerIcon}
		tone="job"
		bind:this={layout}
		error={formError}
	>
		{#snippet headerAside()}
			<span class="job-form__number">
				<span class="job-form__number-tile" aria-hidden="true">{@html hashIcon}</span>
				<span class="job-form__number-label">Job #</span>
				Given when you save
			</span>
		{/snippet}

		{#snippet main()}
			{#if sourceRequest}
				<div class="job-form__request" role="note">
					<span class="job-form__request-tile" aria-hidden="true">{@html inboxIcon}</span>
					<div class="job-form__request-copy">
						<p class="job-form__request-title">
							Turning the request “{sourceRequest.title}” into a job
						</p>
						<p>The request is marked Converted when you save.</p>
					</div>
					<Button
						variant="secondary"
						size="small"
						href={resolve('/(app)/requests/[id=uuid]', { id: sourceRequest.id })}
						target="_blank"
					>
						<span class="job-form__button-icon" aria-hidden="true">{@html externalLinkIcon}</span>
						View request
					</Button>
				</div>
			{/if}

			<SectionBlock
				id="job-primary"
				title="The job"
				subtitle="What the work is and who it is for"
				icon={hammerIcon}
				tone="job"
			>
				<div class="job-form__fields concept-fields">
					<Input
						id="job-primary-title"
						label="Job title"
						bind:value={form.title}
						required
						invalid={Boolean(fieldErrors.title)}
						errorMessage={fieldErrors.title ?? ''}
					/>

					{#if selectedClient && !changingClient}
						<div class="job-form__client">
							<span class="job-form__label">Client <span aria-hidden="true">*</span></span>
							<PickedClient
								id={selectedClient.id}
								name={selectedClient.display_name}
								subtitle={selectedClient.company_name !== selectedClient.display_name
									? selectedClient.company_name
									: null}
								phone={selectedClient.phone}
								email={selectedClient.email}
								property={jobProperty?.line ??
									(form.property_id ? 'Loading the property…' : 'No property yet')}
								{propertyHint}
								lockedReason={sourceRequest ? 'From the request' : undefined}
								onChangeClient={sourceRequest ? undefined : () => (changingClient = true)}
								onChangeProperty={!sourceRequest && propertyCount > 1 ? changeProperty : undefined}
								propertyPicker={choosingProperty ? propertyPicker : undefined}
							/>
						</div>
					{:else}
						<div class="job-form__client">
							<ClientPicker
								id="job-client"
								bind:value={form.client_id}
								required
								initialClient={null}
								invalid={Boolean(fieldErrors.client_id)}
								errorMessage={fieldErrors.client_id ?? ''}
								onSelect={chooseClient}
							/>
							{#if changingClient && selectedClient}
								<div class="job-form__keep">
									<Button variant="quiet" size="small" onclick={() => (changingClient = false)}>
										Keep {selectedClient.display_name}
									</Button>
								</div>
							{/if}
						</div>
					{/if}
				</div>
			</SectionBlock>

			<ProductsAndServicesBlock
				lines={sourceRequest?.lines ?? []}
				alwaysEditing
				editable
				concept
				flush
				icon={packageIcon}
				tone="quote"
				hint={lines.length > 1
					? `${lines.length} lines · drag ⠿ to reorder`
					: `${lines.length} ${lines.length === 1 ? 'line' : 'lines'}`}
				{currencyCode}
				{locale}
				editorTotalLabel="Job subtotal"
				emptyDescription="Add the products and services this job includes."
				onDraftChange={readDraftLines}
			>
				{#snippet conceptTotals()}
					<p class="job-form__totals-note">
						Discount and tax are added on the job once it is saved.
					</p>
				{/snippet}
			</ProductsAndServicesBlock>

			<JobVisitsBlock
				bind:this={visitsBlock}
				jobTitle={form.title}
				{locale}
				seed={seed?.first_visit ?? null}
				onCountChange={(count) => (visitCount = count)}
				onKindChange={(kind) => (scheduleKind = kind)}
			>
				{#snippet footer()}
					<div
						class="job-form__notify concept-fields"
						class:job-form__notify--shown={noticeVisible}
					>
						<NotifyCustomerCheckbox
							id="job-notify-customer"
							bind:checked={notifyCustomer}
							bind:visible={noticeVisible}
							kinds={['booked']}
						/>
					</div>
				{/snippet}
			</JobVisitsBlock>

			<SectionBlock
				title="Billing"
				subtitle="How this job gets invoiced"
				icon={receiptIcon}
				tone="invoice"
			>
				{#if scheduleKind === 'recurring'}
					<p class="job-form__billing-note">
						Repeating work is billed on its own schedule. You can set that up on the job once it is
						saved.
					</p>
				{:else}
					<div class="concept-fields">
						<Checkbox
							id="job-invoice-on-close"
							label="Remind me to invoice when I close the job"
							description="The job shows up under “Requires invoicing” once it is done, so it is not forgotten."
							bind:checked={form.invoice_on_close}
						/>
					</div>
				{/if}
			</SectionBlock>
		{/snippet}

		{#snippet rail()}
			<MoneyFeatureCard
				eyebrow="Job total"
				icon={cashIcon}
				value={money.format(subtotalMinor / 100)}
				note="Job subtotal, before discount and tax"
				rows={railRows}
				footnote="Updates as you add or change lines."
				record
			/>
		{/snippet}

		{#snippet status()}
			<span class="job-form__status-dot" aria-hidden="true"></span>
			<span class="job-form__status-text">New job · not saved yet</span>
			{#if saveHint}<span class="job-form__status-hint">{saveHint}</span>{/if}
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={onCancel} disabled={saving}>Cancel</Button>
			<Button variant="primary" type="submit" loading={saving} disabled={!isDirty}>
				<span class="job-form__button-icon" aria-hidden="true">{@html checkIcon}</span>
				Save job
			</Button>
		{/snippet}
	</RecordFormLayout>
</form>

{#snippet propertyPicker()}
	<Select
		id="job-property"
		bind:value={form.property_id}
		options={propertyOptions}
		placeholder="Loading properties…"
		label="Property"
		onchange={() => (choosingProperty = false)}
	/>
{/snippet}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.job-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__fields {
			display: flex;
			flex-direction: column;
			gap: var(--space-medium);
		}

		&__client {
			display: flex;
			flex-direction: column;
			gap: 6px;
		}

		&__label {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;

			span {
				color: var(--color-critical);
			}
		}

		&__keep {
			display: flex;
		}

		&__button-icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 16px;
				height: 16px;
			}
		}

		// The "Job #" pill at the right of the page header: the number is the database's, given on save.
		&__number {
			display: inline-flex;
			align-items: center;
			gap: var(--space-small);
			padding: 6px var(--space-slim) 6px 6px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-circle);
			color: var(--color-text--secondary);
			background: var(--color-surface);
			font-size: var(--typography--fontSize-small);
		}

		&__number-tile {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			width: 24px;
			height: 24px;
			border-radius: var(--radius-circle);
			color: var(--color-job);
			background: var(--color-job--surface);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__number-label {
			color: var(--color-heading);
			font-weight: 600;
		}

		// "From a request": a request-coloured strip above the form, saying what saving will do.
		&__request {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-slim) var(--space-slim) var(--space-base);
			border-radius: var(--radius-large);
			color: var(--color-request--onSurface);
			background: var(--color-request--surface);
			font-size: var(--typography--fontSize-small);
		}

		&__request-tile {
			display: inline-flex;
			flex: 0 0 auto;
			align-items: center;
			justify-content: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
			color: var(--color-request);
			background: var(--color-surface);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__request-copy {
			flex: 1 1 auto;
			min-width: 0;
		}

		&__request-title {
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__totals-note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		// The Notify customer box closes the Visits card under a hairline, once it shows.
		&__notify--shown {
			margin-top: var(--space-smaller);
			border-top: var(--border-base) solid var(--color-border);

			:global(.notify-customer) {
				padding-top: var(--space-base);
			}
		}

		&__billing-note {
			margin: 0;
			color: var(--color-text);
		}

		&__status-dot {
			flex: 0 0 auto;
			width: 8px;
			height: 8px;
			border-radius: var(--radius-circle);
			background: var(--color-warning);
		}

		&__status-text {
			flex: 0 0 auto;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__status-hint {
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			text-overflow: ellipsis;
			white-space: nowrap;
		}
	}
</style>
