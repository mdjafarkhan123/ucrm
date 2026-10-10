<script lang="ts">
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import copyIcon from '@tabler/icons/outline/copy.svg?raw';
	import checkIcon from '@tabler/icons/outline/check.svg?raw';
	import chevronRightIcon from '@tabler/icons/outline/chevron-right.svg?raw';
	import clockIcon from '@tabler/icons/outline/clock.svg?raw';
	import externalIcon from '@tabler/icons/outline/external-link.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import PageHeader from '$lib/components/layout/PageHeader.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { browserTimeZone } from '$lib/jafar/calendar';
	import { jafarBookingKey, jafarSettingsKey } from '$lib/jafar/query-keys';
	import {
		bookingPath,
		fetchBookingSettings,
		hoursOf,
		hoursSummary,
		lengthWords,
		personKey,
		zoneCity,
		type BookingSettings,
		type MeetingType
	} from '$lib/jafar/booking';

	// Jafar business management E1/E3: Booking settings (plan § 6) -- the public link on or off, every meeting type
	// with its default host, and each host's weekly hours. Each meeting type and each person's hours open on their
	// own page. Only times free on the host's Business Management calendar are offered, so no Google or Outlook.

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({ queryKey: jafarBookingKey, queryFn: fetchBookingSettings }));

	let confirmSwitch = $state(false);
	let switching = $state(false);
	let copiedSlug = $state<string | null>(null);

	const settings = $derived(query.data);
	const nameOf = (id: string | null) =>
		settings?.people.find((person) => person.id === id)?.name ?? 'Jafar';
	const zone = $derived(settings?.time_zone ?? browserTimeZone());

	async function toggleBookings() {
		if (!settings || switching) return;
		switching = true;
		const enabled = !settings.enabled;
		const result = await sendLeadWrite('/api/jafar/booking', 'PATCH', {
			enabled,
			time_zone: settings.time_zone ? undefined : browserTimeZone()
		});
		switching = false;
		confirmSwitch = false;
		if (!result.ok) {
			toast.error(result.error);
			return;
		}
		queryClient.setQueryData(jafarBookingKey, result.data as BookingSettings);
		void queryClient.invalidateQueries({ queryKey: jafarSettingsKey, exact: true });
		toast.success(enabled ? 'Your booking links are taking bookings.' : 'Booking is closed.');
	}

	const linkOf = (type: MeetingType) => `${page.url.origin}${bookingPath(type.slug)}`;

	async function copyLink(type: MeetingType) {
		try {
			await navigator.clipboard.writeText(linkOf(type));
			copiedSlug = type.slug;
			setTimeout(() => (copiedSlug = null), 2000);
		} catch {
			toast.error('The link could not be copied. Open it and copy it from the address bar.');
		}
	}

	function typeFacts(type: MeetingType) {
		const others = type.host_member_ids.length - 1;
		return [
			lengthWords(type.duration_minutes),
			'Phone call',
			`with ${nameOf(type.host_member_id)}${others > 0 ? ` (+${others} more ${others === 1 ? 'host' : 'hosts'})` : ''}`,
			type.requires_approval ? 'You approve each one' : null
		].filter(Boolean);
	}

	const hosting = (id: string | null) =>
		settings?.meeting_types.filter((type) => type.host_member_ids.includes(id)).length ?? 0;
</script>

<svelte:head><title>Booking · Settings · Control Room</title></svelte:head>

<Breadcrumbs
	items={[{ label: 'Settings', href: resolve('/jafar/settings') }, { label: 'Booking' }]}
/>

