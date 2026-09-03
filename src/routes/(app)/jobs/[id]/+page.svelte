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
	import EmptyState from '$lib/components/data-display/EmptyState.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import PencilButton from '$lib/components/ui/PencilButton.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import WorkRecordHeader from '$lib/components/work/WorkRecordHeader.svelte';
	import ClientSummaryCard from '$lib/components/work/ClientSummaryCard.svelte';
	import RecordFactsList from '$lib/components/work/RecordFactsList.svelte';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import QuoteSummaryCard from '$lib/components/quotes/QuoteSummaryCard.svelte';
	import RecordDiscountCard from '$lib/components/work/RecordDiscountCard.svelte';
	import RecordTaxCard from '$lib/components/work/RecordTaxCard.svelte';
	import JobBillingCard from '$lib/components/jobs/JobBillingCard.svelte';
	import JobRemindersCard from '$lib/components/jobs/JobRemindersCard.svelte';
	import JobVisitsSection from '$lib/components/jobs/JobVisitsSection.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		fetchJob,
		jobDetailKey,
		saveJobDetails,
		saveJobLines,
		saveJobDiscount,
		saveJobTax,
		fetchJobEvents,
		jobEventsKey,
		jobCountsKey,
		reopenJob,
		type JobWriteError,
		type JobScopeLineInput
	} from '$lib/jobs/api';
	import type {
		RequestPricingLine,
		RequestPricingLineInput,
		QuoteTaxSource
	} from '$lib/quotes/api';
	import { JOB_STATUS_LABELS, JOB_STATUS_TONES, JOB_TYPE_LABELS } from '$lib/jobs/statuses';
	import briefcaseIcon from '@tabler/icons/outline/briefcase.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock-hour-4.svg?raw';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const jobId = $derived(page.params.id ?? '');

	const jobQuery = createQuery(() => ({
		queryKey: jobDetailKey(jobId),
		queryFn: () => fetchJob(jobId),
		enabled: Boolean(jobId),
		staleTime: 15_000
	}));
	const saved = $derived(jobQuery.data);

	// The title's pencil and the instructions block each stage their own draft; the bottom bar saves both in
	// one command. Every command in this repo guards on a revision, so a stale save is refused rather than
	// clobbering someone else's change.
	let editingTitle = $state(false);
	let titleDraft = $state('');
	let editingInstructions = $state(false);
	let instructionsDraft = $state('');
	let saving = $state(false);
	let saveError = $state('');

	const editable = $derived(Boolean(saved?.can_edit));
	const title = $derived(saved?.job.title?.trim() || `Job #${saved?.job.job_number ?? ''}`);
	const titleChanged = $derived(
		editingTitle && titleDraft.trim() !== (saved?.job.title?.trim() ?? '')
	);
	const instructionsChanged = $derived(
		editingInstructions && instructionsDraft.trim() !== (saved?.job.instructions?.trim() ?? '')
	);
	const showInstructions = $derived(editingInstructions || Boolean(saved?.job.instructions));

	const isEditing = $derived(editingTitle || editingInstructions);
	const isDirty = $derived(titleChanged || instructionsChanged);

	// The read-only scope lines, mapped into the same shape the shared pricing block draws for a quote.
	const jobLines = $derived<RequestPricingLine[]>(
		(saved?.lines ?? []).map((line) => ({
			...line,
			catalog_item_id: line.source_catalog_item_id,
			// A job's scope is always priced product or service work — it carries no text or heading lines —
			// so category and quantity are never actually null; the fallbacks only satisfy the shared type.
			category: line.category ?? 'service',
			quantity: line.quantity ?? 0,
			unit_price_minor: line.unit_price_minor ?? 0,
			unit_cost_minor: line.unit_cost_minor ?? 0,
			line_total_minor: line.line_total_minor ?? 0,
			line_cost_total_minor: line.line_cost_total_minor ?? 0
		}))
	);

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
	const headerFacts = $derived([
		{ label: 'Job #', value: saved ? String(saved.job.job_number) : null },
		{ label: 'Type', value: saved ? JOB_TYPE_LABELS[saved.job.job_type] : null },
		{
			label: 'Created',
			value: saved ? dateTimeFormat.format(new Date(saved.job.created_at)) : null
		},
		...(saved?.job.from_quote ? [{ label: 'Source', value: 'From a quote' }] : [])
	]);

	const propertyLine = $derived.by(() => {
		const property = saved?.job.property;
		if (!property) return null;
		return [
			property.address_line1,
			property.address_line2,
			property.city,
			property.state_region,
			property.postal_code
		]
			.filter(Boolean)
			.join(', ');
	});

	const clientMenuItems = $derived(
		saved?.job.client
			? [
					{
						label: 'View client profile',
						onSelect: () => void goto(resolve('/(app)/clients/[id]', { id: saved.job.client!.id }))
					}
				]
			: []
	);

	// --- History ----------------------------------------------------------------------------------------
	// Jobber swaps the rail for the history panel rather than opening it beside everything else. Nothing
	// about it loads with the page: hovering the button starts the fetch, so it is usually already there by
	// the time the click lands.
	let showHistory = $state(false);

	const eventsQuery = createQuery(() => ({
		queryKey: jobEventsKey(jobId),
		queryFn: () => fetchJobEvents(jobId),
		enabled: Boolean(jobId) && showHistory,
		staleTime: 15_000
	}));

	function warmHistory() {
		if (!jobId) return;
		void queryClient.prefetchQuery({
			queryKey: jobEventsKey(jobId),
			queryFn: () => fetchJobEvents(jobId)
		});
	}

	const EVENT_LABELS: Record<string, string> = {
		job_created: 'Job created',
		details_updated: 'Details updated',
		visits_added: 'Visits added',
		visit_updated: 'Visit updated',
		visits_moved: 'Visits moved',
		visit_deleted: 'Visit deleted',
		schedule_replaced: 'Schedule changed',
		visits_updated_forward: 'Later visits updated'
	};

	function eventLabel(type: string) {
		return EVENT_LABELS[type] ?? type.replace(/_/g, ' ');
	}

	function eventDetail(event: { event_type: string; metadata: Record<string, unknown> }) {
		if (event.event_type === 'details_updated') {
			const changed = event.metadata.changed;
			if (Array.isArray(changed) && changed.length > 0) {
				return `Changed ${changed.join(' and ')}`;
			}
		}
		if (event.event_type === 'visits_added') {
			const count = event.metadata.count;
			if (typeof count === 'number') return `${count} ${count === 1 ? 'visit' : 'visits'} added`;
		}
		if (event.event_type === 'visit_updated') {
			const changed = event.metadata.changed;
			if (Array.isArray(changed) && changed.length > 0) {
				return `Changed ${changed.join(' and ')}`;
			}
		}
		if (event.event_type === 'visits_moved') {
			const count = event.metadata.count;
			const dayOffset = event.metadata.day_offset;
			if (typeof count === 'number' && typeof dayOffset === 'number') {
				const direction = dayOffset > 0 ? 'later' : 'earlier';
				return `${count} ${count === 1 ? 'visit' : 'visits'} moved ${Math.abs(dayOffset)} ${Math.abs(dayOffset) === 1 ? 'day' : 'days'} ${direction}`;
			}
		}
		if (event.event_type === 'schedule_replaced') {
			const created = event.metadata.created_count;
			const removed = event.metadata.removed_count;
			if (typeof created === 'number' && typeof removed === 'number') {
				return `${created} ${created === 1 ? 'visit' : 'visits'} created, ${removed} removed`;
			}
		}
		if (event.event_type === 'visits_updated_forward') {
			const count = event.metadata.count;
			if (typeof count === 'number') {
				return `${count} later ${count === 1 ? 'visit' : 'visits'} updated`;
			}
		}
		return null;
	}

	// --- Pricing ----------------------------------------------------------------------------------------
	// The scope block, the discount card and the tax card each own a piece of the job's money and each write
	// on their own button, the way they already do on a quote. They are not part of the page's staged title
	// and instructions draft, so the bottom save bar never appears for them.
	//
	// The block speaks the quote's dialect — `catalog_item_id`, optional add-on fields — so the job's own
	// column name is put back here. A job carries no headings or notes, so anything that is not a priced
	// line is dropped rather than sent to a command that would refuse it.
	async function saveScope(expectedRevision: number, lines: RequestPricingLineInput[]) {
		const scope: JobScopeLineInput[] = lines
			.filter((line) => (line.line_kind ?? 'priced') === 'priced')
			.map((line, index) => ({
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
				image_attachment_id: line.image_attachment_id ?? null
			}));

		await saveJobLines(jobId, expectedRevision, scope);
		await refreshJob();
		toast.success('Scope saved');
	}

	// --- Saving -----------------------------------------------------------------------------------------
	function discard() {
		editingTitle = false;
		titleDraft = '';
		editingInstructions = false;
		instructionsDraft = '';
		saveError = '';
	}

	async function refreshJob() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: jobDetailKey(jobId) }),
			queryClient.invalidateQueries({ queryKey: jobEventsKey(jobId) }),
			queryClient.invalidateQueries({ queryKey: ['jobs', 'list'] }),
			queryClient.invalidateQueries({ queryKey: jobCountsKey })
		]);
	}

	// The other direction of "Finish job" (Part 13a): a closed job is not a dead end. Removed visits do not
	// regenerate — scheduling more is its own explicit action, once the job is active again.
	let reopening = $state(false);

	async function reopen() {
		if (!saved || reopening) return;
		reopening = true;
		try {
			await reopenJob(jobId, saved.job.revision);
			await refreshJob();
			toast.success('Job reopened');
		} catch (caught) {
			toast.error((caught as JobWriteError).message ?? 'That job could not be reopened.');
		} finally {
			reopening = false;
		}
	}

	async function save() {
		if (!saved || saving || !isDirty) return;
		saving = true;
		saveError = '';
		try {
			await saveJobDetails(jobId, saved.job.revision, {
				title: titleChanged ? titleDraft.trim() : saved.job.title,
				instructions: editingInstructions
					? instructionsDraft.trim() || null
					: saved.job.instructions
			});
			discard();
			await refreshJob();
			toast.success('Job saved');
		} catch (caught) {
			const writeError = caught as JobWriteError;
			if (writeError.reason === 'stale') {
				discard();
				await refreshJob();
				saveError = 'Someone else changed this job. The latest version is now on screen.';
			} else {
				saveError =
					writeError.fieldErrors?.form ?? writeError.message ?? 'Those changes could not be saved.';
			}
		} finally {
			saving = false;
		}
	}
