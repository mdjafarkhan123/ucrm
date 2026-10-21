<script lang="ts">
	import type { Snippet } from 'svelte';
	import { Time } from '@internationalized/date';
	import calendarCogIcon from '@tabler/icons/outline/calendar-cog.svg?raw';
	import calendarClockIcon from '@tabler/icons/outline/calendar-clock.svg?raw';
	import calendarOffIcon from '@tabler/icons/outline/calendar-off.svg?raw';
	import calendarRepeatIcon from '@tabler/icons/outline/calendar-repeat.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock-hour-3.svg?raw';
	import sunIcon from '@tabler/icons/outline/sun.svg?raw';
	import repeatIcon from '@tabler/icons/outline/repeat.svg?raw';
	import receiptIcon from '@tabler/icons/outline/receipt.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
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
		onClose,
		notice
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
		/** Client reminders Part 4: the "Notify customer" box, shown above the buttons. */
		notice?: Snippet;
	} = $props();

	let title = $state('');
	// The one three-way switch replaces the old "Schedule later" and "Anytime" ticks, so the two settings
	// can never be on together.
	type WhenMode = 'time' | 'anytime' | 'later';
	let mode = $state<WhenMode>('time');
	const scheduleLater = $derived(mode === 'later');
	const anytime = $derived(mode === 'anytime');
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let instructions = $state('');
	let assigneeIds = $state<string[]>([]);
	let fieldError = $state('');
	// Which box the message belongs to, so that box (not the whole picker) takes the error look.
	let fieldErrorAt = $state<'day' | 'time'>('day');
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
			mode = visit.visit_date === null ? 'later' : !visit.start_time ? 'anytime' : 'time';
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

	// What the pricing editor holds, reduced to the fields that actually bill -- plus the photo, so removing
	// one alone still saves -- so reopening a dialog and changing nothing does not rewrite the visit's lines
	// and bump its revision.
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
				line.source_job_line_item_id ?? null,
				line.image_file_id ?? null
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
				source_job_line_item_id: line.source_job_line_item_id ?? null,
				image_file_id: line.image_file_id ?? null
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
			fieldError = 'Pick a day for this visit, or choose Later.';
			fieldErrorAt = 'day';
			return null;
		}
		if (anytime) {
			return { ...base, visit_date: day, start_time: null, end_time: null, all_day: true };
		}
		const start = timeToString(when.startTime);
		const end = timeToString(when.endTime);
		if (end && !start) {
			fieldError = 'Set a start time before an end time.';
			fieldErrorAt = 'time';
			return null;
		}
		if (start && end && end <= start) {
			fieldError = 'The end time has to come after the start time.';
			fieldErrorAt = 'time';
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

	function chooseMode(next: string) {
		mode = next as WhenMode;
		fieldError = '';
		if (mode === 'anytime') when = { ...when, startTime: undefined, endTime: undefined };
		else if (mode === 'time' && !when.startTime)
			when = { ...when, startTime: new Time(9, 30), endTime: new Time(10, 30) };
	}

	const clock = (time: { hour: number; minute: number }) =>
		new Date(Date.UTC(2000, 0, 1, time.hour, time.minute)).toLocaleTimeString(locale, {
			hour: 'numeric',
			minute: '2-digit',
			timeZone: 'UTC'
		});

	// "4 hrs", "1½ hrs", "45 min", "1 hr 15 min": how long the visit is, read off the two times.
	function lengthOf(
		start: { hour: number; minute: number },
		end: { hour: number; minute: number }
	) {
		const minutes = end.hour * 60 + end.minute - (start.hour * 60 + start.minute);
		if (minutes <= 0) return '';
		if (minutes < 60) return `${minutes} min`;
		const hours = Math.floor(minutes / 60);
		const rest = minutes % 60;
		if (rest === 0) return hours === 1 ? '1 hr' : `${hours} hrs`;
		if (rest === 30) return `${hours}½ hrs`;
		return `${hours} hr ${rest} min`;
	}

	// The date card reads back what is picked, as it changes.
	const day = $derived(when.date ? when.date.toDate('UTC') : null);
	const dayPart = (options: Intl.DateTimeFormatOptions) =>
		day ? day.toLocaleDateString(locale, { ...options, timeZone: 'UTC' }) : '';
	const hoursLine = $derived.by(() => {
		if (anytime) return 'Anytime that day';
		const start = when.startTime;
		const end = when.endTime;
		if (!start) return 'No time set';
		if (!end) return `From ${clock(start)}`;
		const length = lengthOf(start, end);
		return `${clock(start)} – ${clock(end)}${length ? ` · ${length}` : ''}`;
	});
</script>

<Dialog
	{open}
	title="Edit visit"
	subtitle={`${jobTitle.trim() || 'Job'}${perVisitPricing ? ' · billed per visit' : ''}`}
	size="large"
	icon={calendarCogIcon}
	iconTone="job"
	flush
	{onClose}
>
	{#snippet badge()}
		{#if isRecurring}
			<span class="visit-dialog__recurring">
				<span class="visit-dialog__recurring-icon" aria-hidden="true">{@html repeatIcon}</span>
				Recurring
			</span>
		{/if}
	{/snippet}

	<div class="visit-dialog">
		<section class="visit-dialog__when" aria-label="When">
			<div class="visit-dialog__when-head">
				<IconTile icon={calendarClockIcon} tone="time" size={32} white />
				<h3 class="visit-dialog__when-title">When</h3>
			</div>

			<div class="visit-dialog__date-card">
				{#if scheduleLater}
					<span class="visit-dialog__date-tile visit-dialog__date-tile--empty" aria-hidden="true">
						<span class="visit-dialog__date-off">{@html calendarOffIcon}</span>
					</span>
					<span class="visit-dialog__date-copy">
						<strong class="visit-dialog__weekday">No date yet</strong>
						<span class="visit-dialog__hours visit-dialog__hours--quiet">
							Keep this visit in the backlog without a date until you know it.
						</span>
					</span>
				{:else if !day}
					<span class="visit-dialog__date-tile visit-dialog__date-tile--empty" aria-hidden="true">
						<span class="visit-dialog__date-month">—</span>
						<span class="visit-dialog__date-day">?</span>
					</span>
					<span class="visit-dialog__date-copy">
						<strong class="visit-dialog__weekday visit-dialog__weekday--quiet">Pick a day</strong>
						<span class="visit-dialog__hours">
							<span class="visit-dialog__hours-icon" aria-hidden="true">{@html clockIcon}</span>
							{hoursLine}
						</span>
					</span>
				{:else}
					<span class="visit-dialog__date-tile" aria-hidden="true">
						<span class="visit-dialog__date-month">{dayPart({ month: 'short' })}</span>
						<span class="visit-dialog__date-day">{dayPart({ day: 'numeric' })}</span>
					</span>
					<span class="visit-dialog__date-copy">
						<strong class="visit-dialog__weekday">{dayPart({ weekday: 'long' })}</strong>
						<span class="visit-dialog__hours">
							<span class="visit-dialog__hours-icon" aria-hidden="true">
								{@html anytime ? sunIcon : clockIcon}
							</span>
							{hoursLine}
						</span>
					</span>
				{/if}
			</div>

			<SegmentedControl
				ariaLabel="When this visit happens"
				white
				fullWidth
				value={mode}
				onchange={chooseMode}
				disabled={saving}
				options={[
					{ value: 'time', label: 'Set a time', icon: clockIcon },
					{ value: 'anytime', label: 'Anytime', icon: sunIcon },
					{ value: 'later', label: 'Later', icon: calendarOffIcon }
				]}
			/>

			{#if !scheduleLater}
				<DateTimePicker
					id="visit-dialog-when"
					range
					showTime={!anytime}
					dateLabel="Day of the visit"
					timeLabel="Time"
					{locale}
					dateInvalid={fieldError !== '' && fieldErrorAt === 'day'}
					timeInvalid={fieldError !== '' && fieldErrorAt === 'time'}
					errorMessage={fieldError}
					class="visit-dialog__picker"
					bind:value={when}
				/>
			{/if}
		</section>

		<section class="visit-dialog__details" aria-label="Details">
			{#if error}
				<Banner type="error">{error}</Banner>
			{/if}

			{#if isRecurring}
				<Banner type="notice">
					Changes here affect this visit only, unless you choose to update the later ones.
				</Banner>
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

			<Textarea
				id="visit-dialog-instructions"
				label="Instructions for this visit"
				rows={5}
				maxlength={2000}
				bind:value={instructions}
			/>

			<TeamPicker
				id="visit-dialog-team"
				label="Who is going"
				chips
				bind:value={assigneeIds}
				{open}
			/>

			{#if perVisitPricing}
				<!--
					Invoices 5c-5: a recurring job billed per visit charges for what that visit actually did. The
					visit starts on the job's lines and only carries its own once somebody changes them here.
				-->
				<div class="visit-dialog__pricing">
					{#if pricingLoading}
						<LoadingSkeleton variant="table" rows={3} label="Loading this visit’s pricing" />
					{:else if pricingFailed}
						<Banner type="error">
							This visit’s pricing could not be loaded. Close this dialog and try again.
						</Banner>
					{:else if resettingPricing}
						<Banner type="notice" icon={calendarRepeatIcon}>
							This visit will go back to the job’s own lines when you save.
						</Banner>
						<Button variant="tertiary" onclick={() => (resettingPricing = false)} disabled={saving}>
							Keep this visit’s own lines
						</Button>
					{:else}
						<ProductsAndServicesBlock
							concept
							title="What this visit bills"
							icon={receiptIcon}
							tone="invoice"
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
							<Button
								variant="tertiary"
								onclick={() => (resettingPricing = true)}
								disabled={saving}
							>
								Use the job’s lines again
							</Button>
						{/if}
					{/if}
				</div>
			{/if}
		</section>
	</div>

	{#snippet footer()}
		<div class="visit-dialog__notice">{@render notice?.()}</div>
		<div class="visit-dialog__actions">
			<Button variant="secondary" onclick={onClose} disabled={saving}>Cancel</Button>
			{#if isRecurring && onSaveFuture && !scheduleLater}
				<Button variant="secondary" onclick={submitFuture} loading={saving}>
					<span class="visit-dialog__sync">{@html calendarRepeatIcon}</span>
					Save and update future visits
				</Button>
			{/if}
			<Button onclick={submit} loading={saving}>
				{@html checkIcon}
				Save visit
			</Button>
		</div>
	{/snippet}
</Dialog>

<style lang="scss">
	.visit-dialog {
		display: grid;
		grid-template-columns: 340px minmax(0, 1fr);
		min-height: 0;

		&__when {
			display: grid;
			align-content: start;
			gap: var(--space-base);
			padding: var(--space-medium);
			border-right: var(--border-base) solid var(--color-border);
			background: var(--color-time--surface);
		}

		&__when-head {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
		}

		&__when-title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-larger);
			font-weight: 600;
		}

		&__date-card {
			display: flex;
			align-items: center;
			gap: var(--space-slim);
			padding: var(--space-slim) var(--space-slim) var(--space-slim) var(--space-slim);
			border: var(--border-base) solid var(--color-time--surface-edge);
			border-radius: var(--radius-large);
			background: var(--color-surface);
		}

		&__date-tile {
			display: grid;
			flex: 0 0 auto;
			place-content: center;
			justify-items: center;
			width: 56px;
			height: 60px;
			border-radius: var(--radius-large);
			background: var(--color-time);
			color: #fff;

			&--empty {
				background: var(--color-time--surface);
				color: var(--color-time);
			}
		}

		&__date-month {
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: 0.8px;
			text-transform: uppercase;
			opacity: 0.8;
		}

		&__date-day {
			font-size: var(--typography--fontSize-larger);
			font-weight: 700;
			line-height: 1.1;
		}

		&__date-off {
			display: inline-flex;

			:global(svg) {
				width: 24px;
				height: 24px;
			}
		}

		&__date-copy {
			display: grid;
			gap: var(--space-smaller);
			min-width: 0;
		}

		&__weekday {
			color: var(--color-heading);
			font-size: 18px;
			font-weight: 700;

			&--quiet {
				color: var(--color-text--secondary);
			}
		}

		&__hours {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text);
			font-size: 13px;
			font-weight: 500;

			&--quiet {
				color: var(--color-text--secondary);
			}
		}

		&__hours-icon {
			display: inline-flex;
			color: var(--color-time);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		// The picker's own two-column layout is too tight in the 340 panel: day above, time below.
		&__when :global(.visit-dialog__picker) {
			grid-template-columns: minmax(0, 1fr);
		}

		&__details {
			display: grid;
			align-content: start;
			gap: var(--space-base);
			min-width: 0;
			padding: var(--space-medium);
		}

		&__pricing {
			display: grid;
			gap: var(--space-small);
			justify-items: start;

			> :global(*) {
				justify-self: stretch;
			}
		}

		&__recurring {
			display: inline-flex;
			align-items: center;
			gap: var(--space-smaller);
			padding: 3px 9px;
			border-radius: var(--radius-circle);
			background: var(--color-informative--surface);
			color: var(--color-informative--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__recurring-icon,
		&__sync {
			display: inline-flex;

			:global(svg) {
				width: 12px;
				height: 12px;
			}
		}

		&__sync {
			color: var(--color-time);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__notice {
			flex: 1 1 auto;
			min-width: 0;

			:global(.notify-customer) {
				padding-top: 0;
			}
		}

		&__actions {
			display: flex;
			gap: var(--space-small);
			margin-left: auto;
		}
	}

	@media (max-width: 767px) {
		.visit-dialog {
			grid-template-columns: 1fr;

			&__when {
				border-right: 0;
				border-bottom: var(--border-base) solid var(--color-border);
			}
		}
	}
</style>
