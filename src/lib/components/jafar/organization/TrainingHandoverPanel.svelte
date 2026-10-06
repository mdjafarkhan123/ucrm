<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import flagIcon from '@tabler/icons/outline/flag-check.svg?raw';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import HandoverPackEditor from './HandoverPackEditor.svelte';
	import {
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import {
		organizationHandoverQuery,
		organizationHandoverUrl,
		organizationLaunchApprovalQuery,
		organizationTrainingUrl
	} from '$lib/jafar/organization-setup-queries';
	import {
		jafarOnboardingKey,
		jafarOrganizationHandoverKey,
		jafarOrganizationKey
	} from '$lib/jafar/query-keys';
	import { currentLaunchApproval } from '$lib/setup/launch-approval';
	import {
		DELIVERY_BLOCKER_LABEL,
		LINK_MAX,
		deliveryBlockers,
		formatMeetingTime,
		handoverEventText,
		momentToWallClock,
		trainingStatus,
		wallClockToMoment,
		type HandoverGuide
	} from '$lib/setup/training';
	import { formatDateTime } from './format';

	// Client onboarding E6 (plan §6, §8): after launch approval Jafar marks the system live, books the training the
	// client asked for (or sees the owner skipped it), adds the recording link while they consent, writes the handover
	// pack, and marks the project delivered once nothing blocks it. Live and Delivered cannot be undone. Industry
	// reference: client tasks and completion milestones in GUIDEcx and Rocketlane.
	let { organizationId }: { organizationId: string } = $props();

	const queryClient = useQueryClient();
	const data = createQuery(() => organizationHandoverQuery(organizationId));
	const approvals = createQuery(() => organizationLaunchApprovalQuery(organizationId));

	const handover = $derived(data.data?.handover ?? null);
	const training = $derived(data.data?.training ?? null);
	const approved = $derived(currentLaunchApproval(approvals.data ?? [])?.status === 'approved');
	const blockers = $derived(deliveryBlockers(handover, training));
	const status = $derived(trainingStatus(training));
	const zone = $derived(training?.time_zone ?? null);
	const meetingPassed = $derived(
		Boolean(training?.meeting_at && new Date(training.meeting_at).getTime() <= Date.now())
	);

	let confirm = $state<'live' | 'delivered' | 'cancel' | null>(null);
	let booking = $state(false);
	let meetingLocal = $state('');
	let meetingUrl = $state('');
	let recordingUrl = $state('');
	let error = $state('');
	let notice = $state('');

	const refresh = () =>
		Promise.all([
			queryClient.invalidateQueries({ queryKey: jafarOrganizationHandoverKey(organizationId) }),
			queryClient.invalidateQueries({ queryKey: jafarOrganizationKey(organizationId) }),
			queryClient.invalidateQueries({ queryKey: jafarOnboardingKey })
		]);

	async function post(url: string, body: unknown = {}) {
		const response = await fetch(url, {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
		const result = (await response.json().catch(() => ({}))) as {
			status?: string;
			emailed?: boolean;
			attendees?: number;
			error?: string;
			field_errors?: Record<string, string>;
		};
		if (!response.ok)
			throw new Error(
				Object.values(result.field_errors ?? {})[0] ??
					result.error ??
					'That could not be saved. Try again.'
			);
		return result;
	}

	const emailNote = (emailed: boolean | undefined, done: string, sent: string) =>
		emailed === false
			? `${done} The email could not be queued — tell them in Support.`
			: `${done} ${sent}`;

	function mutation<T>(
		run: (input: T) => Promise<Awaited<ReturnType<typeof post>>>,
		done: (result: Awaited<ReturnType<typeof post>>) => void
	) {
		return createMutation(() => ({
			mutationFn: run,
			onMutate: () => ((error = ''), (notice = '')),
			onSuccess: (result: Awaited<ReturnType<typeof post>>) => {
				confirm = null;
				done(result);
			},
			onError: (cause: Error) => {
				confirm = null;
				error = cause.message;
			},
			onSettled: refresh
		}));
	}

	const markLive = mutation<void>(
		() => post(`${organizationHandoverUrl(organizationId)}/live`),
		(result) =>
			(notice =
				result.status === 'unchanged'
					? 'Already live.'
					: emailNote(
							result.emailed,
							'Marked live.',
							'Their owners and administrators were emailed.'
						))
	);

	const markDelivered = mutation<void>(
		() => post(`${organizationHandoverUrl(organizationId)}/delivered`),
		(result) =>
			(notice =
				result.status === 'unchanged'
					? 'Already delivered.'
					: emailNote(
							result.emailed,
							'Project delivered.',
							'Their owners and administrators were emailed a link to the handover pack.'
						))
	);

	const book = mutation<{ meeting_at: string; meeting_url: string }>(
		(input) => post(`${organizationTrainingUrl(organizationId)}/booking`, input),
		(result) => {
			booking = false;
			notice =
				result.status === 'unchanged'
					? 'Nothing changed.'
					: emailNote(
							result.emailed,
							result.status === 'changed' ? 'Training moved.' : 'Training booked.',
							`${result.attendees} ${result.attendees === 1 ? 'person was' : 'people were'} emailed the details.`
						);
		}
	);

	const cancel = mutation<void>(
		() => post(`${organizationTrainingUrl(organizationId)}/cancel`),
		(result) =>
			(notice =
				result.status === 'unchanged'
					? 'There was no booking to cancel.'
					: emailNote(result.emailed, 'Training cancelled.', 'The attendees were emailed.'))
	);

	const setRecording = mutation<string | null>(
		(url) => post(`${organizationTrainingUrl(organizationId)}/recording`, { recording_url: url }),
		() => {
			notice = recordingUrl
				? 'Recording link added. It shows only on their handover pack.'
				: 'Recording link removed.';
			recordingUrl = '';
		}
	);

	const saveHandover = mutation<{ access_summary: string | null; guides: HandoverGuide[] }>(
		(input) => post(organizationHandoverUrl(organizationId), input),
		() => (notice = 'Handover saved.')
	);

	const busy = $derived(
		markLive.isPending ||
			markDelivered.isPending ||
			book.isPending ||
			cancel.isPending ||
			setRecording.isPending ||
			saveHandover.isPending
	);

	function openBooking() {
		error = '';
		meetingLocal = training?.meeting_at ? momentToWallClock(training.meeting_at, zone) : '';
		meetingUrl = training?.meeting_url ?? '';
		booking = true;
	}

	function submitBooking() {
		const moment = wallClockToMoment(meetingLocal, zone);
		if (!moment) {
			error = 'Choose the training date and time.';
			return;
		}
		book.mutate({ meeting_at: moment, meeting_url: meetingUrl.trim() });
	}
</script>

{#if data.isPending}
	<LoadingSkeleton variant="card" label="Loading training and handover" />
{:else if data.isError}
	<ErrorState
		title="Training and handover could not be loaded"
		description={data.error?.message}
		retry={() => data.refetch()}
	/>
{:else}
	<SectionBlock title="Training and handover" icon={flagIcon}>
		{#snippet actions()}
			{#if handover?.delivered_at}
				<StatusBadge status="success">Delivered</StatusBadge>
			{:else if handover?.live_at}
				<StatusBadge status="informative">Live</StatusBadge>
			{/if}
		{/snippet}
		<div class="handover-panel">
			{#if notice}<Banner type="success">{notice}</Banner>{/if}
			{#if error}<Banner type="error">{error}</Banner>{/if}

			<section class="handover-panel__part" aria-labelledby="handover-live">
				<h4 id="handover-live">1. Live</h4>
				{#if handover?.live_at}
					<p>
						Marked live {formatDateTime(handover.live_at)}{handover.live_version
							? ` on preview version ${handover.live_version}`
							: ''}. Later changes go through Chat with Uplift, not a new preview.
					</p>
				{:else if approved}
					<p class="handover-panel__muted">
						Once the approved system is really running on their address, mark it live. Their owners
						and administrators are emailed and asked to arrange training. This can’t be undone.
					</p>
					<div>
						<Button disabled={busy} onclick={() => (confirm = 'live')}>Mark as live</Button>
					</div>
				{:else}
					<p class="handover-panel__muted">Waits for the client’s launch approval above.</p>
				{/if}
			</section>

			<section class="handover-panel__part" aria-labelledby="handover-training">
				<h4 id="handover-training">2. Training</h4>
				{#if status === 'not_started'}
					<p class="handover-panel__muted">
						The client hasn’t given training details yet. Their owners and administrators can from
						Ready onward, on their Setup page.
					</p>
				{:else if status === 'skipped' && training}
					<p>
						<strong>{training.skipped_by_name}</strong> (owner) said they don’t need training on {formatDateTime(
							training.skipped_at!
						)}. If they ask for it later in Chat, book it below — it replaces the skip.
					</p>
				{/if}

				{#if training && training.attendees.length > 0}
					<dl class="handover-panel__facts">
						<dt>Who’s coming</dt>
						<dd>
							<ul>
								{#each training.attendees as attendee (attendee.email)}
									<li>
										{attendee.name}{attendee.role ? `, ${attendee.role}` : ''} —
										<a href={`mailto:${attendee.email}`}>{attendee.email}</a>
									</li>
								{/each}
							</ul>
						</dd>
						<dt>Times that suit them</dt>
						<dd>{training.preferred_times} <span class="handover-panel__muted">({zone})</span></dd>
						{#if training.top_tasks}<dt>What to show</dt>
							<dd>{training.top_tasks}</dd>{/if}
						{#if training.needs}<dt>Language or access needs</dt>
							<dd>{training.needs}</dd>{/if}
						<dt>Recording</dt>
						<dd>
							{training.recording_consent
								? 'They agree to a recording'
								: 'No recording'}{training.consent_changed_at
								? ` — ${training.consent_changed_by_name}, ${formatDateTime(training.consent_changed_at)}`
								: ''}
						</dd>
					</dl>
					{#if training.details_updated_at}
						<p class="handover-panel__muted">
							Details from {training.details_updated_by_name}, {formatDateTime(
								training.details_updated_at
							)}.
						</p>
					{/if}
				{/if}

				{#if training?.meeting_at}
					<div class="handover-panel__booked">
						<StatusBadge status="success">Booked</StatusBadge>
						<p>
							<strong>{formatMeetingTime(training.meeting_at, zone)}</strong><br />
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- an address on another site, given by Uplift. -->
							<a href={training.meeting_url} target="_blank" rel="noreferrer"
								>{training.meeting_url}</a
							>
						</p>
					</div>
				{/if}

				{#if booking}
					<div class="handover-panel__form">
						<p class="handover-panel__muted">
							Type the time as they will read it, in their time zone ({zone ?? 'UTC'}). The people
							they named are emailed the time and link.
						</p>
						<DateTimePicker
							id="training-meeting"
							dateLabel="Training date"
							timeLabel="Start time"
							required
							value={dateTimePickerValueFromLocalString(meetingLocal)}
							onchange={(value: DateTimePickerValue) =>
								(meetingLocal = dateTimePickerValueToLocalString(value))}
						/>
						<Input
							id="training-meeting-url"
							label="Meet or Zoom link"
							type="url"
							placeholder="https://"
							maxlength={LINK_MAX}
							bind:value={meetingUrl}
						/>
						<div class="handover-panel__actions">
							<Button
								disabled={busy || !meetingLocal || !meetingUrl.trim()}
								loading={book.isPending}
								onclick={submitBooking}
								>{training?.meeting_at
									? 'Save and email the new time'
									: 'Book and email them'}</Button
							>
							<Button variant="tertiary" disabled={book.isPending} onclick={() => (booking = false)}
								>Cancel</Button
							>
						</div>
					</div>
				{:else if training && training.attendees.length > 0}
					<div class="handover-panel__actions">
						<Button variant="secondary" disabled={busy} onclick={openBooking}
							>{training.meeting_at ? 'Change the time or link' : 'Book training'}</Button
						>
						{#if training.meeting_at}
							<Button
								variant="tertiary"
								variation="destructive"
								disabled={busy}
								onclick={() => (confirm = 'cancel')}>Cancel the training</Button
							>
						{/if}
					</div>
				{/if}
			</section>

			{#if training?.meeting_at || data.data?.recording_url}
				<section class="handover-panel__part" aria-labelledby="handover-recording">
					<h4 id="handover-recording">Recording</h4>
					{#if data.data?.recording_url}
						{#if training?.recording_consent !== true}
							<Banner type="warning">
								They withdrew consent, so the link is hidden from them. Restrict or delete the video
								where it is hosted, then remove the link here.
							</Banner>
						{/if}
						<p>
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -- an address on another site, given by Uplift. -->
							<a href={data.data.recording_url} target="_blank" rel="noreferrer"
								>{data.data.recording_url}</a
							>
							{#if data.data.recording_added_at}
								<span class="handover-panel__muted">
									— added {formatDateTime(data.data.recording_added_at)}</span
								>
							{/if}
						</p>
						<div>
							<Button
								variant="tertiary"
								variation="destructive"
								disabled={busy}
								loading={setRecording.isPending}
								onclick={() => setRecording.mutate(null)}>Remove the link</Button
							>
						</div>
					{:else if training?.recording_consent !== true}
						<p class="handover-panel__muted">They haven’t agreed to a recording.</p>
					{:else if !meetingPassed}
						<p class="handover-panel__muted">
							You can add the private video link once the training time has passed.
						</p>
					{:else}
						<p class="handover-panel__muted">
							A private link to the video (no uploads here). It shows only on their handover pack
							and is never emailed.
						</p>
						<div class="handover-panel__inline">
							<Input
								id="training-recording-url"
								label="Recording link"
								type="url"
								placeholder="https://"
								maxlength={LINK_MAX}
								bind:value={recordingUrl}
							/>
							<Button
								variant="secondary"
								disabled={busy || !recordingUrl.trim()}
								loading={setRecording.isPending}
								onclick={() => setRecording.mutate(recordingUrl.trim())}>Add link</Button
							>
						</div>
					{/if}
				</section>
			{/if}

			<section class="handover-panel__part" aria-labelledby="handover-pack">
				<h4 id="handover-pack">3. Handover pack</h4>
				<p class="handover-panel__muted">
					Their owners and administrators read this once delivered, with their launch approval, open
					outside waits and the support route. You can keep it up to date after delivery.
				</p>
				{#key handover?.updated_at}
					<HandoverPackEditor
						{handover}
						saving={saveHandover.isPending}
						onSave={(input) => saveHandover.mutate(input)}
					/>
				{/key}
			</section>

			{#if !handover?.delivered_at}
				<section class="handover-panel__part" aria-labelledby="handover-delivered">
					<h4 id="handover-delivered">4. Delivered</h4>
					{#if blockers.length}
						<p class="handover-panel__muted">Still needed before you can mark it delivered:</p>
						<ul class="handover-panel__blockers">
							{#each blockers as blocker (blocker)}<li>{DELIVERY_BLOCKER_LABEL[blocker]}</li>{/each}
						</ul>
					{:else}
						<p class="handover-panel__muted">
							Everything is in place. Outside waits still open stay listed on their handover pack
							and don’t hold this up.
						</p>
					{/if}
					<div>
						<Button disabled={busy || blockers.length > 0} onclick={() => (confirm = 'delivered')}
							>Mark as delivered</Button
						>
					</div>
				</section>
			{:else}
				<p class="handover-panel__muted">
					Delivered {formatDateTime(handover.delivered_at)}. Their dashboard card shows it for 14
					days; the handover pack stays in their Settings.
				</p>
			{/if}

			{#if data.data?.events.length}
				<details class="handover-panel__history">
					<summary>History ({data.data.events.length})</summary>
					<ul>
						{#each data.data.events as event (event.id)}
							<li>
								<span>{formatDateTime(event.happened_at)}</span>
								{handoverEventText(event, (value) =>
									formatMeetingTime(value, zone)
								)}{event.actor_kind === 'uplift' ? ` — ${event.actor_name}` : ''}
							</li>
						{/each}
					</ul>
				</details>
			{/if}
		</div>
	</SectionBlock>

	<ConfirmDialog
		open={confirm === 'live'}
		title="Mark the system as live?"
		confirmLabel="Mark as live"
		loading={markLive.isPending}
		onConfirm={() => markLive.mutate()}
		onClose={() => (confirm = null)}
	>
		<p>
			Do this once the approved version is really running. Their owners and administrators are
			emailed and asked to arrange training. After this, changes go through Chat with Uplift instead
			of a new preview. It can’t be undone.
		</p>
	</ConfirmDialog>

	<ConfirmDialog
		open={confirm === 'delivered'}
		title="Mark the project as delivered?"
		confirmLabel="Mark as delivered"
		tone="success"
		loading={markDelivered.isPending}
		onConfirm={() => markDelivered.mutate()}
		onClose={() => (confirm = null)}
	>
		<p>
			Their owners and administrators are emailed a link to the handover pack, and the project
			leaves your Onboarding list. It can’t be undone.
		</p>
	</ConfirmDialog>

	<ConfirmDialog
		open={confirm === 'cancel'}
		title="Cancel the training?"
		confirmLabel="Cancel the training"
		cancelLabel="Keep it"
		destructive
		loading={cancel.isPending}
		onConfirm={() => cancel.mutate()}
		onClose={() => (confirm = null)}
	>
		<p>
			Everyone they named is emailed that it is cancelled.{handover?.delivered_at
				? ''
				: ' Before delivery, you then need a new booking or the owner’s skip.'}
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	.handover-panel {
		display: grid;
		gap: var(--space-large);

		&__part {
			display: grid;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: 1px solid var(--color-border);

			&:first-of-type {
				padding-top: 0;
				border-top: 0;
			}

			h4 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
			}

			p {
				margin: 0;
			}
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__facts {
			display: grid;
			grid-template-columns: max-content minmax(0, 1fr);
			gap: var(--space-smaller) var(--space-base);
			margin: 0;

			dt {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}

			dd {
				margin: 0;
				overflow-wrap: anywhere;
				white-space: pre-line;
			}

			ul {
				margin: 0;
				padding: 0;
				list-style: none;
			}

			@media (max-width: 640px) {
				grid-template-columns: minmax(0, 1fr);

				dd {
					margin-bottom: var(--space-small);
				}
			}
		}

		&__booked {
			display: grid;
			justify-items: start;
			gap: var(--space-smaller);

			a {
				overflow-wrap: anywhere;
			}
		}

		&__form {
			display: grid;
			gap: var(--space-base);
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);
		}

		&__inline {
			display: grid;
			grid-template-columns: minmax(0, 1fr) auto;
			gap: var(--space-small);
			align-items: start;
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__blockers {
			display: grid;
			gap: var(--space-smaller);
			margin: 0;
			padding-left: var(--space-large);
		}

		&__history {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			summary {
				cursor: pointer;
			}

			ul {
				display: grid;
				gap: var(--space-smaller);
				margin: var(--space-small) 0 0;
				padding-left: var(--space-base);
			}

			span {
				margin-right: var(--space-small);
				font-variant-numeric: tabular-nums;
			}
		}
	}
</style>
