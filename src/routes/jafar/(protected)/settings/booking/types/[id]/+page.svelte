<script lang="ts">
	import { untrack } from 'svelte';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { beforeNavigate, goto } from '$app/navigation';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import calendarIcon from '@tabler/icons/outline/calendar-event.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import Breadcrumbs from '$lib/components/layout/Breadcrumbs.svelte';
	import RecordFormLayout from '$lib/components/layout/RecordFormLayout.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Card from '$lib/components/ui/Card.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import { jafarBookingHostsKey, jafarBookingKey } from '$lib/jafar/query-keys';
	import type { SetupOwnerChoice } from '$lib/jafar/deals';
	import {
		BUFFER_CHOICES,
		CHANGE_DEADLINE_CHOICES,
		DURATION_CHOICES,
		HORIZON_CHOICES,
		INTERVAL_CHOICES,
		MAX_VISITOR_REMINDERS,
		NOTICE_CHOICES,
		VISITOR_REMINDER_CHOICES,
		bookingPath,
		fetchBookingSettings,
		lengthWords,
		noticeWords,
		personKey,
		slugify,
		type BookingSettings,
		type MeetingType,
		type MeetingTypeInput
	} from '$lib/jafar/booking';

	// Jafar business management E3: one meeting type (plan § 6) -- what prospects see, which times it offers, who
	// may host it and who takes each new booking, and whether Jafar approves each one. `new` adds a type. A type
	// that has been booked can only be turned off, so its visitors' change and cancel links keep working.

	const queryClient = useQueryClient();
	const toast = getToastManager();
	const query = createQuery(() => ({ queryKey: jafarBookingKey, queryFn: fetchBookingSettings }));
	const hostsQuery = createQuery(() => ({
		queryKey: jafarBookingHostsKey,
		queryFn: async (): Promise<SetupOwnerChoice[]> => {
			const response = await fetch('/api/jafar/booking/hosts');
			const result = await response.json();
			if (!response.ok) throw new Error(result.error ?? 'Your team could not be loaded.');
			return result.choices;
		}
	}));

	const typeId = $derived(page.params.id ?? 'new');
	const isNew = $derived(typeId === 'new');
	const existing = $derived<MeetingType | undefined>(
		query.data?.meeting_types.find((type) => type.id === typeId)
	);

	type Draft = Omit<MeetingTypeInput, 'description'> & { description: string };

	let draft = $state<Draft | null>(null);
	let saved = $state('');
	let saving = $state(false);
	let deleting = $state(false);
	let confirmDelete = $state(false);
	let slugTouched = $state(false);
	let formError = $state('');
	let fieldErrors = $state<Record<string, string>>({});
	let layout = $state<RecordFormLayout>();

	function load(type: MeetingType | undefined) {
		draft = type
			? {
					slug: type.slug,
					name: type.name,
					description: type.description ?? '',
					duration_minutes: type.duration_minutes,
					min_notice_minutes: type.min_notice_minutes,
					horizon_days: type.horizon_days,
					buffer_minutes: type.buffer_minutes,
					slot_interval_minutes: type.slot_interval_minutes,
					requires_approval: type.requires_approval,
					change_deadline_minutes: type.change_deadline_minutes,
					is_active: type.is_active,
					visitor_reminder_minutes: [...type.visitor_reminder_minutes],
					host_member_id: type.host_member_id,
					host_member_ids: [...type.host_member_ids]
				}
			: {
					slug: '',
					name: '',
					description: '',
					duration_minutes: 30,
					min_notice_minutes: 240,
					horizon_days: 60,
					buffer_minutes: 0,
					slot_interval_minutes: 30,
					requires_approval: false,
					change_deadline_minutes: 240,
					is_active: true,
					visitor_reminder_minutes: [1440],
					host_member_id: null,
					host_member_ids: [null]
				};
		slugTouched = Boolean(type);
		saved = JSON.stringify(draft);
	}

	$effect(() => {
		const settings = query.data;
		if (settings) untrack(() => draft === null && load(existing));
	});

	const dirty = $derived(draft !== null && JSON.stringify(draft) !== saved);

	beforeNavigate((navigation) => {
		if (!dirty || saving || deleting) return;
		if (!confirm('Leave this page? Your changes have not been saved.')) navigation.cancel();
	});

	/** Jafar, everyone who can host now, and anyone already ticked who no longer can (flagged, to untick). */
	const hostRows = $derived.by(() => {
		const rows: { id: string | null; name: string; canHost: boolean }[] = [
			{ id: null, name: 'Jafar (you)', canHost: true }
		];
		for (const choice of hostsQuery.data ?? [])
			rows.push({ id: choice.id, name: choice.name, canHost: true });
		if (hostsQuery.data)
			for (const id of draft?.host_member_ids ?? [])
				if (id !== null && !rows.some((row) => row.id === id))
					rows.push({
						id,
						name: query.data?.people.find((person) => person.id === id)?.name ?? 'Former teammate',
						canHost: false
					});
		return rows;
	});

	function toggleHost(id: string | null, on: boolean) {
		if (!draft) return;
		const ids = draft.host_member_ids.filter((entry) => entry !== id);
		draft.host_member_ids = on ? [...ids, id] : ids;
		if (!draft.host_member_ids.includes(draft.host_member_id))
			draft.host_member_id = draft.host_member_ids[0] ?? null;
	}

	const defaultHostOptions = $derived(
		hostRows
			.filter((row) => draft?.host_member_ids.includes(row.id))
			.map((row) => ({ value: personKey(row.id), label: row.name }))
	);
	const defaultHost = {
		get value() {
			return draft ? personKey(draft.host_member_id) : '';
		},
		set value(next: string) {
			if (draft) draft.host_member_id = next === 'jafar' ? null : next;
		}
	};

	/** E2b: ticks a reminder time on or off, latest first, at most three. */
	function toggleReminder(minutes: number, on: boolean) {
		if (!draft) return;
		const rest = draft.visitor_reminder_minutes.filter((entry) => entry !== minutes);
		draft.visitor_reminder_minutes = (on ? [...rest, minutes] : rest).sort((a, b) => b - a);
	}

	function setName(value: string) {
		if (!draft) return;
		draft.name = value;
		if (!slugTouched) draft.slug = slugify(value);
	}

	async function save() {
		if (!draft || !dirty || saving) return;
		saving = true;
		formError = '';
		fieldErrors = {};
		const body: MeetingTypeInput = { ...draft, description: draft.description || null };
		const result = isNew
			? await sendLeadWrite('/api/jafar/booking/types', 'POST', body)
			: await sendLeadWrite(`/api/jafar/booking/types/${typeId}`, 'PATCH', body);
		if (!result.ok) {
			saving = false;
			formError = result.error;
			fieldErrors = result.fieldErrors;
			return;
		}
		queryClient.setQueryData(jafarBookingKey, result.data as BookingSettings);
		saved = JSON.stringify(draft);
		toast.success(isNew ? 'Meeting type added.' : 'Meeting type saved.');
		await goto(resolve('/jafar/settings/booking'));
		saving = false;
	}

	async function remove() {
		if (deleting) return;
		deleting = true;
		const result = await sendLeadWrite(`/api/jafar/booking/types/${typeId}`, 'DELETE');
		if (!result.ok) {
			deleting = false;
			confirmDelete = false;
			toast.error(result.error);
			return;
		}
		await queryClient.invalidateQueries({ queryKey: jafarBookingKey, exact: true });
		toast.success('Meeting type deleted.');
		await goto(resolve('/jafar/settings/booking'));
		deleting = false;
	}

	const options = (values: readonly number[], words: (value: number) => string) =>
		values.map((value) => ({ value: String(value), label: words(value) }));
	const durationOptions = options(DURATION_CHOICES, lengthWords);
	const noticeOptions = options(NOTICE_CHOICES, noticeWords);
	const horizonOptions = options(HORIZON_CHOICES, (days) => `${days} days ahead`);
	const bufferOptions = options(BUFFER_CHOICES, (minutes) =>
		minutes === 0 ? 'No gap' : `${minutes} min`
	);
	const deadlineOptions = options(CHANGE_DEADLINE_CHOICES, (minutes) =>
		minutes === 0 ? 'Until the call starts' : `Up to ${noticeWords(minutes)} before`
	);
	const intervalOptions = options(INTERVAL_CHOICES, (minutes) => `Every ${lengthWords(minutes)}`);

	type NumberKey =
		| 'duration_minutes'
		| 'min_notice_minutes'
		| 'horizon_days'
		| 'buffer_minutes'
		| 'slot_interval_minutes'
		| 'change_deadline_minutes';
	function numberField(key: NumberKey) {
		return {
			get value() {
				return draft ? String(draft[key]) : '';
			},
			set value(next: string) {
				if (draft) draft[key] = Number(next);
			}
		};
	}
	const duration = numberField('duration_minutes');
	const notice = numberField('min_notice_minutes');
	const horizon = numberField('horizon_days');
	const buffer = numberField('buffer_minutes');
	const interval = numberField('slot_interval_minutes');
	const deadline = numberField('change_deadline_minutes');

	const title = $derived(isNew ? 'New meeting type' : (existing?.name ?? 'Meeting type'));
