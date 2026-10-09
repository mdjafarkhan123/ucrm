<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import WeeklyHoursEditor from '$lib/components/jafar/booking/WeeklyHoursEditor.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { browserTimeZone } from '$lib/jafar/calendar';
	import { jafarBookingKey, jafarSettingsKey } from '$lib/jafar/query-keys';
	import {
		BUFFER_CHOICES,
		DURATION_CHOICES,
		HORIZON_CHOICES,
		INTERVAL_CHOICES,
		NOTICE_CHOICES,
		bookingPath,
		fetchBookingSettings,
		lengthWords,
		noticeWords,
		zoneCity,
		type BookingHours,
		type BookingSettings,
		type BookingSettingsInput
	} from '$lib/jafar/booking';

	// Jafar business management E1: Booking settings (plan § 6) -- the public link on or off, the Discovery call,
	// the rules that decide which times are offered, and Jafar's weekly hours. Only times free on his Business
	// Management calendar are offered, so the page needs no Google or Outlook connection.

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({ queryKey: jafarBookingKey, queryFn: fetchBookingSettings }));

	type Draft = Omit<BookingSettingsInput, 'time_zone' | 'meeting_type'> & {
		meeting_type: Omit<BookingSettingsInput['meeting_type'], 'description'> & {
			description: string;
		};
	};

	let draft = $state<Draft | null>(null);
	let saved = $state('');
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let layout = $state<RecordFormLayout>();
	let copied = $state(false);

	function load(settings: BookingSettings) {
		const type = settings.meeting_type;
		draft = {
			enabled: settings.enabled,
			meeting_type: {
				id: type.id,
				slug: type.slug,
				name: type.name,
				description: type.description ?? '',
				duration_minutes: type.duration_minutes,
				min_notice_minutes: type.min_notice_minutes,
				horizon_days: type.horizon_days,
				buffer_minutes: type.buffer_minutes,
				slot_interval_minutes: type.slot_interval_minutes
			},
			hours: settings.hours.map((range) => ({ ...range }))
		};
		saved = JSON.stringify(draft);
	}

	$effect(() => {
		const settings = query.data;
		if (settings) untrack(() => draft === null && load(settings));
	});

	const dirty = $derived(draft !== null && JSON.stringify(draft) !== saved);
	const zone = $derived(query.data?.time_zone ?? browserTimeZone());
	const savedSlug = $derived(query.data?.meeting_type.slug ?? '');
	const publicLink = $derived(`${page.url.origin}${bookingPath(savedSlug)}`);

	beforeNavigate((navigation) => {
		if (!dirty) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});

	function cancel() {
		if (query.data) load(query.data);
		formError = '';
		fieldErrors = {};
	}

	async function save() {
		if (!draft || !dirty || saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		const body: BookingSettingsInput = {
			...draft,
			meeting_type: { ...draft.meeting_type, description: draft.meeting_type.description || null },
			time_zone: query.data?.time_zone ? undefined : browserTimeZone()
		};
		const result = await sendLeadWrite('/api/jafar/booking', 'PATCH', body);
		saving = false;
		if (!result.ok) {
			formError = result.error;
			fieldErrors = result.fieldErrors;
			return;
		}
		queryClient.setQueryData(jafarBookingKey, result.data as BookingSettings);
		load(result.data as BookingSettings);
		void queryClient.invalidateQueries({ queryKey: jafarSettingsKey, exact: true });
		toast.success(
			draft?.enabled ? 'Booking saved. Your page is taking bookings.' : 'Booking saved.'
		);
	}

	async function copyLink() {
		try {
			await navigator.clipboard.writeText(publicLink);
			copied = true;
			setTimeout(() => (copied = false), 2000);
		} catch {
			toast.error('The link could not be copied. Select it and copy it yourself.');
		}
	}

	const options = (values: readonly number[], words: (value: number) => string) =>
		values.map((value) => ({ value: String(value), label: words(value) }));
	const durationOptions = options(DURATION_CHOICES, lengthWords);
	const noticeOptions = options(NOTICE_CHOICES, noticeWords);
	const horizonOptions = options(HORIZON_CHOICES, (days) => `${days} days ahead`);
	const bufferOptions = options(BUFFER_CHOICES, (minutes) =>
		minutes === 0 ? 'No gap' : `${minutes} min`
	);
	const intervalOptions = options(INTERVAL_CHOICES, (minutes) => `Every ${lengthWords(minutes)}`);

	/** The server's "hours.3.start" messages, by range. */
	const hourErrors = $derived.by(() => {
		const errors: Record<number, string> = {};
		for (const [path, message] of Object.entries(fieldErrors)) {
			const match = /^hours\.(\d+)/.exec(path);
			if (match) errors[Number(match[1])] ??= message;
		}
		return errors;
	});

	function numberField(key: keyof Draft['meeting_type']) {
		return {
			get value() {
				return draft ? String(draft.meeting_type[key]) : '';
			},
			set value(next: string) {
				if (draft) (draft.meeting_type[key] as number) = Number(next);
			}
		};
	}
	const duration = numberField('duration_minutes');
	const notice = numberField('min_notice_minutes');
	const horizon = numberField('horizon_days');
	const buffer = numberField('buffer_minutes');
	const interval = numberField('slot_interval_minutes');

	const daysOpen = (hours: BookingHours[]) => new Set(hours.map((range) => range.weekday)).size;
</script>

<svelte:head><title>Booking · Settings · Control Room</title></svelte:head>

<Breadcrumbs
	items={[{ label: 'Settings', href: resolve('/jafar/settings') }, { label: 'Booking' }]}
/>

{#if query.isError && !query.data}
	<ErrorState
		title="Booking settings could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if !draft}
	<LoadingSkeleton variant="card" rows={4} label="Loading booking settings" />
{:else}
	<RecordFormLayout title="Booking" icon={calendarIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			{#if draft}
				<form
					class="booking-form"
					novalidate
					onsubmit={(event) => {
						event.preventDefault();
						void save().finally(() => layout?.revealError());
					}}
				>
					<SectionBlock
						title="Booking page"
						hint="Prospects open this link to book a call with you."
						form
					>
						<Toggle
							id="booking-enabled"
							label="Take bookings"
							description={draft.enabled
								? 'Anyone with the link can book an open time.'
								: 'The link says booking is closed. Past bookings stay on your calendar.'}
							labelSide="start"
							bind:checked={draft.enabled}
						/>
						<div class="booking-form__link" class:booking-form__link--off={!query.data?.enabled}>
							<span class="booking-form__link-text">{publicLink}</span>
							<div class="booking-form__link-actions">
								<Button variant="secondary" size="small" onclick={copyLink}>
									<span class="booking-form__button-icon" aria-hidden="true"
										>{@html copied ? checkIcon : copyIcon}</span
									>
									{copied ? 'Copied' : 'Copy link'}
								</Button>
								<Button
									variant="tertiary"
									size="small"
									href={bookingPath(savedSlug)}
									target="_blank"
								>
									<span class="booking-form__button-icon" aria-hidden="true"
										>{@html externalIcon}</span
									>
									Open
								</Button>
							</div>
						</div>
						{#if query.data && !query.data.enabled}
							<p class="booking-form__note">
								Turn on <strong>Take bookings</strong> and save before you share the link.
							</p>
						{/if}
					</SectionBlock>

					<SectionBlock title="Meeting" hint="What prospects see before they pick a time." form>
						<div class="booking-form__grid">
							<Input
								id="booking-name"
								label="Name"
								required
								maxlength={120}
								invalid={Boolean(fieldErrors['meeting_type.name'])}
								errorMessage={fieldErrors['meeting_type.name'] ?? ''}
								bind:value={draft.meeting_type.name}
							/>
							<Select
								id="booking-length"
								label="Length"
								options={durationOptions}
								bind:value={duration.value}
							/>
						</div>
						<Input
							id="booking-slug"
							label="Link ending"
							required
							maxlength={60}
							invalid={Boolean(fieldErrors['meeting_type.slug'])}
							errorMessage={fieldErrors['meeting_type.slug'] ??
								'Changing it stops the old link working.'}
							bind:value={draft.meeting_type.slug}
						/>
						<Textarea
							id="booking-description"
							label="Description"
							rows={3}
							maxlength={1000}
							invalid={Boolean(fieldErrors['meeting_type.description'])}
							errorMessage={fieldErrors['meeting_type.description'] ?? ''}
							bind:value={draft.meeting_type.description}
						/>
						<div class="booking-form__how">
							<span class="booking-form__how-icon" aria-hidden="true">{@html phoneIcon}</span>
							<div>
								<p class="booking-form__how-title">Phone call</p>
								<p class="booking-form__note">
									You call the number they give when they book. Zoom and Google Meet come later.
								</p>
							</div>
						</div>
					</SectionBlock>

					<SectionBlock
						title="Weekly hours"
						hint={`When you take calls, in ${zoneCity(zone)} time (${daysOpen(draft.hours)} ${daysOpen(draft.hours) === 1 ? 'day' : 'days'} a week).`}
						form
					>
						<WeeklyHoursEditor bind:value={draft.hours} errors={hourErrors} />
						<p class="booking-form__note">
							Your time zone is set in <a href={resolve('/jafar/settings/preferences')}
								>My preferences</a
							>.
						</p>
					</SectionBlock>

					<SectionBlock title="Booking rules" hint="Which open times the page offers." form>
						<div class="booking-form__grid">
							<Select
								id="booking-notice"
								label="Minimum notice"
								options={noticeOptions}
								bind:value={notice.value}
							/>
							<Select
								id="booking-horizon"
								label="How far ahead"
								options={horizonOptions}
								bind:value={horizon.value}
							/>
							<Select
								id="booking-buffer"
								label="Gap around your meetings"
								options={bufferOptions}
								bind:value={buffer.value}
							/>
							<Select
								id="booking-interval"
								label="Times start"
								options={intervalOptions}
								bind:value={interval.value}
							/>
						</div>
					</SectionBlock>
					<button type="submit" hidden aria-hidden="true" tabindex="-1"></button>
				</form>
			{/if}
		{/snippet}

		{#snippet rail()}
			<Card heading="How booking works">
				<div class="booking-form__about">
					<p>
						The page offers only times that are free on your <a href={resolve('/jafar/calendar')}
							>calendar</a
						>. Calls and Busy blocks hide their time; a follow-up with a time does not.
					</p>
					<p>
						Two people can never book the same time. A booking lands on your calendar and on the
						business's Lead, with your usual call reminders.
					</p>
					<p>
						The visitor gets a confirmation email at once. If their email matches a Lead you already
						have, the call joins that Lead; otherwise a new Lead starts.
					</p>
					{#if query.data && query.data.bookings_count > 0}
						<p>
							<strong>{query.data.bookings_count}</strong>
							{query.data.bookings_count === 1 ? 'call has' : 'calls have'} been booked through this page.
						</p>
					{/if}
				</div>
			</Card>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={cancel} disabled={!dirty || saving}>Cancel</Button>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving}
				loading={saving}>Save</Button
			>
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.booking-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.booking-form__grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);

		@media (max-width: 640px) {
			grid-template-columns: 1fr;
		}
	}

	.booking-form__link {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-small) var(--space-base);
		padding: var(--space-small) var(--space-small) var(--space-small) var(--space-base);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}

	.booking-form__link--off .booking-form__link-text {
		color: var(--color-text--secondary);
	}

	.booking-form__link-text {
		min-width: 0;
		overflow-wrap: anywhere;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text);
	}

	.booking-form__link-actions {
		display: flex;
		gap: var(--space-small);
	}

	.booking-form__button-icon {
		display: inline-flex;

		:global(svg) {
			width: 1rem;
			height: 1rem;
		}
	}

	.booking-form__how {
		display: flex;
		gap: var(--space-base);
		align-items: flex-start;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}

	.booking-form__how-icon {
		display: inline-grid;
		place-items: center;
		flex: none;
		width: 2.25rem;
		height: 2.25rem;
		border-radius: var(--radius-circle);
		background: var(--color-informative--surface);
		color: var(--color-informative--onSurface);

		:global(svg) {
			width: 1.25rem;
			height: 1.25rem;
		}
	}

	.booking-form__how-title {
		margin: 0;
		font-weight: 600;
		color: var(--color-text);
	}

	.booking-form__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.booking-form__about {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);

		p {
			margin: 0;
		}
	}
</style>
