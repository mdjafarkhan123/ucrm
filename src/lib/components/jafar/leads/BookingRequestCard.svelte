<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import calendarQuestionIcon from '@tabler/icons/outline/calendar-question.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock-edit.svg?raw';
	import xIcon from '@tabler/icons/outline/x.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import BookingTimePicker from '$lib/components/jafar/booking/BookingTimePicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		dateWords,
		lengthWords,
		timeWords,
		zoneCity,
		type BookingView
	} from '$lib/jafar/booking';
	import { jafarCalendarKey, jafarLeadKey } from '$lib/jafar/query-keys';
	import { refreshLead, sendLeadWrite } from '$lib/jafar/lead-page-api';

	// Jafar business management E2: a visitor's booking request in approval mode, as Jobber's "needs approval"
	// request -- Approve at the time they asked for, approve at another open time (Calendly's "propose a new time";
	// offered even while the booking link is off, which only stops new visitors),
	// or Decline. A request holds no time, so the time is checked again on approval; when it was taken since, the
	// picker opens with the reason. The visitor is emailed whichever answer Jafar gives.
	let {
		leadId,
		zone,
		canDecide
	}: {
		leadId: string;
		/** Jafar's calendar zone: times read in it first, the visitor's own zone beside them. */
		zone: string;
		canDecide: boolean;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	// Under the Lead's key, so every refresh of the Lead refreshes its requests too.
	const requestsKey = $derived([...jafarLeadKey(leadId), 'booking-requests'] as const);
	const requests = createQuery(() => ({
		queryKey: requestsKey,
		queryFn: async (): Promise<BookingView[]> => {
			const response = await fetch(
				`/api/jafar/leads/${encodeURIComponent(leadId)}/booking-requests`
			);
			const result = await response.json();
			if (!response.ok) throw new Error(result.error ?? 'Booking requests could not be loaded.');
			return result;
		},
		enabled: Boolean(leadId)
	}));

	let saving = $state<string | null>(null);
	let declining = $state<BookingView | null>(null);
	let rescheduling = $state<BookingView | null>(null);
	let pickerZone = $state('');
	let chosen = $state<string | null>(null);
	let pickerNotice = $state('');
	let picker = $state<BookingTimePicker>();

	function decisionPath(request: BookingView) {
		return `/api/jafar/leads/${encodeURIComponent(leadId)}/booking-requests/${encodeURIComponent(request.booking_id)}`;
	}

	async function afterAnswer() {
		await Promise.all([
			refreshLead(queryClient, leadId),
			queryClient.invalidateQueries({ queryKey: jafarCalendarKey })
		]);
	}

	function openPicker(request: BookingView, notice = '') {
		rescheduling = request;
		chosen = null;
		pickerNotice = notice;
		pickerZone = zone;
	}

	async function approve(request: BookingView, startsAt: string | null) {
		if (saving) return;
		saving = request.booking_id;
		const result = await sendLeadWrite(decisionPath(request), 'POST', {
			decision: 'approve',
			starts_at: startsAt
		});
		saving = null;
		if (result.ok) {
			rescheduling = null;
			await afterAnswer();
			toast.success(
				`Booked ${dateWords(startsAt ?? request.starts_at, zone)} at ${timeWords(startsAt ?? request.starts_at, zone)}`,
				`${request.visitor_name} has been emailed the confirmation.`
			);
			return;
		}
		if (result.fieldErrors.starts_at) {
			// The time went to someone else since: offer the open times instead, saying why.
			if (rescheduling) {
				chosen = null;
				pickerNotice = result.fieldErrors.starts_at;
				await picker?.refresh(startsAt ?? undefined);
			} else
				openPicker(
					request,
					'The time they asked for is no longer free. Choose another time to offer.'
				);
			return;
		}
		await afterAnswer();
		toast.error('The request could not be approved.', result.error);
	}

	async function decline() {
		const request = declining;
		if (!request || saving) return;
		saving = request.booking_id;
		const result = await sendLeadWrite(decisionPath(request), 'POST', { decision: 'decline' });
		saving = null;
		if (!result.ok) {
			await afterAnswer();
			declining = null;
			toast.error('The request could not be declined.', result.error);
			return;
		}
		declining = null;
		await afterAnswer();
		toast.success(
			'Request declined',
			`${request.visitor_name} has been emailed a link to choose another time.`
		);
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if requests.data?.length}
	<RailCard
		title={requests.data.length === 1 ? 'Booking request' : 'Booking requests'}
		icon={calendarQuestionIcon}
		count={requests.data.length > 1 ? requests.data.length : undefined}
		class="booking-request"
	>
		<ul class="booking-request__list">
			{#each requests.data as request (request.booking_id)}
				{@const ownZone = request.visitor_time_zone === zone}
				<li class="booking-request__item">
					<p class="booking-request__lead">
						<strong>{request.visitor_name}</strong> asked for a {lengthWords(
							request.duration_minutes
						)}
						{request.name}
					</p>
					<div class="booking-request__when">
						<span class="booking-request__date">{dateWords(request.starts_at, zone)}</span>
						<span class="booking-request__time"
							>{timeWords(request.starts_at, zone)} – {timeWords(request.ends_at, zone)}
							<span class="booking-request__zone">{zoneCity(zone)} time</span></span
						>
						{#if !ownZone}
							<span class="booking-request__theirs"
								>{timeWords(request.starts_at, request.visitor_time_zone)} for them in {zoneCity(
									request.visitor_time_zone
								)}</span
							>
						{/if}
					</div>
					<p class="booking-request__hint">
						The time is not held until you approve. They are emailed your answer.
					</p>
					{#if canDecide}
						<div class="booking-request__actions">
							<Button
								variant="primary"
								size="small"
								loading={saving === request.booking_id && !rescheduling && !declining}
								disabled={saving !== null}
								onclick={() => void approve(request, null)}
							>
								<span class="booking-request__icon" aria-hidden="true">{@html checkIcon}</span
								>Approve
							</Button>
							<Button
								variant="secondary"
								size="small"
								disabled={saving !== null}
								onclick={() => openPicker(request)}
							>
								<span class="booking-request__icon" aria-hidden="true">{@html clockIcon}</span
								>Another time
							</Button>
							<Button
								variant="tertiary"
								variation="destructive"
								size="small"
								disabled={saving !== null}
								onclick={() => (declining = request)}
							>
								<span class="booking-request__icon" aria-hidden="true">{@html xIcon}</span>Decline
							</Button>
						</div>
					{/if}
				</li>
			{/each}
		</ul>
	</RailCard>
{/if}

{#if rescheduling}
	{@const request = rescheduling}
	<Dialog
		open={true}
		size="large"
		title={chosen ? 'Approve at this time?' : `Choose a time for ${request.visitor_name}`}
		onClose={() => (rescheduling = null)}
	>
		<div class="booking-request__dialog">
			{#if pickerNotice}
				<Banner type="warning" icon={alertIcon}><p>{pickerNotice}</p></Banner>
			{/if}
			<!-- Kept mounted behind the confirm step, so going back shows the same month. -->
			<div class="booking-request__pick" hidden={chosen !== null}>
				<p class="booking-request__intro">
					They asked for {dateWords(request.starts_at, pickerZone || zone)} at {timeWords(
						request.starts_at,
						pickerZone || zone
					)}. Times are the ones your booking page offers, checked against your calendar.
				</p>
				<BookingTimePicker
					bind:this={picker}
					bind:zone={pickerZone}
					slotsUrl={`${decisionPath(request)}/slots`}
					queryKey={['jafar', 'booking-request-slots', request.booking_id]}
					firstWindow={{ to: '', starts: [] }}
					horizonDays={request.horizon_days}
					current={request.starts_at}
					onchoose={(start) => {
						chosen = start;
						pickerNotice = '';
					}}
				/>
			</div>
			{#if chosen}
				<div class="booking-request__confirm">
					<p class="booking-request__chosen">
						{dateWords(chosen, pickerZone)}<br />
						<strong>{timeWords(chosen, pickerZone)}</strong>
						<span class="booking-request__zone">{zoneCity(pickerZone)} time</span>
					</p>
					<p>
						{request.visitor_name} gets a confirmation for this time, saying the one they asked for didn't
						work. They can still change or cancel it from their email.
					</p>
					<div class="booking-request__dialog-actions">
						<Button variant="tertiary" disabled={saving !== null} onclick={() => (chosen = null)}
							>Back to times</Button
						>
						<Button
							variant="primary"
							loading={saving === request.booking_id}
							disabled={saving !== null}
							onclick={() => void approve(request, chosen)}>Approve and email</Button
						>
					</div>
				</div>
			{/if}
		</div>
	</Dialog>
{/if}

{#if declining}
	<ConfirmDialog
		open={true}
		title="Decline this request?"
		confirmLabel="Decline"
		destructive
		loading={saving !== null}
		onConfirm={decline}
		onClose={() => (declining = null)}
	>
		<p>
			{declining.visitor_name} is emailed that {dateWords(declining.starts_at, zone)} at {timeWords(
				declining.starts_at,
				zone
			)} doesn't work, with a link to choose another time. The history keeps a record.
		</p>
	</ConfirmDialog>
{/if}

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	:global(.booking-request) {
		border-top: 4px solid var(--color-warning);
	}

	.booking-request {
		&__list {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__item {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);

			& + & {
				margin-top: var(--space-base);
				padding-top: var(--space-base);
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__lead {
			margin: 0;
			color: var(--color-text);
			overflow-wrap: anywhere;

			strong {
				color: var(--color-heading);
			}
		}

		&__when {
			display: flex;
			flex-direction: column;
			gap: 2px;
			padding: var(--space-small) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-warning--surface);
		}

		&__date {
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
		}

		&__time {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}

		&__zone {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 400;
		}

		&__theirs {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		// Approve leads across the card; the other two answers share the row beneath it.
		&__actions {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-small);

			> :global(:first-child) {
				grid-column: 1 / -1;
			}

			> :global(*) {
				justify-content: center;
			}
		}

		&__icon {
			display: inline-flex;
			margin-right: var(--space-smaller);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__dialog {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);

			p {
				margin: 0;
			}
		}

		&__pick:not([hidden]) {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__intro {
			color: var(--color-text--secondary);
		}

		&__confirm {
			display: flex;
			flex-direction: column;
			gap: var(--space-base);
		}

		&__chosen {
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background--subtle);
			color: var(--color-text);

			strong {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-larger);
			}
		}

		&__dialog-actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}
</style>
