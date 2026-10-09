<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import alarmIcon from '@tabler/icons/outline/alarm.svg?raw';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import ReminderPicker from '$lib/components/jafar/calendar/ReminderPicker.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		browserTimeZone,
		calendarPreferencesKey,
		fetchCalendarPreferences,
		refreshCalendar,
		type CalendarPreferences,
		type ReminderRule
	} from '$lib/jafar/calendar';

	// Jafar business management C2: My preferences -- his time zone and the reminders a new call or next action
	// starts with (Jafar, 2026-10-08). Each call or next action can still change its own. Saving rewrites every
	// reminder still to come that follows these defaults, so a change applies to what is already booked.
	// D3b: each teammate has their own; Settings stay Jafar's, so only he is led back to them.
	const ownerView = $derived(page.data.owner?.role === null);

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({
		queryKey: calendarPreferencesKey,
		queryFn: fetchCalendarPreferences
	}));

	type Draft = {
		time_zone: string;
		call: ReminderRule[] | null;
		follow_up_day: ReminderRule[] | null;
		follow_up_timed: ReminderRule[] | null;
	};

	let draft = $state<Draft | null>(null);
	let saved = $state('');
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let layout = $state<RecordFormLayout>();

	// The time zone fills in from this browser until one is saved.
	function load(preferences: CalendarPreferences) {
		const defaults = preferences.reminder_defaults;
		draft = {
			time_zone: preferences.time_zone ?? browserTimeZone(),
			call: defaults.call.map((rule) => ({ ...rule })),
			follow_up_day: defaults.follow_up_day.map((rule) => ({ ...rule })),
			follow_up_timed: defaults.follow_up_timed.map((rule) => ({ ...rule }))
		};
		saved = preferences.time_zone === null ? '' : JSON.stringify(draft);
	}

	$effect(() => {
		const preferences = query.data;
		if (preferences) untrack(() => draft === null && load(preferences));
	});

	const dirty = $derived(draft !== null && JSON.stringify(draft) !== saved);

	beforeNavigate((navigation) => {
		if (!dirty || saved === '') return;
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
		const result = await sendLeadWrite('/api/jafar/calendar/preferences', 'PATCH', {
			time_zone: draft.time_zone,
			reminder_defaults: {
				call: draft.call ?? [],
				follow_up_day: draft.follow_up_day ?? [],
				follow_up_timed: draft.follow_up_timed ?? []
			}
		});
		if (!result.ok) {
			saving = false;
			formError = result.error;
			fieldErrors = result.fieldErrors;
			return;
		}
		saved = JSON.stringify(draft);
		await refreshCalendar(queryClient);
		saving = false;
		toast.success('My preferences saved.');
	}

	const section = (key: string) =>
		Object.entries(fieldErrors).find(([path]) => path.includes(key))?.[1] ?? '';
</script>

<svelte:head><title>My preferences · Settings · Control Room</title></svelte:head>

{#if ownerView}
	<Breadcrumbs
		items={[{ label: 'Settings', href: resolve('/jafar/settings') }, { label: 'My preferences' }]}
	/>
{/if}

{#if query.isError && !query.data}
	<ErrorState
		title="Your preferences could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if !draft}
	<LoadingSkeleton variant="card" rows={3} label="Loading your preferences" />
{:else}
	<RecordFormLayout title="My preferences" icon={alarmIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			{#if draft}
				<form
					class="preferences-form"
					novalidate
					onsubmit={(event) => {
						event.preventDefault();
						void save().finally(() => layout?.revealError());
					}}
				>
					<SectionBlock
						title="Time zone"
						hint="Your calendar and reminder times use this zone."
						form
					>
						<TimezonePicker
							id="preferences-time-zone"
							required
							invalid={Boolean(fieldErrors.time_zone)}
							errorMessage={fieldErrors.time_zone ?? ''}
							bind:value={draft.time_zone}
						/>
					</SectionBlock>

					<SectionBlock title="Sales calls" hint="Reminders a new call starts with." form>
						<ReminderPicker
							id="preferences-call"
							label="Call reminders"
							timed
							allowDefaults={false}
							defaults={[]}
							bind:value={draft.call}
						/>
						{#if section('call')}<p class="preferences-form__error" role="alert">
								{section('call')}
							</p>{/if}
					</SectionBlock>

					<SectionBlock
						title="Follow-ups"
						hint="Reminders a next action starts with — one set for a day only, one for a set time."
						form
					>
						<ReminderPicker
							id="preferences-follow-up-day"
							label="Due on a day"
							timed={false}
							allowDefaults={false}
							defaults={[]}
							bind:value={draft.follow_up_day}
						/>
						{#if section('follow_up_day')}<p class="preferences-form__error" role="alert">
								{section('follow_up_day')}
							</p>{/if}
						<ReminderPicker
							id="preferences-follow-up-timed"
							label="Due at a time"
							timed
							allowDefaults={false}
							defaults={[]}
							bind:value={draft.follow_up_timed}
						/>
						{#if section('follow_up_timed')}<p class="preferences-form__error" role="alert">
								{section('follow_up_timed')}
							</p>{/if}
					</SectionBlock>
					<button type="submit" hidden aria-hidden="true" tabindex="-1"></button>
				</form>
			{/if}
		{/snippet}

		{#snippet rail()}
			<Card heading="What this changes">
				<div class="preferences-form__about">
					<p>
						An <strong>alert</strong> appears in the bell at the top of the panel. An
						<strong>email</strong> goes to the address you sign in with.
					</p>
					<p>
						Changing these updates reminders already booked that use them. A call or follow-up whose
						reminders you changed by hand keeps its own.
					</p>
					<p>Each call and follow-up can still have its own reminders when you book it.</p>
				</div>
			</Card>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={cancel} disabled={!dirty || saving || saved === ''}
				>Cancel</Button
			>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving}
				loading={saving}>Save</Button
			>
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.preferences-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.preferences-form__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.preferences-form__about {
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