{#if query.isError && !settings}
	<ErrorState
		title="Booking settings could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if !settings}
	<LoadingSkeleton variant="card" rows={4} label="Loading booking settings" />
{:else}
	<PageHeader
		title="Booking"
		description="Your booking links, the meetings they offer, and when each host takes calls."
	/>
	<div class="booking-settings">
		<div class="booking-settings__main">
			<SectionBlock title="Booking page" hint="Prospects open a meeting's link to book a call.">
				<div class="booking-settings__switch">
					<div>
						<p class="booking-settings__switch-title">
							<Badge status={settings.enabled ? 'success' : 'inactive'}
								>{settings.enabled ? 'Taking bookings' : 'Closed'}</Badge
							>
						</p>
						<p class="booking-settings__note">
							{settings.enabled
								? 'Anyone with a link can book an open time.'
								: 'Every link says booking is closed. Past bookings stay on the calendar and can still be changed.'}
						</p>
					</div>
					<Button
						variant={settings.enabled ? 'secondary' : 'primary'}
						onclick={() => (confirmSwitch = true)}
						loading={switching}
					>
						{settings.enabled ? 'Close booking' : 'Start taking bookings'}
					</Button>
				</div>
			</SectionBlock>

			<SectionBlock title="Meeting types" hint="What prospects can book, and who takes it.">
				{#if settings.meeting_types.length === 0}
					<p class="booking-settings__note">
						No meeting types yet. Add one to get a link prospects can book.
					</p>
				{:else}
					<ul class="booking-settings__list">
						{#each settings.meeting_types as type (type.id)}
							<li class="booking-settings__row">
								<a
									class="booking-settings__row-main"
									href={resolve('/jafar/(protected)/settings/booking/types/[id]', { id: type.id })}
								>
									<span class="booking-settings__row-title">
										{type.name}
										{#if !type.is_active}<Badge status="inactive">Off</Badge>{/if}
									</span>
									<span class="booking-settings__row-facts">{typeFacts(type).join(' · ')}</span>
									<span class="booking-settings__row-link">{bookingPath(type.slug)}</span>
								</a>
								<div class="booking-settings__row-actions">
									<Button variant="secondary" size="small" onclick={() => copyLink(type)}>
										<span class="booking-settings__icon" aria-hidden="true"
											>{@html copiedSlug === type.slug ? checkIcon : copyIcon}</span
										>
										{copiedSlug === type.slug ? 'Copied' : 'Copy link'}<span
											class="booking-settings__sr"
										>
											for {type.name}</span
										>
									</Button>
									<Button
										variant="secondary"
										size="small"
										href={bookingPath(type.slug)}
										target="_blank"
									>
										<span class="booking-settings__icon" aria-hidden="true"
											>{@html externalIcon}</span
										>
										Open<span class="booking-settings__sr"> {type.name}</span>
									</Button>
								</div>
							</li>
						{/each}
					</ul>
				{/if}
				<div class="booking-settings__add">
					<Button
						variant="secondary"
						size="small"
						href={resolve('/jafar/settings/booking/types/new')}
					>
						<span class="booking-settings__icon" aria-hidden="true">{@html plusIcon}</span>
						Add meeting type
					</Button>
				</div>
			</SectionBlock>

			<SectionBlock
				title="Weekly hours"
				hint="When each host takes calls, in their own time zone. A teammate appears once they host a meeting."
			>
				<ul class="booking-settings__list">
					{#each settings.people as person (personKey(person.id))}
						<li class="booking-settings__row">
							<a
								class="booking-settings__row-main booking-settings__row-main--wide"
								href={resolve('/jafar/(protected)/settings/booking/hours/[person]', {
									person: personKey(person.id)
								})}
							>
								<span class="booking-settings__row-title">
									<span class="booking-settings__icon" aria-hidden="true">{@html clockIcon}</span>
									{person.name}
								</span>
								<span class="booking-settings__row-facts">
									{hoursSummary(hoursOf(settings, person.id))} · {zoneCity(
										person.id === null ? zone : person.time_zone
									)} time · hosts {hosting(person.id)}
									{hosting(person.id) === 1 ? 'meeting' : 'meetings'}
								</span>
							</a>
							<span class="booking-settings__chevron" aria-hidden="true"
								>{@html chevronRightIcon}</span
							>
						</li>
					{/each}
				</ul>
			</SectionBlock>
		</div>

		<aside class="booking-settings__rail">
			<Card heading="How booking works">
				<div class="booking-settings__about">
					<p>
						Each meeting offers only times that are free on its default host's <a
							href={resolve('/jafar/calendar')}>calendar</a
						>, inside their weekly hours. Calls and Busy blocks hide their time; a follow-up with a
						time does not.
					</p>
					<p>
						Two people can never book the same time. New bookings always go to the default host; you
						or a teammate can hand a booked call to another of its hosts from the call, once they
						are free then. The visitor is emailed.
					</p>
					{#if settings.bookings_count > 0}
						<p>
							<strong>{settings.bookings_count}</strong>
							{settings.bookings_count === 1 ? 'call has' : 'calls have'} been booked online.
						</p>
					{/if}
				</div>
			</Card>
		</aside>
	</div>

	<ConfirmDialog
		open={confirmSwitch}
		title={settings.enabled ? 'Close booking?' : 'Start taking bookings?'}
		confirmLabel={settings.enabled ? 'Close booking' : 'Start taking bookings'}
		destructive={settings.enabled}
		loading={switching}
		onConfirm={() => void toggleBookings()}
		onClose={() => (confirmSwitch = false)}
	>
		<p>
			{settings.enabled
				? 'Every booking link will say booking is closed. Calls already booked stay, and visitors can still change or cancel them.'
				: 'Anyone with a meeting link can book an open time straight away.'}
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.booking-settings {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 20rem;
		gap: var(--space-large);
		align-items: start;

		@media (max-width: 1024px) {
			grid-template-columns: 1fr;
		}
	}

	.booking-settings__main {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
		min-width: 0;
	}

	.booking-settings__switch {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-base);
	}

	.booking-settings__switch-title {
		margin: 0 0 var(--space-small);
	}

	.booking-settings__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.booking-settings__list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.booking-settings__row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-small) var(--space-base);
		padding: var(--space-base);

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		&:hover {
			background: var(--color-surface--background);
		}
	}

	.booking-settings__row-main {
		display: flex;
		flex: 1 1 16rem;
		flex-direction: column;
		gap: var(--space-smallest);
		min-width: 0;
		color: inherit;
		text-decoration: none;
		border-radius: var(--radius-small);

		&:focus-visible {
			outline: var(--focus-ring, 2px solid var(--color-interactive));
			outline-offset: var(--space-small);
		}
	}

	.booking-settings__row-title {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		font-weight: 600;
		color: var(--color-heading);
	}

	.booking-settings__row-facts,
	.booking-settings__row-link {
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
		overflow-wrap: anywhere;
	}

	.booking-settings__row-link {
		color: var(--color-text--tertiary, var(--color-text--secondary));
	}

	.booking-settings__row-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.booking-settings__add {
		display: flex;
	}

	.booking-settings__sr {
		position: absolute;
		width: 1px;
		height: 1px;
		margin: -1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
	}

	.booking-settings__chevron {
		display: inline-flex;
		color: var(--color-text--secondary);

		:global(svg) {
			width: 1.25rem;
			height: 1.25rem;
		}
	}

	.booking-settings__icon {
		display: inline-flex;

		:global(svg) {
			width: 1rem;
			height: 1rem;
		}
	}

	.booking-settings__about {
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
