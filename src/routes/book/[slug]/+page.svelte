<script lang="ts">
	import { onMount } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import {
		CalendarDate,
		endOfMonth,
		parseDate,
		startOfMonth,
		toZoned,
		today
	} from '@internationalized/date';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import circleCheckIcon from '@tabler/icons/outline/circle-check.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import CountryPicker from '$lib/components/ui/CountryPicker.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import TurnstileCheck from '$lib/components/forms/TurnstileCheck.svelte';
	import BookingMonth from '$lib/components/jafar/booking/BookingMonth.svelte';
	import {
		LOCATION_WORDS,
		dateWords,
		dayKey,
		lengthWords,
		timeWords,
		zoneCity,
		type BookedCall
	} from '$lib/jafar/booking';
	import type { PageProps } from './$types';

	// Jafar business management E1: a prospect books a sales call (plan § 6), Calendly's way -- a month with the
	// open days marked, that day's times, then their details. Times show in the visitor's own zone, which they
	// can change. The server checks the time is still open when they book; if someone took it first, they are
	// brought back to the times with the list refreshed.

	let { data }: PageProps = $props();
	const meeting = $derived(data.meeting);
	const slug = $derived(meeting?.slug ?? '');

	const queryClient = useQueryClient();

	// The zone is the browser's, so nothing time-shaped draws until the page reaches it.
	let zone = $state('');
	let changingZone = $state(false);
	let locale = $state<string | undefined>(undefined);
	let month = $state<CalendarDate>();
	let picked = $state<CalendarDate>();
	let firstStarts = $state<string[]>([]);
	let firstTo = $state('');

	type Step = 'pick' | 'details' | 'booked';
	let step = $state<Step>('pick');
	let chosen = $state('');
	let notice = $state('');

	onMount(() => {
		zone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
		locale = navigator.language || undefined;
		firstStarts = data.firstWindow.starts;
		firstTo = data.firstWindow.to;
		const first = firstStarts[0];
		month = first ? parseDate(dayKey(first, zone)) : today(zone);
	});

	function monthRange(shown: CalendarDate, inZone: string) {
		return {
			from: toZoned(startOfMonth(shown), inZone).toDate().toISOString(),
			to: toZoned(endOfMonth(shown).add({ days: 1 }), inZone)
				.toDate()
				.toISOString()
		};
	}

	async function fetchStarts(from: string, to: string): Promise<string[]> {
		const params = new URLSearchParams({ from, to });
		const response = await fetch(`/api/public/book/${encodeURIComponent(slug)}/slots?${params}`);
		const result = await response.json();
		if (!response.ok) throw new Error(result.error ?? 'We could not load the open times.');
		return result;
	}

	const range = $derived(month && zone ? monthRange(month, zone) : null);
	// A month that ends inside the window the page arrived with needs no request (times before now are never open).
	const covered = $derived(Boolean(range && firstTo && range.to <= firstTo));
	const monthQuery = createQuery(() => ({
		queryKey: ['public-booking', slug, range?.from, range?.to],
		queryFn: () => fetchStarts(range!.from, range!.to),
		enabled: Boolean(range && meeting) && !covered,
		staleTime: 30_000
	}));

	const starts = $derived.by(() => {
		if (!range) return [];
		if (covered) return firstStarts.filter((start) => start >= range.from && start < range.to);
		return monthQuery.data ?? [];
	});
	const loadingMonth = $derived(!covered && monthQuery.isPending);

	const byDay = $derived.by(() => {
		const days = new Map<string, string[]>();
		for (const start of starts) {
			const key = dayKey(start, zone);
			const list = days.get(key);
			if (list) list.push(start);
			else days.set(key, [start]);
		}
		return days;
	});
	const openDays = $derived(new Set(byDay.keys()));

	// The day shown: the one the visitor chose while it is still open in this month, else the month's first open day.
	const day = $derived.by(() => {
		if (picked && openDays.has(picked.toString())) return picked;
		const first = [...openDays].sort()[0];
		return first ? parseDate(first) : undefined;
	});
	const dayTimes = $derived(day ? (byDay.get(day.toString()) ?? []) : []);

	const minDay = $derived(zone ? today(zone) : undefined);
	const maxDay = $derived(
		zone && meeting ? today(zone).add({ days: meeting.horizon_days }) : undefined
	);

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
	let bookedEmail = $state('');

	async function refreshTimes() {
		const now = new Date().toISOString();
		const [fresh] = await Promise.all([
			fetchStarts(now, firstTo).catch(() => null),
			queryClient.invalidateQueries({ queryKey: ['public-booking', slug] })
		]);
		if (fresh) firstStarts = fresh;
	}

	async function book(event: SubmitEvent) {
		event.preventDefault();
		if (submitting) return;
		submitting = true;
		formError = '';
		fieldErrors = {};
		try {
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
				bookedEmail = form.email.trim();
				step = 'booked';
				window.scrollTo({ top: 0, behavior: 'smooth' });
				return;
			}
			turnstile?.reset();
			if (response.status === 409 && result.taken) {
				notice = result.error;
				step = 'pick';
				picked = parseDate(dayKey(chosen, zone));
				await refreshTimes();
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

<main class="booking-page">
	<div class="booking-page__brand">
		<span class="booking-page__brand-mark" aria-hidden="true">U</span>
		Uplift
	</div>

	{#if !meeting}
		<section class="booking-page__card booking-page__card--narrow">
			<div class="booking-page__closed">
				<span class="booking-page__closed-icon" aria-hidden="true">{@html calendarIcon}</span>
				<h1>Booking isn't open right now</h1>
				<p>
					This booking link isn't taking bookings at the moment. Please check the link you were
					sent.
				</p>
			</div>
		</section>
	{:else}
		<section class="booking-page__card" class:booking-page__card--narrow={step === 'booked'}>
			{#if step === 'booked' && booked}
				<div class="booking-page__done">
					<span class="booking-page__done-icon" aria-hidden="true">{@html circleCheckIcon}</span>
					<h1>You're booked</h1>
					<p class="booking-page__lede">
						A confirmation is on its way to <strong>{bookedEmail}</strong>.
					</p>
					<dl class="booking-page__facts booking-page__facts--boxed">
						<div>
							<dt><span aria-hidden="true">{@html calendarIcon}</span><span>When</span></dt>
							<dd>
								{dateWords(booked.starts_at, zone, locale)}<br />
								{timeWords(booked.starts_at, zone, locale)} – {timeWords(
									booked.ends_at,
									zone,
									locale
								)}
								({zoneCity(zone)} time)
							</dd>
						</div>
						<div>
							<dt><span aria-hidden="true">{@html phoneIcon}</span><span>How</span></dt>
							<dd>{booked.host_name} will phone you on {form.phone}.</dd>
						</div>
					</dl>
					<p class="booking-page__hint">Need a different time? Reply to the confirmation email.</p>
				</div>
			{:else}
				<aside class="booking-page__about">
					<p class="booking-page__host">{meeting.host_name} · Uplift</p>
					<h1 class="booking-page__title">{meeting.name}</h1>
					<ul class="booking-page__meta">
						<li>
							<span aria-hidden="true">{@html clockIcon}</span>{lengthWords(
								meeting.duration_minutes
							)}
						</li>
						<li>
							<span aria-hidden="true">{@html phoneIcon}</span>{LOCATION_WORDS[
								meeting.location_kind
							]}
						</li>
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
					</ul>
					{#if meeting.description}
						<p class="booking-page__description">{meeting.description}</p>
					{/if}
				</aside>

				<div class="booking-page__work">
					{#if step === 'pick'}
						<h2 class="booking-page__step-title">Choose a day and time</h2>
						{#if notice}
							<Banner type="warning" icon={alertIcon}
								><p class="booking-page__banner">{notice}</p></Banner
							>
						{/if}
						{#if !zone || !month || !minDay || !maxDay}
							<div class="booking-page__pick booking-page__pick--placeholder" aria-hidden="true">
								<div class="booking-page__skeleton booking-page__skeleton--month"></div>
								<div class="booking-page__skeleton booking-page__skeleton--times"></div>
							</div>
						{:else}
							<div class="booking-page__pick">
								<div class="booking-page__month">
									<BookingMonth
										bind:month
										bind:value={() => day, (next) => (picked = next)}
										{openDays}
										minValue={minDay}
										maxValue={maxDay}
										loading={loadingMonth}
									/>
									<div class="booking-page__zone">
										{#if changingZone}
											<span id="booking-zone-label" class="booking-page__zone-label">Time zone</span
											>
											<TimezonePicker
												id="booking-zone"
												labelledby="booking-zone-label"
												bind:value={zone}
												onchange={() => (changingZone = false)}
											/>
										{:else}
											<span class="booking-page__zone-icon" aria-hidden="true"
												>{@html worldIcon}</span
											>
											<span>Times in {zoneCity(zone)} time</span>
											<button
												type="button"
												class="booking-page__link-button"
												onclick={() => (changingZone = true)}>Change</button
											>
										{/if}
									</div>
								</div>

								<div class="booking-page__times" aria-live="polite">
									{#if loadingMonth}
										<p class="booking-page__hint">Finding open times…</p>
									{:else if monthQuery.isError && !covered}
										<p class="booking-page__hint">
											We could not load the open times.
											<button
												type="button"
												class="booking-page__link-button"
												onclick={() => monthQuery.refetch()}>Try again</button
											>
										</p>
									{:else if !day}
										<p class="booking-page__hint">
											No open times this month. Try the next month with the arrow above.
										</p>
									{:else}
										<h3 class="booking-page__day-title">{dateWords(dayTimes[0], zone, locale)}</h3>
										<ul class="booking-page__time-list">
											{#each dayTimes as start (start)}
												<li>
													<button
														type="button"
														class="booking-page__time"
														onclick={() => choose(start)}
													>
														{timeWords(start, zone, locale)}
													</button>
												</li>
											{/each}
										</ul>
									{/if}
								</div>
							</div>
						{/if}
					{:else if step === 'details'}
						<button
							type="button"
							class="booking-page__back"
							onclick={() => {
								step = 'pick';
								formError = '';
							}}
						>
							<span aria-hidden="true">{@html arrowLeftIcon}</span> Choose another time
						</button>
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
									label="Phone number we should call"
									type="tel"
									required
									autocomplete="tel"
									inputmode="tel"
									maxlength={40}
									placeholder="+44 7700 900123"
									invalid={Boolean(fieldErrors.phone)}
									errorMessage={fieldErrors.phone ?? 'Include your country code.'}
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
									Book the call
								</Button>
							</div>
						</form>
					{/if}
				</div>
			{/if}
		</section>
	{/if}
</main>

<style lang="scss">
	.booking-page {
		min-height: 100vh;
		padding: var(--space-larger) var(--space-base) var(--space-extravagant);
		background: var(--color-surface--background);
		color: var(--color-text);

		@media (max-width: 640px) {
			padding: var(--space-base) var(--space-base) var(--space-largest);
		}
	}

	.booking-page__brand {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-small);
		margin-bottom: var(--space-large);
		font-weight: 700;
		font-size: var(--typography--fontSize-large);
	}

	.booking-page__brand-mark {
		display: grid;
		width: 32px;
		height: 32px;
		place-items: center;
		border-radius: var(--radius-small);
		background: var(--color-interactive);
		color: var(--color-surface);
		font-weight: 900;
	}

	.booking-page__card {
		display: grid;
		grid-template-columns: minmax(240px, 300px) minmax(0, 1fr);
		max-width: 1040px;
		margin: 0 auto;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		background: var(--color-surface);
		box-shadow: var(--shadow-base);

		@media (max-width: 860px) {
			grid-template-columns: 1fr;
		}
	}

	.booking-page__card--narrow {
		display: block;
		max-width: 560px;
	}

	.booking-page__about {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		padding: var(--space-larger) var(--space-large);
		border-right: var(--border-base) solid var(--color-border);

		@media (max-width: 860px) {
			padding: var(--space-large) var(--space-base);
			border-right: 0;
			border-bottom: var(--border-base) solid var(--color-border);
		}
	}

	.booking-page__host {
		margin: 0;
		color: var(--color-text--secondary);
		font-weight: 600;
	}

	.booking-page__title {
		margin: 0;
		font-size: var(--typography--fontSize-largest);
		line-height: var(--typography--lineHeight-tight);
	}

	.booking-page__meta {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		margin: 0;
		padding: 0;
		list-style: none;
		color: var(--color-text--secondary);
		font-weight: 600;

		li {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
		}

		:global(svg) {
			flex: none;
			width: 1.25rem;
			height: 1.25rem;
		}

		> li > span:first-child {
			display: inline-flex;
		}
	}

	.booking-page__meta-chosen {
		color: var(--color-interactive);
	}

	.booking-page__description {
		margin: 0;
		color: var(--color-text--secondary);
		line-height: var(--typography--lineHeight-base);
		white-space: pre-line;
	}

	.booking-page__work {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
		padding: var(--space-larger) var(--space-large);

		@media (max-width: 860px) {
			padding: var(--space-large) var(--space-base);
		}
	}

	.booking-page__step-title {
		margin: 0;
		font-size: var(--typography--fontSize-larger);
	}

	.booking-page__banner {
		margin: 0;
	}

	.booking-page__pick {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 220px;
		gap: var(--space-larger);
		min-height: 420px;

		@media (max-width: 640px) {
			grid-template-columns: 1fr;
			gap: var(--space-large);
		}
	}

	.booking-page__skeleton {
		border-radius: var(--radius-base);
		background: var(--color-surface--background--subtle, var(--color-surface--background));
		animation: booking-pulse 1.4s ease-in-out infinite;
	}

	.booking-page__skeleton--month {
		height: 380px;
	}

	.booking-page__skeleton--times {
		height: 380px;

		@media (max-width: 640px) {
			height: 160px;
		}
	}

	@keyframes booking-pulse {
		50% {
			opacity: 0.5;
		}
	}

	.booking-page__month {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
	}

	.booking-page__zone {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);

		:global(.timezone-picker),
		:global(> div) {
			flex: 1 1 240px;
		}
	}

	.booking-page__zone-label {
		flex-basis: 100%;
		font-weight: 600;
		color: var(--color-text);
	}

	.booking-page__zone-icon {
		display: inline-flex;

		:global(svg) {
			width: 1rem;
			height: 1rem;
		}
	}

	.booking-page__link-button {
		padding: 0;
		border: 0;
		background: none;
		color: var(--color-interactive);
		font: inherit;
		font-weight: 600;
		text-decoration: underline;
		text-underline-offset: 2px;
		cursor: pointer;

		&:hover {
			color: var(--color-interactive--hover);
		}

		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
	}

	.booking-page__times {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;
	}

	.booking-page__day-title {
		margin: 0;
		min-height: 2.5rem;
		display: flex;
		align-items: center;
		font-size: var(--typography--fontSize-base);
		font-weight: 600;
	}

	.booking-page__time-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);
		max-height: 420px;
		margin: 0;
		padding: 0 var(--space-smaller) 0 0;
		overflow-y: auto;
		list-style: none;

		@media (max-width: 640px) {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			max-height: none;
			overflow: visible;
		}
	}

	.booking-page__time {
		width: 100%;
		min-height: 3rem;
		border: var(--border-thick) solid var(--color-interactive);
		border-radius: var(--radius-base);
		background: var(--color-surface);
		color: var(--color-interactive);
		font: inherit;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		cursor: pointer;
		transition:
			background-color 120ms ease,
			color 120ms ease;

		&:hover {
			background: var(--color-interactive);
			color: var(--color-surface);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.booking-page__back {
		display: inline-flex;
		align-self: flex-start;
		align-items: center;
		gap: var(--space-smaller);
		padding: var(--space-smaller) 0;
		border: 0;
		background: none;
		color: var(--color-interactive);
		font: inherit;
		font-weight: 600;
		cursor: pointer;

		:global(svg) {
			width: 1.125rem;
			height: 1.125rem;
		}

		span {
			display: inline-flex;
		}

		&:hover {
			color: var(--color-interactive--hover);
		}

		&:focus-visible {
			outline: none;
			border-radius: var(--radius-small);
			box-shadow: var(--shadow-focus);
		}
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
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);
	}

	.booking-page__closed,
	.booking-page__done {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-base);
		padding: var(--space-largest) var(--space-large);
		text-align: center;

		h1 {
			margin: 0;
			font-size: var(--typography--fontSize-largest);
		}

		p {
			margin: 0;
		}

		@media (max-width: 640px) {
			padding: var(--space-larger) var(--space-base);
		}
	}

	.booking-page__closed p {
		color: var(--color-text--secondary);
	}

	.booking-page__closed-icon,
	.booking-page__done-icon {
		display: inline-grid;
		place-items: center;
		width: 4rem;
		height: 4rem;
		border-radius: var(--radius-circle);

		:global(svg) {
			width: 2rem;
			height: 2rem;
		}
	}

	.booking-page__closed-icon {
		background: var(--color-surface--background);
		color: var(--color-text--secondary);
	}

	.booking-page__done-icon {
		background: var(--color-success--surface);
		color: var(--color-success--onSurface);
	}

	.booking-page__lede {
		color: var(--color-text--secondary);
		overflow-wrap: anywhere;
	}

	.booking-page__facts {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		width: 100%;
		margin: var(--space-small) 0 0;
		text-align: left;

		div {
			display: grid;
			grid-template-columns: 6rem 1fr;
			gap: var(--space-base);
		}

		dt {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			color: var(--color-text--secondary);
			font-weight: 600;

			span:first-child {
				display: inline-flex;
			}

			:global(svg) {
				width: 1.125rem;
				height: 1.125rem;
			}
		}

		dd {
			margin: 0;
			font-weight: 600;
			line-height: var(--typography--lineHeight-base);
		}
	}

	.booking-page__facts--boxed {
		padding: var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}
</style>
