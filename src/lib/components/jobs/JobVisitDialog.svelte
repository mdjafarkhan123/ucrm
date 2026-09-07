<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import TeamPicker from '$lib/components/team/TeamPicker.svelte';
	import {
		calendarDateFromString,
		calendarDateToString,
		timeFromString,
		timeToString,
		emptyDateTimePickerValue,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import ProductsAndServicesBlock from '$lib/components/quotes/ProductsAndServicesBlock.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import type { RequestPricingLineInput } from '$lib/quotes/api';
	import type { JobVisit, JobVisitLines, UpdateVisitInput } from '$lib/jobs/api';

	// Editing one existing visit, the way a client's property is edited: its own modal with its own Save, kept
	// out of the page's title/instructions draft. The dialog only shapes the visit and hands the result back;
	// the section that owns the list does the write, so saving state and server errors come in as props. It is
	// used from the Job page and from Schedule's move/reschedule path; creating a job and its first visit is a
	// separate flow that lives in ScheduleJobCreate and the New Job page.
	let {
		open,
		visit,
		jobTitle = '',
		locale = 'en-US',
		isRecurring = false,
		saving = false,
		error = '',
		perVisitPricing = false,
		pricing = null,
		pricingLoading = false,
		pricingFailed = false,
		canEditPricing = false,
		canSeePrice = true,
		currencyCode = 'USD',
		onSave,
		onSaveFuture,
		onClose
	}: {
		open: boolean;
		visit: JobVisit | null;
		jobTitle?: string;
		locale?: string;
		// A recurring job's visit can carry its settings forward; the section wires the follow-up dialog.
		isRecurring?: boolean;
		saving?: boolean;
		error?: string;
		/** Invoices 5c-5: only a recurring job billed per visit prices its visits one at a time. */
		perVisitPricing?: boolean;
		/** This visit's effective lines, loaded when the dialog is opened. Null while it has not arrived. */
		pricing?: JobVisitLines | null;
		pricingLoading?: boolean;
		pricingFailed?: boolean;
		canEditPricing?: boolean;
		canSeePrice?: boolean;
		currencyCode?: string;
		// The pricing argument is what to write for this visit's own lines: an array replaces them, an empty
		// array puts the visit back on the job's lines, and null means nobody touched them.
		onSave: (payload: UpdateVisitInput, pricing: RequestPricingLineInput[] | null) => void;
		onSaveFuture?: (payload: UpdateVisitInput, pricing: RequestPricingLineInput[] | null) => void;
		onClose: () => void;
	} = $props();

	let title = $state('');
	let scheduleLater = $state(false);
	let anytime = $state(false);
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let instructions = $state('');
	let assigneeIds = $state<string[]>([]);
	let fieldError = $state('');
	// The pricing editor types into its own draft and this dialog's Save writes it, so one press saves the
	// visit rather than leaving a half-saved appointment behind two buttons.
	let pricingDraft = $state<RequestPricingLineInput[] | null>(null);
	// "Use the job's lines again" is staged like everything else here: it takes effect on Save, as an empty
	// set, which is what clears a visit's own pricing.
	let resettingPricing = $state(false);

	// Re-read the visit into the form each time the dialog opens, never while it is open, so typing is never
	// overwritten by a background refetch or a re-render.
	let wasOpen = false;
	$effect(() => {
		if (open && !wasOpen && visit) {
			title = visit.title ?? '';
			scheduleLater = visit.visit_date === null;
			anytime = visit.visit_date !== null && !visit.start_time;
			when = {
				date: calendarDateFromString(visit.visit_date),
				startTime: timeFromString(visit.start_time),
				endTime: timeFromString(visit.end_time)
			};
			instructions = visit.instructions ?? '';
			assigneeIds = [...visit.assignee_ids];
			fieldError = '';
			pricingDraft = null;
			resettingPricing = false;
		}
		wasOpen = open;
	});

	// The editor is only offered where it means something: a job billed per visit, a visit whose work is not
	// already recorded or billed, and a member who may edit the job's money.
	const pricingEditable = $derived(
		canEditPricing && canSeePrice && pricing !== null && !pricing.locked
	);
	const savedPricingLines = $derived(pricing?.lines ?? []);

	// What the pricing editor holds, reduced to the fields that actually bill, so reopening a dialog and
	// changing nothing does not rewrite the visit's lines and bump its revision.
	function pricingFingerprint(lines: RequestPricingLineInput[]) {
		return JSON.stringify(
			lines.map((line) => [
				line.name.trim(),
				line.category,
				line.quantity,
				line.unit_price_minor,
				line.is_taxable ?? true,
				line.description ?? '',
				line.unit_label ?? '',
				line.source_job_line_item_id ?? null
			])
		);
	}

	const savedFingerprint = $derived(
		pricingFingerprint(
			savedPricingLines.map((line) => ({
				name: line.name,
				category: line.category,
				is_labor: line.is_labor,
				catalog_item_id: line.catalog_item_id,
				description: line.description,
				unit_label: line.unit_label,
				quantity: line.quantity,
				unit_price_minor: line.unit_price_minor,
				unit_cost_minor: line.unit_cost_minor,
				is_taxable: line.is_taxable,
				source_job_line_item_id: line.source_job_line_item_id ?? null
			}))
		)
	);

	// Null unless there is really something to write: an empty set to clear the override, or a changed set.
	function pricingToSave(): RequestPricingLineInput[] | null {
		if (!pricingEditable) return null;
		if (resettingPricing) return pricing?.has_override ? [] : null;
		if (pricingDraft === null) return null;
		return pricingFingerprint(pricingDraft) === savedFingerprint ? null : pricingDraft;
	}

	// The same shape rules the create form and the database enforce, checked here so a bad combination is a
	// message in the dialog rather than a raw constraint bounced back from the write.
	function collect(): UpdateVisitInput | null {
		const base = {
			title: title.trim() || null,
			instructions: instructions.trim() || null,
			assignee_ids: assigneeIds
		};
		if (scheduleLater) {
			return { ...base, visit_date: null, start_time: null, end_time: null, all_day: false };
		}
		const day = calendarDateToString(when.date);
		if (!day) {
			fieldError = 'Pick a day for this visit, or tick "Schedule later".';
			return null;
		}
		if (anytime) {
			return { ...base, visit_date: day, start_time: null, end_time: null, all_day: true };
		}
		const start = timeToString(when.startTime);
		const end = timeToString(when.endTime);
		if (end && !start) {
			fieldError = 'Set a start time before an end time.';
			return null;
		}
		if (start && end && end <= start) {
			fieldError = 'The end time has to come after the start time.';
			return null;
		}
		return {
			...base,
			visit_date: day,
			start_time: start || null,
			end_time: end || null,
			all_day: false
		};
	}

	function submit() {
		fieldError = '';
		const payload = collect();
		if (payload) onSave(payload, pricingToSave());
	}

	// Same shape, but the section saves this visit and then opens "Apply to later visits". Undated visits have
	// no later visits to name, so the button is hidden for one and this path is never reached with a null date.
	function submitFuture() {
		fieldError = '';
		const payload = collect();
		if (payload) onSaveFuture?.(payload, pricingToSave());
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog {open} title="Edit visit" size={perVisitPricing ? 'large' : 'default'} {onClose}>
	<div class="visit-dialog">
		{#if error}<p class="visit-dialog__alert" role="alert">{error}</p>{/if}
		{#if fieldError}<p class="visit-dialog__alert" role="alert">{fieldError}</p>{/if}

		{#if isRecurring}
			<p class="visit-dialog__note">
				Changes here affect this visit only, unless you choose to update the later ones.
			</p>
		{/if}

		<Input
			id="visit-dialog-title"
			label="Visit title"
			placeholder={jobTitle.trim()
				? `Leave blank to use “${jobTitle.trim()}”`
				: 'Leave blank to use the job title'}
			bind:value={title}
			maxlength={160}
		/>

		<Checkbox
			id="visit-dialog-later"
			label="Schedule later"
			description="Keep this visit in the backlog without a date until you know it."
			bind:checked={scheduleLater}
		/>

		{#if !scheduleLater}
			<DateTimePicker
				id="visit-dialog-when"
				range
				showTime={!anytime}
				dateLabel="Day of the visit"
				timeLabel="Time"
				{locale}
				bind:value={when}
			/>
			<Checkbox
				id="visit-dialog-anytime"
				label="Anytime"
				description="Promise the day without promising an hour."
				checked={anytime}
				onchange={(checked) => {
					anytime = checked;
					if (checked) when = { ...when, startTime: undefined, endTime: undefined };
				}}
			/>
		{/if}

		<Textarea
			id="visit-dialog-instructions"
			label="Instructions for this visit"
			rows={3}
			maxlength={2000}
			bind:value={instructions}
		/>

		<TeamPicker id="visit-dialog-team" bind:value={assigneeIds} {open} />

		{#if perVisitPricing}
			<!--
				Invoices 5c-5: a recurring job billed per visit charges for what that visit actually did. The
				visit starts on the job's lines and only carries its own once somebody changes them here.
			-->
			<div class="visit-dialog__pricing">
				{#if pricingLoading}
					<LoadingSkeleton variant="text" label="Loading this visit’s pricing" rows={3} />
				{:else if pricingFailed}
					<p class="visit-dialog__note">
						This visit’s pricing could not be loaded. Close this dialog and try again.
					</p>
				{:else if resettingPricing}
					<p class="visit-dialog__note">
						This visit will go back to the job’s own lines when you save.
					</p>
					<Button variant="tertiary" onclick={() => (resettingPricing = false)} disabled={saving}>
						Keep this visit’s own lines
					</Button>
				{:else}
					<ProductsAndServicesBlock
						lines={savedPricingLines}
						editable={pricingEditable}
						alwaysEditing={pricingEditable}
						carrySourceLine
						showPrices={canSeePrice}
						subtotalMinor={pricing?.subtotal_minor ?? null}
						{currencyCode}
						{locale}
						editorTotalLabel="This visit"
						lockedMessage={pricing?.lock_reason === 'invoiced'
							? 'This visit is already on an invoice, so its pricing is fixed.'
							: pricing?.lock_reason === 'completed'
								? 'This visit is marked complete, so its pricing is fixed. Reopen it to change what it bills.'
								: ''}
						emptyDescription="This visit bills the job’s lines. Change a quantity to make it bill its own."
						onDraftChange={(lines) => (pricingDraft = lines)}
					/>
					{#if pricingEditable && pricing?.has_override}
						<Button variant="tertiary" onclick={() => (resettingPricing = true)} disabled={saving}>
							Use the job’s lines again
						</Button>
					{/if}
				{/if}
			</div>
		{/if}

		<div class="visit-dialog__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			{#if isRecurring && onSaveFuture && !scheduleLater}
				<Button variant="secondary" onclick={submitFuture} loading={saving}>
					Save and update future visits
				</Button>
			{/if}
			<Button onclick={submit} loading={saving}>Save visit</Button>
		</div>
	</div>
</Dialog>

<style lang="scss">
	.visit-dialog {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__alert {
			margin: 0;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__pricing {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			align-items: flex-start;
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