</script>

<svelte:head><title>{title} · Booking · Settings · Control Room</title></svelte:head>

<Breadcrumbs
	items={[
		{ label: 'Settings', href: resolve('/jafar/settings') },
		{ label: 'Booking', href: resolve('/jafar/settings/booking') },
		{ label: title }
	]}
/>

{#if query.isError && !query.data}
	<ErrorState
		title="Booking settings could not be loaded"
		description={query.error.message}
		retry={() => query.refetch()}
	/>
{:else if !query.data}
	<!-- The card and its title draw at once; the fields fill in when the settings arrive. -->
	<RecordFormLayout {title} icon={calendarIcon}>
		{#snippet main()}
			<LoadingSkeleton variant="table" rows={4} label="Loading the meeting type" />
		{/snippet}
		{#snippet rail()}
			<LoadingSkeleton variant="table" rows={2} label="Loading this meeting" />
		{/snippet}
	</RecordFormLayout>
{:else if !isNew && !existing}
	<ErrorState
		title="That meeting type no longer exists"
		description="It may have been deleted. Go back to Booking to see the others."
	/>
{:else if draft}
	<RecordFormLayout {title} icon={calendarIcon} bind:this={layout} error={formError}>
		{#snippet main()}
			{#if draft}
				<form
					class="meeting-type"
					novalidate
					onsubmit={(event) => {
						event.preventDefault();
						void save().finally(() => layout?.revealError());
					}}
				>
					<SectionBlock title="Meeting" hint="What prospects see before they pick a time." form>
						<Toggle
							id="type-active"
							label="Taking bookings"
							description={draft.is_active
								? 'Anyone with this link can book an open time.'
								: 'This link says booking is closed. Calls already booked keep working.'}
							labelSide="start"
							bind:checked={draft.is_active}
						/>
						<div class="meeting-type__grid">
							<Input
								id="type-name"
								label="Name"
								required
								maxlength={120}
								invalid={Boolean(fieldErrors.name)}
								errorMessage={fieldErrors.name ?? ''}
								value={draft.name}
								oninput={(event: Event & { currentTarget: HTMLInputElement }) =>
									setName(event.currentTarget.value)}
							/>
							<Select
								id="type-length"
								label="Length"
								options={durationOptions}
								bind:value={duration.value}
							/>
						</div>
						<Input
							id="type-slug"
							label="Link ending"
							required
							maxlength={60}
							invalid={Boolean(fieldErrors.slug)}
							errorMessage={fieldErrors.slug ?? ''}
							value={draft.slug}
							oninput={(event: Event & { currentTarget: HTMLInputElement }) => {
								slugTouched = true;
								if (draft) draft.slug = event.currentTarget.value;
							}}
						/>
						<p class="meeting-type__note">
							{#if existing && draft.slug !== existing.slug && !fieldErrors.slug}
								After you save, the old link <strong>{bookingPath(existing.slug)}</strong> stops working.
							{:else}
								The link will be <strong>{page.url.origin}{bookingPath(draft.slug || '…')}</strong>
							{/if}
						</p>
						<Textarea
							id="type-description"
							label="Description"
							rows={3}
							maxlength={1000}
							invalid={Boolean(fieldErrors.description)}
							errorMessage={fieldErrors.description ?? ''}
							bind:value={draft.description}
						/>
						<div class="meeting-type__how">
							<span class="meeting-type__how-icon" aria-hidden="true">{@html phoneIcon}</span>
							<div>
								<p class="meeting-type__how-title">Phone call</p>
								<p class="meeting-type__note">
									The host calls the number the visitor gives when they book. Zoom and Google Meet
									come later.
								</p>
							</div>
						</div>
					</SectionBlock>

					<SectionBlock
						title="Hosts"
						hint="Who can take this meeting. New bookings go to the default host; a booked call can be handed to any other host."
						form
					>
						{#if hostsQuery.isError}
							<p class="meeting-type__note">
								Your team could not be loaded, so only you are shown.
								<Button variant="tertiary" size="small" onclick={() => hostsQuery.refetch()}
									>Try again</Button
								>
							</p>
						{/if}
						{#if !hostsQuery.data && !hostsQuery.isError}
							<LoadingSkeleton variant="text" rows={2} label="Loading your team" />
						{:else}
							<ul class="meeting-type__hosts">
								{#each hostRows as row (personKey(row.id))}
									<li class="meeting-type__host">
										<Checkbox
											id={`type-host-${personKey(row.id)}`}
											label={row.name}
											description={row.canHost
												? ''
												: 'Can no longer host: no Leads & Deals change access, or left the team. Untick to save.'}
											invalid={!row.canHost}
											checked={draft.host_member_ids.includes(row.id)}
											onchange={(on) => toggleHost(row.id, on)}
										/>
										{#if draft.host_member_id === row.id}
											<Badge status="informative">Default</Badge>
										{/if}
									</li>
								{/each}
							</ul>
						{/if}
						{#if fieldErrors.host_member_ids}
							<p class="meeting-type__error" role="alert">{fieldErrors.host_member_ids}</p>
						{/if}
						<div class="meeting-type__grid">
							<Select
								id="type-default-host"
								label="Default host"
								options={defaultHostOptions}
								placeholder="Tick a host first"
								disabled={defaultHostOptions.length === 0}
								bind:value={defaultHost.value}
							/>
						</div>
						{#if fieldErrors.host_member_id}
							<p class="meeting-type__error" role="alert">{fieldErrors.host_member_id}</p>
						{/if}
						<p class="meeting-type__note">
							Only teammates who can change Leads & Deals can host, because the call lands on their
							Lead. Each host's weekly hours are on the <a href={resolve('/jafar/settings/booking')}
								>Booking</a
							> page.
						</p>
					</SectionBlock>

					<SectionBlock title="Booking rules" hint="Which open times the link offers." form>
						<div class="meeting-type__grid">
							<Select
								id="type-notice"
								label="Minimum notice"
								options={noticeOptions}
								bind:value={notice.value}
							/>
							<Select
								id="type-horizon"
								label="How far ahead"
								options={horizonOptions}
								bind:value={horizon.value}
							/>
							<Select
								id="type-buffer"
								label="Gap around the host's meetings"
								options={bufferOptions}
								bind:value={buffer.value}
							/>
							<Select
								id="type-interval"
								label="Times start"
								options={intervalOptions}
								bind:value={interval.value}
							/>
						</div>
					</SectionBlock>

					<SectionBlock
						title="Confirming and changes"
						hint="Whether you approve each booking, and how late people can change theirs."
						form
					>
						<Toggle
							id="type-approval"
							label="Approve each booking first"
							description={draft.requires_approval
								? 'People send a request. It holds no time until it is approved on their Lead, and the time is checked again then.'
								: 'A free time is booked straight away and confirmed by email.'}
							labelSide="start"
							bind:checked={draft.requires_approval}
						/>
						<div class="meeting-type__grid">
							<Select
								id="type-deadline"
								label="People can change or cancel"
								options={deadlineOptions}
								bind:value={deadline.value}
							/>
						</div>
						<p class="meeting-type__note">
							Every email has a link to change or cancel. After this point, the link asks them to
							reply instead.
						</p>
					</SectionBlock>
					<SectionBlock
						title="Reminders"
						hint="Emails that remind the person who booked, before the call."
						form
					>
						<ul class="meeting-type__hosts">
							{#each VISITOR_REMINDER_CHOICES as minutes (minutes)}
								{@const ticked = draft.visitor_reminder_minutes.includes(minutes)}
								<li class="meeting-type__host">
									<Checkbox
										id={`type-reminder-${minutes}`}
										label={`${noticeWords(minutes)} before`}
										checked={ticked}
										disabled={!ticked &&
											draft.visitor_reminder_minutes.length >= MAX_VISITOR_REMINDERS}
										onchange={(on) => toggleReminder(minutes, on)}
									/>
								</li>
							{/each}
						</ul>
						{#if fieldErrors.visitor_reminder_minutes}
							<p class="meeting-type__error" role="alert">{fieldErrors.visitor_reminder_minutes}</p>
						{/if}
						<p class="meeting-type__note">
							{draft.visitor_reminder_minutes.length === 0
								? 'No reminders: people get only their booking email.'
								: `Choose up to ${MAX_VISITOR_REMINDERS}. A reminder is skipped when the call is booked after its time. Each one has the call's details, calendar links, and their change or cancel link.`}
						</p>
					</SectionBlock>
					<button type="submit" hidden aria-hidden="true" tabindex="-1"></button>
				</form>
			{/if}
		{/snippet}

		{#snippet rail()}
			{#if existing}
				<Card heading="This meeting">
					<div class="meeting-type__about">
						<p>
							<strong>{existing.bookings_count}</strong>
							{existing.bookings_count === 1 ? 'call has' : 'calls have'} been booked through this link.
						</p>
						{#if existing.bookings_count > 0}
							<p>
								It cannot be deleted, because those visitors' change and cancel links still need it.
								Turn off <strong>Taking bookings</strong> instead.
							</p>
						{:else}
							<Button variant="secondary" size="small" onclick={() => (confirmDelete = true)}>
								<span class="meeting-type__icon" aria-hidden="true">{@html trashIcon}</span>
								Delete meeting type
							</Button>
						{/if}
					</div>
				</Card>
			{:else}
				<Card heading="Adding a meeting">
					<div class="meeting-type__about">
						<p>
							Each meeting gets its own link. It offers only times free on its default host's
							calendar, inside their weekly hours.
						</p>
					</div>
				</Card>
			{/if}
		{/snippet}

		{#snippet actions()}
			<Button
				variant="secondary"
				onclick={() => void goto(resolve('/jafar/settings/booking'))}
				disabled={saving}>Cancel</Button
			>
			<Button
				onclick={() => void save().finally(() => layout?.revealError())}
				disabled={!dirty || saving}
				loading={saving}>{isNew ? 'Add meeting type' : 'Save'}</Button
			>
		{/snippet}
	</RecordFormLayout>

	<ConfirmDialog
		open={confirmDelete}
		title="Delete this meeting type?"
		confirmLabel="Delete"
		destructive
		loading={deleting}
		onConfirm={() => void remove()}
		onClose={() => (confirmDelete = false)}
	>
		<p>Its link stops working straight away. Nobody has booked through it yet.</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.meeting-type {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);
	}

	.meeting-type__grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-base);

		@media (max-width: 640px) {
			grid-template-columns: 1fr;
		}
	}

	.meeting-type__hosts {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
	}

	.meeting-type__host {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-base);
		padding: var(--space-small) var(--space-base);

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}
	}

	.meeting-type__how {
		display: flex;
		gap: var(--space-base);
		align-items: flex-start;
		padding: var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
	}

	.meeting-type__how-icon {
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

	.meeting-type__how-title {
		margin: 0;
		font-weight: 600;
		color: var(--color-text);
	}

	.meeting-type__note {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		overflow-wrap: anywhere;
	}

	.meeting-type__error {
		margin: 0;
		color: var(--color-critical);
		font-size: var(--typography--fontSize-small);
	}

	.meeting-type__icon {
		display: inline-flex;

		:global(svg) {
			width: 1rem;
			height: 1rem;
		}
	}

	.meeting-type__about {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-base);
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		line-height: var(--typography--lineHeight-base);

		p {
			margin: 0;
		}
	}
</style>