</script>

<svelte:head><title>{title || 'Job'} · Contractor CRM</title></svelte:head>

<!-- eslint-disable svelte/no-at-html-tags -->
<PageContainer>
	{#if jobQuery.isPending}
		<LoadingSkeleton variant="card" label="Loading job" />
	{:else if jobQuery.isError}
		<ErrorState description="That job could not be loaded. Refresh and try again." />
	{:else if saved}
		<RecordDetailLayout
			class="job-detail"
			editing={isEditing}
			dirty={isDirty}
			{saving}
			error={saveError}
			onSave={() => void save()}
			onCancel={discard}
		>
			{#snippet main()}
				<WorkRecordHeader
					icon={briefcaseIcon}
					recordType="Job"
					{title}
					statusLabel={JOB_STATUS_LABELS[saved.job.derived_status]}
					statusTone={JOB_STATUS_TONES[saved.job.derived_status]}
					onHistory={() => (showHistory = !showHistory)}
					onHistoryHover={warmHistory}
					onEditTitle={editable
						? () => {
								titleDraft = saved.job.title;
								editingTitle = true;
							}
						: undefined}
					{editingTitle}
					bind:titleDraft
				>
					{#snippet summary()}
						<ClientSummaryCard
							name={saved.job.client?.display_name ?? 'No client'}
							href={saved.job.client
								? resolve('/(app)/clients/[id]', { id: saved.job.client.id })
								: undefined}
							addresses={[{ value: propertyLine, empty: 'No property on this job' }]}
							phone={saved.job.client?.phone}
							email={saved.job.client?.email}
							menuItems={clientMenuItems}
						/>
					{/snippet}
					{#snippet facts()}<RecordFactsList facts={headerFacts} />{/snippet}
					{#snippet badges()}
						{#if saved.job.status === 'closed' && saved.can_close}
							<Button size="small" variant="tertiary" onclick={() => void reopen()} loading={reopening}>
								Reopen job
							</Button>
						{/if}
					{/snippet}
				</WorkRecordHeader>

				<ProductsAndServicesBlock
					lines={jobLines}
					revision={saved.job.revision}
					editable={editable && saved.can_see_price}
					showPrices={saved.can_see_price}
					subtotalMinor={saved.can_see_price ? (saved.money?.subtotal_minor ?? 0) : null}
					currencyCode={saved.job.currency_code}
					locale={saved.locale}
					editorTotalLabel="Job subtotal"
					saveLabel="Save scope"
					emptyDescription="Add the products and services this job covers."
					onSave={saveScope}
				/>

				<JobVisitsSection
					jobId={saved.job.id}
					visits={saved.visits}
					jobTitle={title}
					locale={saved.locale}
					canSchedule={saved.can_schedule}
					canComplete={saved.can_complete}
					canClose={saved.can_close}
					jobStatus={saved.job.status}
					jobType={saved.job.job_type}
					isAsNeeded={saved.job.is_as_needed}
					recurrence={saved.recurrence}
					jobRevision={saved.job.revision}
				/>

				{#if showInstructions}
					<SectionBlock title="Instructions" icon={notesIcon} level={2} form={editingInstructions}>
						{#snippet actions()}
							{#if editable && !editingInstructions}
								<PencilButton
									onclick={() => {
										instructionsDraft = saved.job.instructions ?? '';
										editingInstructions = true;
									}}
									label="Edit the instructions"
								/>
							{:else if instructionsChanged}
								<Badge size="small" status="warning">Unsaved</Badge>
							{/if}
						{/snippet}

						{#if editingInstructions}
							<Textarea
								id="job-instructions"
								label="Notes for the crew doing this work"
								rows={5}
								maxlength={4000}
								bind:value={instructionsDraft}
							/>
						{:else if saved.job.instructions}
							<p class="job-detail__copy">{saved.job.instructions}</p>
						{:else}
							<EmptyState
								icon={notesIcon}
								title="No instructions"
								description="Add notes the crew should read before this work."
							/>
						{/if}
					</SectionBlock>
				{/if}
			{/snippet}

			{#snippet rail()}
				{#if showHistory}
					<RailCard title="Job history" icon={clockIcon}>
						{#snippet actions()}
							<Button size="small" variant="tertiary" onclick={() => (showHistory = false)}>
								Close
							</Button>
						{/snippet}
						{#if eventsQuery.isPending}
							<LoadingSkeleton variant="text" label="Loading history" />
						{:else if eventsQuery.isError}
							<p class="job-history__empty">That history could not be loaded.</p>
						{:else if (eventsQuery.data ?? []).length === 0}
							<p class="job-history__empty">Nothing has happened on this job yet.</p>
						{:else}
							<ol class="job-history">
								{#each eventsQuery.data ?? [] as event (event.id)}
									<li class="job-history__item">
										<p class="job-history__title">{eventLabel(event.event_type)}</p>
										{#if eventDetail(event)}
											<p class="job-history__detail">{eventDetail(event)}</p>
										{/if}
										<p class="job-history__meta">
											{event.actor_name ?? 'Someone'} ·
											{dateTimeFormat.format(new Date(event.created_at))}
										</p>
									</li>
								{/each}
							</ol>
						{/if}
					</RailCard>
				{/if}

				<QuoteSummaryCard
					title="Job total"
					subtotalMinor={saved.can_see_price ? (saved.money?.subtotal_minor ?? 0) : null}
					discountMinor={saved.money?.discount_minor ?? 0}
					taxMinor={saved.money?.tax_minor ?? 0}
					totalMinor={saved.money?.total_minor ?? null}
					discountLabel={saved.money?.discount_name ?? null}
					taxLabel={saved.money?.tax_name ?? null}
					costMinor={saved.can_see_cost ? (saved.money?.cost_minor ?? null) : null}
					profitMinor={saved.can_see_cost ? (saved.money?.profit_minor ?? null) : null}
					currencyCode={saved.job.currency_code}
					locale={saved.locale}
				/>

				<JobBillingCard
					jobId={saved.job.id}
					revision={saved.job.revision}
					jobType={saved.job.job_type}
					priceBasis={saved.job.price_basis}
					billingTiming={saved.job.billing_timing}
					totalMinor={saved.can_see_price ? (saved.money?.total_minor ?? null) : null}
					currencyCode={saved.job.currency_code}
					locale={saved.locale}
					{editable}
					canSeePrice={saved.can_see_price}
					onSaved={refreshJob}
				/>

				<JobRemindersCard
					jobId={saved.job.id}
					reminders={saved.reminders}
					today={saved.organization_today}
					locale={saved.locale}
					{editable}
					onChanged={refreshJob}
				/>

				<RecordDiscountCard
					revision={saved.job.revision}
					name={saved.money?.discount_name ?? null}
					type={saved.money?.discount_type ?? null}
					value={saved.money?.discount_value ?? null}
					discountMinor={saved.can_see_price ? (saved.money?.discount_minor ?? 0) : null}
					currencyCode={saved.job.currency_code}
					locale={saved.locale}
					{editable}
					canSeePrice={saved.can_see_price}
					recordNoun="job"
					onSave={(revision, payload) => saveJobDiscount(jobId, revision, payload)}
					onSaved={refreshJob}
				/>

				{#if saved.job.property}
					<RecordTaxCard
						revision={saved.job.revision}
						propertyId={saved.job.property.id}
						taxSource={(saved.money?.tax_source ?? 'not_configured') as QuoteTaxSource}
						rateId={saved.money?.tax_rate_id ?? null}
						name={saved.money?.tax_name ?? null}
						rateBasisPoints={saved.money?.tax_rate_basis_points ?? 0}
						taxMinor={saved.can_see_price ? (saved.money?.tax_minor ?? 0) : null}
						currencyCode={saved.job.currency_code}
						locale={saved.locale}
						{editable}
						canSeePrice={saved.can_see_price}
						canManageTaxes={saved.can_manage_taxes}
						recordNoun="job"
						unsetHint="This job is not taxed yet."
						onSave={(revision, payload) => saveJobTax(jobId, revision, payload)}
						onSaved={refreshJob}
					/>
				{/if}
			{/snippet}
		</RecordDetailLayout>
	{/if}
</PageContainer>

<style lang="scss">
	.job-history {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		margin: 0;
		padding: 0;
		list-style: none;

		&__item {
			display: flex;
			flex-direction: column;
			gap: var(--space-smallest);
			padding-bottom: var(--space-base);

			& + & {
				border-top: var(--border-base) solid var(--color-border);
				padding-top: var(--space-base);
			}
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__detail {
			margin: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
		}

		&__meta {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__empty {
			margin: 0;
			color: var(--color-text--secondary);
		}
	}

	.job-detail__copy {
		margin: 0;
		color: var(--color-text);
		line-height: var(--typography--lineHeight-large);
		white-space: pre-wrap;
	}
</style>
