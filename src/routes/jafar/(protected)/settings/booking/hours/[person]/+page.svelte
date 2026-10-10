<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate, goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import WeeklyHoursEditor from '$lib/components/jafar/booking/WeeklyHoursEditor.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { browserTimeZone } from '$lib/jafar/calendar';
	import { jafarBookingKey } from '$lib/jafar/query-keys';
	import {
		fetchBookingSettings,
		hoursOf,
		zoneCity,
		type BookingHours,
		type BookingSettings
	} from '$lib/jafar/booking';

	// Jafar business management E3: one host's weekly hours -- Jafar's or a teammate's -- in their own time zone.
	// A booking for a meeting they host, and a call handed to them, must fall inside these hours.

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({ queryKey: jafarBookingKey, queryFn: fetchBookingSettings }));

	const personParam = $derived(page.params.person ?? 'jafar');
	const memberId = $derived(personParam === 'jafar' ? null : personParam);
	const person = $derived(query.data?.people.find((entry) => entry.id === memberId));
	const isJafar = $derived(memberId === null);
	const zone = $derived(
		isJafar ? (query.data?.time_zone ?? browserTimeZone()) : (person?.time_zone ?? '')
	);

	let hours = $state<BookingHours[] | null>(null);
	let saved = $state('');
	let saving = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let layout = $state<RecordFormLayout>();

	function load(settings: BookingSettings) {
		hours = hoursOf(settings, memberId);
		saved = JSON.stringify(hours);
	}

	$effect(() => {
		const settings = query.data;
		if (settings) untrack(() => hours === null && load(settings));
	});

	const dirty = $derived(hours !== null && JSON.stringify(hours) !== saved);

	beforeNavigate((navigation) => {
		if (!dirty || saving) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});

	const hourErrors = $derived.by(() => {
		const errors: Record<number, string> = {};
		for (const [path, message] of Object.entries(fieldErrors)) {
			const match = /^hours\.(\d+)/.exec(path);
			if (match) errors[Number(match[1])] ??= message;
		}
		return errors;
	});

	async function save() {
		if (!hours || !dirty || saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		const result = await sendLeadWrite(
			`/api/jafar/booking/hours/${encodeURIComponent(personParam)}`,
			'PATCH',
			{ hours, time_zone: isJafar && !query.data?.time_zone ? browserTimeZone() : undefined }
		);
		if (!result.ok) {
			saving = false;
			formError = result.error;
			fieldErrors = result.fieldErrors;
			return;
		}
		queryClient.setQueryData(jafarBookingKey, result.data as BookingSettings);
		load(result.data as BookingSettings);
		toast.success('Weekly hours saved.');
		await goto(resolve('/jafar/settings/booking'));
		saving = false;
	}

	function cancel() {
		void goto(resolve('/jafar/settings/booking'));
	}

	const title = $derived(
		isJafar ? 'Your weekly hours' : person ? `${person.name}'s weekly hours` : 'Weekly hours'
	);
</script>

<svelte:head><title>Weekly hours · Booking · Settings · Control Room</title></svelte:head>

<Breadcrumbs
	items={[
		{ label: 'Settings', href: resolve('/jafar/settings') },
		{ label: 'Booking', href: resolve('/jafar/settings/booking') },
		{ label: isJafar ? 'Your hours' : (person?.name ?? 'Hours') }
	]}
/>

{#if query.isError && !query.data}
	<ErrorState
		title="Booking settings could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if !query.data || hours === null}
	<!-- The card and its title draw at once; the days fill in when the settings arrive. -->
	<RecordFormLayout {title} icon={clockIcon}>
		{#snippet main()}
			<LoadingSkeleton variant="text" rows={7} label="Loading weekly hours" />
		{/snippet}
	</RecordFormLayout>
{:else if !person}
	<ErrorState
		title="This person is not a host"
		description="They may have left the team. Choose hosts on a meeting type first."
	/>
{:else}
	<RecordFormLayout {title} icon={clockIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			<form
				novalidate
				onsubmit={(event) => {
					event.preventDefault();
					void save().finally(() => layout?.revealError());
				}}
			>
				<SectionBlock
					title="Weekly hours"
					hint={`When ${isJafar ? 'you take' : `${person.name} takes`} calls, in ${zoneCity(zone)} time.`}
					form
				>
					{#if hours}
						<WeeklyHoursEditor bind:value={hours} errors={hourErrors} />
					{/if}
					<p class="booking-hours__note">
						{#if isJafar}
							Your time zone is set in <a href={resolve('/jafar/settings/preferences')}
								>My preferences</a
							>.
						{:else}
							{person.name} sets their own time zone in their My preferences.
						{/if}
					</p>
				</SectionBlock>
				<button type="submit" hidden aria-hidden="true" tabindex="-1"></button>
			</form>
		{/snippet}

		{#snippet actions()}
			<Button variant="secondary" onclick={cancel} disabled={saving}>Cancel</Button>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving}
				loading={saving}>Save</Button
			>
		{/snippet}
	</RecordFormLayout>
{/if}

<style lang="scss">
	.booking-hours__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}
</style>
