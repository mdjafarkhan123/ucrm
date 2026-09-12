<script lang="ts">
	import Card from '$lib/components/ui/Card.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import BookingDurationField from './BookingDurationField.svelte';
	import {
		BOOKING_ARRIVAL_WINDOW_MAX_MINUTES,
		BOOKING_BUFFER_MAX_MINUTES,
		BOOKING_MIN_NOTICE_MAX_MINUTES,
		BOOKING_SLOT_INTERVAL_MAX_MINUTES,
		BOOKING_SLOT_INTERVAL_MIN_MINUTES,
		BOOKING_VISIT_DURATION_MAX_MINUTES,
		BOOKING_VISIT_DURATION_MIN_MINUTES
	} from '$lib/forms/types';

	// The rule fields from `form_booking_rules`, edited as a working copy and saved as one command by the
	// owning page (matches 4B-1's "one screen, one save" shape). `efficient_scheduling_type` is deliberately
	// not shown: `update_form_booking_settings` does not accept it yet, so there is nothing here to save —
	// see 20260913160000 § 4.
	let {
		requiresBookingApproval = $bindable(),
		serviceAreaEnabled = $bindable(),
		minNoticeMinutes = $bindable(),
		slotIntervalMinutes = $bindable(),
		visitDurationMinutes = $bindable(),
		arrivalWindowMinutes = $bindable(),
		bufferMinutes = $bindable(),
		serviceAreaReady,
		disabled = false
	}: {
		requiresBookingApproval: boolean;
		serviceAreaEnabled: boolean;
		minNoticeMinutes: number;
		slotIntervalMinutes: number;
		visitDurationMinutes: number;
		arrivalWindowMinutes: number | null;
		bufferMinutes: number;
		/** From Business Profile: address geocoded + a radius set. The toggle stays honestly off until then. */
		serviceAreaReady: boolean;
		disabled?: boolean;
	} = $props();

	// `arrivalWindowMinutes` is nullable (null = an exact time is shown); `BookingDurationField` only speaks
	// plain minutes, so its length lives in its own local state and only flows into the real field while the
	// toggle is on.
	let arrivalWindowShown = $state(arrivalWindowMinutes !== null);
	let arrivalWindowLength = $state(arrivalWindowMinutes ?? 60);

	function toggleArrivalWindow(shown: boolean) {
		arrivalWindowShown = shown;
		arrivalWindowMinutes = shown ? arrivalWindowLength : null;
	}

	$effect(() => {
		if (arrivalWindowShown) arrivalWindowMinutes = arrivalWindowLength;
	});
</script>

<Card heading="Timing">
	<BookingDurationField
		id="booking-min-notice"
		label="Minimum notice"
		bind:minutes={minNoticeMinutes}
		maxMinutes={BOOKING_MIN_NOTICE_MAX_MINUTES}
		units={['minutes', 'hours', 'days']}
		hint="How soon before the visit a customer may still book."
		{disabled}
	/>
	<BookingDurationField
		id="booking-visit-duration"
		label="Visit length"
		bind:minutes={visitDurationMinutes}
		minMinutes={BOOKING_VISIT_DURATION_MIN_MINUTES}
		maxMinutes={BOOKING_VISIT_DURATION_MAX_MINUTES}
		units={['minutes', 'hours']}
		hint="How long the visit is held on the calendar once booked."
		{disabled}
	/>
	<BookingDurationField
		id="booking-slot-interval"
		label="Offer times every"
		bind:minutes={slotIntervalMinutes}
		minMinutes={BOOKING_SLOT_INTERVAL_MIN_MINUTES}
		maxMinutes={BOOKING_SLOT_INTERVAL_MAX_MINUTES}
		units={['minutes', 'hours']}
		hint="The spacing between the times a customer can choose from, e.g. every 30 minutes."
		{disabled}
	/>

	<Toggle
		id="booking-arrival-window"
		label="Give an arrival window instead of an exact time"
		description="For example, arriving between 1–3pm rather than an exact time."
		labelSide="start"
		checked={arrivalWindowShown}
		onchange={toggleArrivalWindow}
		{disabled}
	/>
	{#if arrivalWindowShown}
		<BookingDurationField
			id="booking-arrival-window-length"
			label="Arrival window length"
			bind:minutes={arrivalWindowLength}
			minMinutes={5}
			maxMinutes={BOOKING_ARRIVAL_WINDOW_MAX_MINUTES}
			units={['minutes', 'hours']}
			{disabled}
		/>
	{/if}

	<BookingDurationField
		id="booking-buffer"
		label="Buffer time between bookings"
		bind:minutes={bufferMinutes}
		maxMinutes={BOOKING_BUFFER_MAX_MINUTES}
		units={['minutes', 'hours']}
		hint="A gap kept clear before and after every booking, so back-to-back visits aren't scheduled too tightly."
		{disabled}
	/>
</Card>

<Card heading="Approval and area">
	<Toggle
		id="booking-requires-approval"
		label="Require your approval before a booking is confirmed"
		description="Off books the slot straight onto the calendar; on holds it until staff approve it."
		labelSide="start"
		bind:checked={requiresBookingApproval}
		{disabled}
	/>
	<Toggle
		id="booking-service-area"
		label="Only accept bookings inside your service area"
		description={serviceAreaReady
			? 'Uses the radius set in Business Profile.'
			: 'Set your business address and a service area radius in Business Profile first.'}
		labelSide="start"
		bind:checked={serviceAreaEnabled}
		disabled={disabled || !serviceAreaReady}
	/>
</Card>
