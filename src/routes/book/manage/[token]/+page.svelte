<script lang="ts">
	import { onMount } from 'svelte';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import calendarOffIcon from '@tabler/icons/outline/calendar-off.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import linkOffIcon from '@tabler/icons/outline/link-off.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import BookingBackButton from '$lib/components/jafar/booking/BookingBackButton.svelte';
	import BookingFrame from '$lib/components/jafar/booking/BookingFrame.svelte';
	import BookingStatus from '$lib/components/jafar/booking/BookingStatus.svelte';
	import BookingFacts from '$lib/components/jafar/booking/BookingFacts.svelte';
	import BookingTimePicker from '$lib/components/jafar/booking/BookingTimePicker.svelte';
	import {
		bookingPath,
		dateWords,
		timeWords,
		zoneCity,
		type ManagedBooking
	} from '$lib/jafar/booking';
	import type { PageProps } from './$types';

	// Jafar business management E2: the visitor's own page for their booking (Calendly's "Reschedule or cancel"):
	// see it, move it to another open time, or cancel it with an optional reason -- until Jafar's deadline before
	// the call. A request (approval mode) can be changed or withdrawn the same way. The server checks the time and
	// the deadline again; a time taken meanwhile brings the visitor back to the refreshed list.

	let { data, params }: PageProps = $props();

	// What the server last said about the booking: the page's copy until a change answers with a newer one.
	let changed = $state<ManagedBooking | null>(null);
	const booking = $derived(changed ?? data.booking);
	let zone = $state('');
	let locale = $state<string | undefined>(undefined);
	let picker = $state<BookingTimePicker>();

	type Mode = 'view' | 'move' | 'confirm' | 'cancel' | 'moved' | 'cancelled';
	let mode = $state<Mode>('view');
	let chosen = $state('');
	let reason = $state('');
	let notice = $state('');
	let error = $state('');
	let saving = $state(false);

	onMount(() => {
		locale = navigator.language || undefined;
		// The booking's own zone until the picker (or the visitor) says otherwise.
		zone ||= booking?.visitor_time_zone ?? 'UTC';
	});

	const isRequest = $derived(booking?.status === 'requested');
	const bookAgain = $derived(booking?.slug ? bookingPath(booking.slug) : null);
	const chosenEnd = $derived(
		chosen && booking
			? new Date(Date.parse(chosen) + booking.duration_minutes * 60_000).toISOString()
			: ''
	);
	const deadlineBeforeStart = $derived(
		booking ? Date.parse(booking.change_until) < Date.parse(booking.starts_at) : false
	);

	function show(next: Mode) {
		mode = next;
		error = '';
		window.scrollTo({ top: 0, behavior: 'smooth' });
	}

	async function send(body: object) {
		saving = true;
		error = '';
		try {
			const response = await fetch(`/api/public/book/manage/${encodeURIComponent(params.token)}`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			});
			const result = await response.json().catch(() => ({}));
			if (response.ok) {
				changed = result.booking;
				return 'ok' as const;
			}
			if (response.status === 409 && result.taken) {
				notice = result.error;
				return 'taken' as const;
			}
			error =
				response.status === 429
					? 'Too many tries from this connection. Please wait a few minutes and try again.'
					: (result.error ?? 'We could not change your booking. Please try again.');
			return 'failed' as const;
		} catch {
			error = 'You seem to be offline. Please check your connection and try again.';
			return 'failed' as const;
		} finally {
			saving = false;
		}
	}

	async function move() {
		const outcome = await send({ action: 'move', starts_at: chosen });
		if (outcome === 'ok') show('moved');
		else if (outcome === 'taken') {
			show('move');
			await picker?.refresh(chosen);
		}
	}

	async function cancel(event: SubmitEvent) {
		event.preventDefault();
		if ((await send({ action: 'cancel', reason: reason.trim() || null })) === 'ok')
			show('cancelled');
	}

	const at = (instant: string) =>
		`${dateWords(instant, zone, locale)} at ${timeWords(instant, zone, locale)}`;
</script>

<svelte:head>
	<title>{booking ? `Your ${booking.name} · Uplift` : 'Your booking · Uplift'}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

