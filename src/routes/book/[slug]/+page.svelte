<script lang="ts">
	import { onMount } from 'svelte';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import hourglassIcon from '@tabler/icons/outline/hourglass.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import TurnstileCheck from '$lib/components/forms/TurnstileCheck.svelte';
	import BookingTimePicker from '$lib/components/jafar/booking/BookingTimePicker.svelte';
	import BookingBackButton from '$lib/components/jafar/booking/BookingBackButton.svelte';
	import BookingFrame from '$lib/components/jafar/booking/BookingFrame.svelte';
	import BookingStatus from '$lib/components/jafar/booking/BookingStatus.svelte';
	import BookingFacts from '$lib/components/jafar/booking/BookingFacts.svelte';
	import { dateWords, timeWords, zoneCity, type BookedCall } from '$lib/jafar/booking';
	import type { PageProps } from './$types';

	// Jafar business management E1: a prospect books a sales call (plan § 6), Calendly's way -- a month with the
	// open days marked, that day's times, then their details. Times show in the visitor's own zone, which they
	// can change. The server checks the time is still open when they book; if someone took it first, they are
	// brought back to the times with the list refreshed. E2: in approval mode the same steps send a request.

	let { data }: PageProps = $props();
	const meeting = $derived(data.meeting);
	const slug = $derived(meeting?.slug ?? '');

	let zone = $state('');
	let locale = $state<string | undefined>(undefined);
	let picker = $state<BookingTimePicker>();

	type Step = 'pick' | 'details' | 'booked';
	let step = $state<Step>('pick');
	let chosen = $state('');
	let notice = $state('');

	onMount(() => {
		locale = navigator.language || undefined;
	});

	function choose(start: string) {
		chosen = start;
		notice = '';
		step = 'details';
		window.scrollTo({ top: 0, behavior: 'smooth' });
	}

	// --- Details --------------------------------------------------------------------------------------------

	let form = $state({
		name: '',
		email: '',
		phone: '',
		business_name: '',
		country_code: '',
		trade: '',
		note: ''
	});
	let turnstileToken = $state('');
	let turnstile = $state<TurnstileCheck>();
	let submitting = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let booked = $state<BookedCall | null>(null);
	let requested = $state(false);
	let bookedEmail = $state('');

	/** A quick visitor can press Book before Cloudflare's check hands back its token; give it up to 10 seconds. */
	async function humanCheckDone() {
		for (let waited = 0; !turnstileToken && waited < 10_000; waited += 200)
			await new Promise((done) => setTimeout(done, 200));
		return Boolean(turnstileToken);
	}

	async function book(event: SubmitEvent) {
		event.preventDefault();
		if (submitting) return;
		submitting = true;
		formError = '';
		fieldErrors = {};
		try {
			if (data.turnstileSiteKey && !(await humanCheckDone())) {
				formError = 'The security check has not finished. Please wait a moment and try again.';
				return;
			}
			const response = await fetch(`/api/public/book/${encodeURIComponent(slug)}`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					...form,
					starts_at: chosen,
					time_zone: zone,
					turnstile_token: turnstileToken
				})
			});
			const result = await response.json().catch(() => ({}));
			if (response.ok) {
				booked = result.call;
				requested = Boolean(result.requested);
				bookedEmail = form.email.trim();
				step = 'booked';
				window.scrollTo({ top: 0, behavior: 'smooth' });
				return;
			}
			turnstile?.reset();
			if (response.status === 409 && result.taken) {
				notice = result.error;
				step = 'pick';
				await picker?.refresh(chosen);
				return;
			}
			fieldErrors = result.field_errors ?? {};
			formError =
				response.status === 429
					? 'Too many tries from this connection. Please wait a few minutes and try again.'
					: (result.error ?? 'We could not book that time. Please try again.');
		} catch {
			formError = 'You seem to be offline. Please check your connection and try again.';
		} finally {
			submitting = false;
		}
	}

	const chosenEnd = $derived(
		chosen && meeting
			? new Date(Date.parse(chosen) + meeting.duration_minutes * 60_000).toISOString()
			: ''
	);
</script>

<svelte:head>
	<title>{meeting ? `${meeting.name} · Uplift` : 'Booking · Uplift'}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