{#if !booking}
	<BookingFrame>
		<BookingStatus icon={linkOffIcon} title="This link isn't valid">
			<p>
				Please use the link in your latest email from us. If it still doesn't work, reply to it.
			</p>
		</BookingStatus>
	</BookingFrame>
{:else if mode === 'moved'}
	<BookingFrame>
		<BookingStatus
			icon={isRequest ? hourglassIcon : circleCheckIcon}
			tone={isRequest ? 'waiting' : 'success'}
			title={isRequest ? 'Request changed' : 'Your call has moved'}
		>
			<p>
				{#if isRequest}
					{booking.host_name} will confirm the new time by email. It is not held for you until then.
				{:else}
					We have emailed you the new time. Your old time is free for someone else.
				{/if}
			</p>
			<BookingFacts
				startsAt={booking.starts_at}
				endsAt={booking.ends_at}
				{zone}
				{locale}
				hostName={booking.host_name}
				phone={booking.visitor_phone}
				locationKind={booking.location_kind}
				videoJoinUrl={booking.video_join_url}
			/>
			<Button variant="tertiary" onclick={() => show('view')}>Back to your booking</Button>
		</BookingStatus>
	</BookingFrame>
{:else if mode === 'cancelled' || !booking.can_change}
	{@const cancelled =
		mode === 'cancelled' ||
		booking.call_status === 'cancelled' ||
		booking.status === 'withdrawn' ||
		booking.status === 'declined'}
	{@const passed = Date.parse(booking.starts_at) <= Date.now() || booking.call_status === 'held'}
	<BookingFrame>
		<BookingStatus
			icon={cancelled ? calendarOffIcon : calendarIcon}
			title={booking.status === 'declined'
				? 'This request was not accepted'
				: booking.status === 'withdrawn'
					? 'Request withdrawn'
					: cancelled
						? 'This call is cancelled'
						: passed
							? 'This call has passed'
							: "It's too late to change online"}
		>
			{#if cancelled}
				<BookingFacts
					startsAt={booking.starts_at}
					endsAt={booking.ends_at}
					{zone}
					{locale}
					hostName={booking.host_name}
					phone={booking.visitor_phone}
					locationKind={booking.location_kind}
					videoJoinUrl={booking.video_join_url}
					struck
				/>
				{#if bookAgain}
					<p>Want to talk another time? Choose a new time that suits you.</p>
					<Button href={bookAgain}>Choose a new time</Button>
				{/if}
			{:else if passed}
				<p>Thanks for your time. If you need anything else, reply to your confirmation email.</p>
			{:else}
				<p>
					Your {booking.name} is {at(booking.starts_at)} ({zoneCity(zone)} time). Changes online closed
					{at(booking.change_until)}. Please reply to your confirmation email and we will help.
				</p>
			{/if}
		</BookingStatus>
	</BookingFrame>
{:else}
	<BookingFrame meeting={booking}>
		{#snippet meta()}
			{#if mode === 'confirm' && chosen}
				<li class="manage-page__meta-chosen">
					<span aria-hidden="true">{@html calendarIcon}</span>
					<span>
						{timeWords(chosen, zone, locale)} – {timeWords(chosenEnd, zone, locale)},
						{dateWords(chosen, zone, locale)}
					</span>
				</li>
				<li><span aria-hidden="true">{@html worldIcon}</span>{zoneCity(zone)} time</li>
			{/if}
		{/snippet}

		{#if mode !== 'view'}
			<BookingBackButton
				label={mode === 'confirm' ? 'Choose another time' : 'Back to your booking'}
				onclick={() => show(mode === 'confirm' ? 'move' : 'view')}
			/>
		{/if}

		{#if error}
			<Banner type="error" icon={alertIcon}><p class="manage-page__banner">{error}</p></Banner>
		{/if}

		{#if mode === 'view'}
			<div class="manage-page__heading">
				<h2 class="manage-page__title">
					{isRequest ? 'Your request' : 'Your booking'}
				</h2>
				{#if isRequest}
					<span class="manage-page__badge">Waiting for {booking.host_name} to confirm</span>
				{/if}
			</div>
			<BookingFacts
				startsAt={booking.starts_at}
				endsAt={booking.ends_at}
				{zone}
				{locale}
				hostName={booking.host_name}
				phone={booking.visitor_phone}
				locationKind={booking.location_kind}
				videoJoinUrl={booking.video_join_url}
			/>
			{#if deadlineBeforeStart}
				<p class="manage-page__hint">
					You can change or cancel online until {at(booking.change_until)}.
				</p>
			{/if}
			<div class="manage-page__actions">
				<Button onclick={() => show('move')}>
					{isRequest ? 'Ask for another time' : 'Change time'}
				</Button>
				<Button variant="secondary" variation="destructive" onclick={() => show('cancel')}>
					{isRequest ? 'Withdraw request' : 'Cancel booking'}
				</Button>
			</div>
		{:else if mode === 'confirm'}
			<h2 class="manage-page__title">Move your call?</h2>
			<dl class="manage-page__change">
				<div>
					<dt>From</dt>
					<dd class="manage-page__old">{at(booking.starts_at)}</dd>
				</div>
				<div>
					<dt>To</dt>
					<dd>{at(chosen)}</dd>
				</div>
			</dl>
			<p class="manage-page__hint">
				{isRequest
					? `${booking.host_name} will confirm the new time by email.`
					: 'Your old time will be freed for someone else and we will email you the new one.'}
			</p>
			<div class="manage-page__actions">
				<Button size="large" loading={saving} disabled={saving} onclick={move}>
					{isRequest ? 'Ask for this time' : 'Move my call'}
				</Button>
			</div>
		{:else if mode === 'cancel'}
			<h2 class="manage-page__title">
				{isRequest ? 'Withdraw your request?' : 'Cancel your call?'}
			</h2>
			<p class="manage-page__hint">
				{at(booking.starts_at)} ({zoneCity(zone)} time) with {booking.host_name}.
			</p>
			<form class="manage-page__form" novalidate onsubmit={cancel}>
				<Textarea
					id="manage-reason"
					label="Anything you'd like to tell us? (optional)"
					rows={3}
					maxlength={500}
					bind:value={reason}
				/>
				<div class="manage-page__actions">
					<Button
						type="submit"
						size="large"
						variation="destructive"
						loading={saving}
						disabled={saving}
					>
						{isRequest ? 'Withdraw request' : 'Cancel booking'}
					</Button>
					<Button variant="tertiary" size="large" onclick={() => show('view')}>
						{isRequest ? 'Keep request' : 'Keep booking'}
					</Button>
				</div>
			</form>
		{/if}

		<!-- Mounted once the visitor first chooses to move, and kept behind the confirm step so its month stays. -->
		{#if mode === 'move' || mode === 'confirm'}
			<div class="manage-page__pick" hidden={mode !== 'move'}>
				<h2 class="manage-page__title">Choose a new time</h2>
				{#if notice}
					<Banner type="warning" icon={alertIcon}
						><p class="manage-page__banner">{notice}</p></Banner
					>
				{/if}
				<BookingTimePicker
					bind:this={picker}
					bind:zone
					{locale}
					slotsUrl={`/api/public/book/manage/${encodeURIComponent(params.token)}/slots`}
					queryKey={['public-booking-change', params.token]}
					firstWindow={data.firstWindow}
					horizonDays={booking.horizon_days}
					current={booking.starts_at}
					onchoose={(start) => {
						chosen = start;
						notice = '';
						show('confirm');
					}}
				/>
			</div>
		{/if}
	</BookingFrame>
{/if}

<style lang="scss">
	.manage-page__meta-chosen {
		color: var(--color-interactive);
	}

	.manage-page__heading {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small) var(--space-base);
	}

	.manage-page__title {
		margin: 0;
		font-size: var(--typography--fontSize-larger);
	}

	.manage-page__badge {
		padding: var(--space-smallest) var(--space-small);
		border-radius: var(--radius-base);
		background: var(--color-warning--surface);
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
		font-weight: 600;
	}

	.manage-page__banner {
		margin: 0;
	}

	.manage-page__hint {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
	}

	.manage-page__actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);

		@media (max-width: 640px) {
			flex-direction: column;

			:global(> *) {
				width: 100%;
			}
		}
	}

	.manage-page__pick {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.manage-page__form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.manage-page__change {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);

		div {
			display: grid;
			grid-template-columns: 4rem 1fr;
			gap: var(--space-base);
		}

		dt {
			color: var(--color-text--secondary);
			font-weight: 600;
		}

		dd {
			margin: 0;
			font-weight: 600;
		}
	}

	.manage-page__old {
		color: var(--color-text--secondary);
		text-decoration: line-through;
	}
</style>