{#if !meeting}
	<BookingFrame>
		<BookingStatus icon={calendarIcon} title="Booking isn't open right now">
			<p>
				This booking link isn't taking bookings at the moment. Please check the link you were sent.
			</p>
		</BookingStatus>
	</BookingFrame>
{:else if step === 'booked' && booked}
	<BookingFrame>
		<BookingStatus
			icon={requested ? hourglassIcon : circleCheckIcon}
			tone={requested ? 'waiting' : 'success'}
			title={requested ? 'Request sent' : "You're booked"}
		>
			<p>
				{#if requested}
					{booked.host_name} will confirm by email to <strong>{bookedEmail}</strong>. The time is
					not held for you until then.
				{:else}
					A confirmation is on its way to <strong>{bookedEmail}</strong>.
				{/if}
			</p>
			<BookingFacts
				startsAt={booked.starts_at}
				endsAt={booked.ends_at}
				{zone}
				{locale}
				hostName={booked.host_name}
				phone={form.phone}
				locationKind={booked.location_kind}
				videoJoinUrl={booked.video_join_url}
			/>
			<p class="booking-page__hint">
				Need a different time? Use the link in that email to change or cancel.
			</p>
		</BookingStatus>
	</BookingFrame>
{:else}
	<BookingFrame {meeting}>
		{#snippet meta()}
			{#if step === 'details' && chosen}
				<li class="booking-page__meta-chosen">
					<span aria-hidden="true">{@html calendarIcon}</span>
					<span>
						{timeWords(chosen, zone, locale)} – {timeWords(chosenEnd, zone, locale)},
						{dateWords(chosen, zone, locale)}
					</span>
				</li>
				<li>
					<span aria-hidden="true">{@html worldIcon}</span>{zoneCity(zone)} time
				</li>
			{/if}
		{/snippet}

		{#if step === 'pick'}
			<h2 class="booking-page__step-title">Choose a day and time</h2>
			{#if notice}
				<Banner type="warning" icon={alertIcon}><p class="booking-page__banner">{notice}</p></Banner
				>
			{/if}
		{/if}
		<!-- Stays mounted behind the details step, so going back keeps the month and day. -->
		<div hidden={step !== 'pick'}>
			<BookingTimePicker
				bind:this={picker}
				bind:zone
				{locale}
				slotsUrl={`/api/public/book/${encodeURIComponent(slug)}/slots`}
				queryKey={['public-booking', slug]}
				firstWindow={data.firstWindow}
				horizonDays={meeting.horizon_days}
				onchoose={choose}
			/>
		</div>
		{#if step === 'details'}
			<BookingBackButton
				label="Choose another time"
				onclick={() => {
					step = 'pick';
					formError = '';
				}}
			/>
			<h2 class="booking-page__step-title">Your details</h2>
			{#if formError}
				<Banner type="error" icon={alertIcon}
					><p class="booking-page__banner">{formError}</p></Banner
				>
			{/if}
			<form class="booking-page__form" novalidate onsubmit={book}>
				<div class="booking-page__grid">
					<Input
						id="book-name"
						label="Your name"
						required
						autocomplete="name"
						maxlength={120}
						invalid={Boolean(fieldErrors.name)}
						errorMessage={fieldErrors.name ?? ''}
						bind:value={form.name}
					/>
					<Input
						id="book-email"
						label="Email"
						type="email"
						required
						autocomplete="email"
						maxlength={254}
						invalid={Boolean(fieldErrors.email)}
						errorMessage={fieldErrors.email ?? ''}
						bind:value={form.email}
					/>
					<Input
						id="book-phone"
						label="Phone, with country code"
						type="tel"
						required
						autocomplete="tel"
						inputmode="tel"
						maxlength={40}
						placeholder="+44 7700 900123"
						invalid={Boolean(fieldErrors.phone)}
						errorMessage={fieldErrors.phone ?? ''}
						bind:value={form.phone}
					/>
					<Input
						id="book-business"
						label="Business name"
						required
						autocomplete="organization"
						maxlength={200}
						invalid={Boolean(fieldErrors.business_name)}
						errorMessage={fieldErrors.business_name ?? ''}
						bind:value={form.business_name}
					/>
					<CountryPicker
						id="book-country"
						label="Country"
						required
						invalid={Boolean(fieldErrors.country_code)}
						errorMessage={fieldErrors.country_code ?? ''}
						bind:value={form.country_code}
					/>
					<Input
						id="book-trade"
						label="Your trade"
						required
						maxlength={120}
						placeholder="Plumbing, roofing, landscaping…"
						invalid={Boolean(fieldErrors.trade)}
						errorMessage={fieldErrors.trade ?? ''}
						bind:value={form.trade}
					/>
				</div>
				<Textarea
					id="book-note"
					label="Anything you'd like us to know? (optional)"
					rows={3}
					maxlength={2000}
					invalid={Boolean(fieldErrors.note)}
					errorMessage={fieldErrors.note ?? ''}
					bind:value={form.note}
				/>
				<TurnstileCheck
					siteKey={data.turnstileSiteKey}
					bind:token={turnstileToken}
					bind:this={turnstile}
				/>
				<div class="booking-page__submit">
					<Button type="submit" size="large" loading={submitting} disabled={submitting}>
						{data.requiresApproval ? 'Send request' : 'Book the call'}
					</Button>
				</div>
			</form>
		{/if}
	</BookingFrame>
{/if}

<style lang="scss">
	.booking-page__meta-chosen {
		color: var(--color-interactive);
	}

	.booking-page__step-title {
		margin: 0;
		font-size: var(--typography--fontSize-larger);
	}

	.booking-page__banner {
		margin: 0;
	}

	.booking-page__form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.booking-page__grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);

		@media (max-width: 640px) {
			grid-template-columns: 1fr;
		}
	}

	.booking-page__submit {
		display: flex;
		justify-content: flex-end;

		@media (max-width: 640px) {
			:global(> *) {
				width: 100%;
			}
		}
	}

	.booking-page__hint {
		font-size: var(--typography--fontSize-small);
	}
</style>
