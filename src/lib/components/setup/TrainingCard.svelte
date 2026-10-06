<script lang="ts">
	import { createMutation, createQuery, useQueryClient } from '@tanstack/svelte-query';
	import schoolIcon from '@tabler/icons/outline/school.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import videoIcon from '@tabler/icons/outline/video.svg?raw';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import Toggle from '$lib/components/ui/Toggle.svelte';
	import TimezonePicker from '$lib/components/ui/TimezonePicker.svelte';
	import ConfirmDialog from '$lib/components/ui/ConfirmDialog.svelte';
	import StatusBadge from '$lib/components/ui/StatusBadge.svelte';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import {
		fetchSetupTraining,
		saveSetupTraining,
		setSetupTrainingConsent,
		setupSummaryKey,
		setupTrainingKey,
		skipSetupTraining,
		type SetupWriteFailure
	} from '$lib/setup/api';
	import {
		TRAINING_ATTENDEES_MAX,
		TRAINING_NAME_MAX,
		TRAINING_ROLE_MAX,
		TRAINING_TASKS_MAX,
		TRAINING_TEXT_MAX,
		formatMeetingTime,
		trainingStatus,
		type TrainingAttendee
	} from '$lib/setup/training';
	import { getSupportAsk } from '$lib/support/ask';

	// Client onboarding E6 (plan §6): from Ready for Uplift onward, an owner or administrator tells Uplift who is
	// coming to training, when suits them and what to show; Uplift books the time and emails the meeting link to
	// those people. Until then the details can change; afterwards changes go through Chat with Uplift. The owner may
	// say they don't need training instead. Recording consent can be given or withdrawn at any time. Industry
	// reference: client tasks in GUIDEcx and Rocketlane.
	let { userId }: { userId: string | null } = $props();

	const queryClient = useQueryClient();
	const askUplift = getSupportAsk();
	const query = createQuery(() => ({
		queryKey: setupTrainingKey(userId),
		queryFn: fetchSetupTraining
	}));

	const training = $derived(query.data?.training ?? null);
	const status = $derived(trainingStatus(training));

	let editing = $state(false);
	let attendees = $state<TrainingAttendee[]>([]);
	let timeZone = $state('');
	let preferredTimes = $state('');
	let topTasks = $state('');
	let needs = $state('');
	let consent = $state(false);
	let confirmSkip = $state(false);
	let error = $state('');
	let fieldError = $state('');

	const refresh = () =>
		Promise.all([
			queryClient.invalidateQueries({ queryKey: setupTrainingKey(userId) }),
			queryClient.invalidateQueries({ queryKey: setupSummaryKey(userId) })
		]);

	const failure = (cause: Error) => (cause as SetupWriteFailure).fieldErrors?.form ?? cause.message;

	function startEditing() {
		error = '';
		fieldError = '';
		attendees = training?.attendees.length
			? training.attendees.map((attendee) => ({ ...attendee }))
			: [{ name: '', role: '', email: '' }];
		timeZone = training?.time_zone ?? Intl.DateTimeFormat().resolvedOptions().timeZone ?? '';
		preferredTimes = training?.preferred_times ?? '';
		topTasks = training?.top_tasks ?? '';
		needs = training?.needs ?? '';
		consent = training?.recording_consent ?? false;
		editing = true;
	}

	const save = createMutation(() => ({
		mutationFn: () =>
			saveSetupTraining({
				attendees: attendees.map((attendee) => ({
					name: attendee.name.trim(),
					role: attendee.role.trim(),
					email: attendee.email.trim()
				})),
				time_zone: timeZone,
				preferred_times: preferredTimes.trim(),
				needs: needs.trim() || null,
				top_tasks: topTasks.trim() || null,
				recording_consent: consent
			}),
		onMutate: () => ((error = ''), (fieldError = '')),
		onSuccess: () => (editing = false),
		onError: (cause) => (fieldError = failure(cause)),
		onSettled: refresh
	}));

	const skip = createMutation(() => ({
		mutationFn: skipSetupTraining,
		onMutate: () => (error = ''),
		onSuccess: () => ((confirmSkip = false), (editing = false)),
		onError: (cause) => ((confirmSkip = false), (error = failure(cause))),
		onSettled: refresh
	}));

	const changeConsent = createMutation(() => ({
		mutationFn: setSetupTrainingConsent,
		onMutate: () => (error = ''),
		onError: (cause) => (error = failure(cause)),
		onSettled: refresh
	}));

	function submit() {
		fieldError = '';
		if (attendees.some((attendee) => !attendee.name.trim() || !attendee.email.trim())) {
			fieldError = 'Give each person’s name and email address, or remove the empty row.';
			return;
		}
		if (!timeZone) {
			fieldError = 'Choose your time zone.';
			return;
		}
		if (!preferredTimes.trim()) {
			fieldError = 'Say which days and times suit you.';
			return;
		}
		save.mutate();
	}

	// The live email links to #training, which exists only once the answer has arrived.
	let scrolled = false;
	$effect(() => {
		if (!query.data || scrolled) return;
		scrolled = true;
		if (window.location.hash !== '#training') return;
		requestAnimationFrame(() =>
			document.getElementById('training')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
		);
	});

	const day = (value: string) =>
		new Date(value).toLocaleDateString(undefined, { day: 'numeric', month: 'long' });
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
{#if query.isPending}
	<LoadingSkeleton variant="card" label="Loading your training" />
{:else if query.isError}
	<ErrorState
		title="Your training details could not be loaded"
		description={query.error?.message}
		retry={() => query.refetch()}
	/>
{:else}
	<SectionBlock
		id="training"
		class="training-card-block"
		title="Training"
		icon={schoolIcon}
		hint="A short video call where Uplift shows your team how to use the system."
	>
		{#snippet actions()}
			{#if status === 'booked'}
				<StatusBadge status="success">Booked</StatusBadge>
			{:else if status === 'skipped'}
				<StatusBadge status="inactive">Not needed</StatusBadge>
			{:else if status === 'details_given'}
				<StatusBadge status="informative">Uplift is booking</StatusBadge>
			{/if}
		{/snippet}

		<div class="training">
			{#if error}<Banner type="error">{error}</Banner>{/if}

			{#if editing}
				<form
					class="training__form"
					onsubmit={(event) => {
						event.preventDefault();
						submit();
					}}
				>
					<fieldset class="training__people">
						<legend>Who’s coming?</legend>
						<p class="training__muted">
							Each person gets the meeting link by email once Uplift books it.
						</p>
						{#each attendees as attendee, index (index)}
							<div class="training__person">
								<Input
									id={`training-name-${index}`}
									label="Name"
									required
									maxlength={TRAINING_NAME_MAX}
									bind:value={attendee.name}
								/>
								<Input
									id={`training-role-${index}`}
									label="Role (optional)"
									placeholder="Office manager"
									maxlength={TRAINING_ROLE_MAX}
									bind:value={attendee.role}
								/>
								<Input
									id={`training-email-${index}`}
									label="Email"
									type="email"
									required
									maxlength={320}
									bind:value={attendee.email}
								/>
								{#if attendees.length > 1}
									<button
										type="button"
										class="training__remove"
										aria-label={`Remove ${attendee.name.trim() || `person ${index + 1}`}`}
										onclick={() => attendees.splice(index, 1)}
										><span aria-hidden="true">{@html trashIcon}</span></button
									>
								{/if}
							</div>
						{/each}
						{#if attendees.length < TRAINING_ATTENDEES_MAX}
							<button
								type="button"
								class="training__add"
								onclick={() => attendees.push({ name: '', role: '', email: '' })}
								><span aria-hidden="true">{@html plusIcon}</span>Add another person</button
							>
						{/if}
					</fieldset>

					<div class="training__field">
						<span class="training__label" id="training-zone-label">Your time zone</span>
						<TimezonePicker
							id="training-zone"
							labelledby="training-zone-label"
							required
							bind:value={timeZone}
						/>
					</div>
					<Textarea
						id="training-times"
						label="Which days and times suit you?"
						placeholder="Weekday mornings before 11, or Thursday afternoons"
						rows={2}
						required
						maxlength={TRAINING_TEXT_MAX}
						bind:value={preferredTimes}
					/>
					<Textarea
						id="training-tasks"
						label="What should Uplift show you? (optional)"
						placeholder="Sending quotes, booking jobs, replying to texts from the website"
						rows={3}
						maxlength={TRAINING_TASKS_MAX}
						bind:value={topTasks}
					/>
					<Textarea
						id="training-needs"
						label="Language or accessibility needs (optional)"
						rows={2}
						maxlength={TRAINING_TEXT_MAX}
						bind:value={needs}
					/>
					<Toggle
						id="training-consent"
						label="Uplift may record the training"
						description="So your team can watch it again. The video link is only on your handover pack, and you can change your mind any time."
						labelSide="start"
						checked={consent}
						onchange={(checked) => (consent = checked)}
					/>

					{#if fieldError}<Banner type="error">{fieldError}</Banner>{/if}
					<div class="training__actions">
						<Button type="submit" loading={save.isPending}>Send to Uplift</Button>
						<Button variant="tertiary" disabled={save.isPending} onclick={() => (editing = false)}
							>Cancel</Button
						>
					</div>
				</form>
			{:else if status === 'booked' && training?.meeting_at}
				<div class="training__booked">
					<span class="training__booked-icon" aria-hidden="true">{@html videoIcon}</span>
					<div>
						<p class="training__lead">
							{formatMeetingTime(training.meeting_at, training.time_zone)}
						</p>
						<p class="training__muted">
							The link was emailed to {training.attendees.map((person) => person.name).join(', ')}.
						</p>
					</div>
					{#if training.meeting_url}
						<Button href={training.meeting_url} target="_blank">Join the call</Button>
					{/if}
				</div>
				<p class="training__muted">
					Need a different time or someone else to come?
					<button type="button" class="training__link" onclick={() => askUplift(null)}
						>Ask in Chat with Uplift</button
					>.
				</p>
			{:else if status === 'skipped' && training?.skipped_at}
				<p>
					{training.skipped_by_name} said your team doesn’t need training on {day(
						training.skipped_at
					)}.
				</p>
				<p class="training__muted">
					Changed your mind?
					<button type="button" class="training__link" onclick={() => askUplift(null)}
						>Ask in Chat with Uplift</button
					> and Uplift will book it.
				</p>
			{:else if status === 'details_given' && training}
				<dl class="training__facts">
					<dt>Who’s coming</dt>
					<dd>
						{training.attendees
							.map((person) => (person.role ? `${person.name} (${person.role})` : person.name))
							.join(', ')}
					</dd>
					<dt>Times that suit you</dt>
					<dd>{training.preferred_times}</dd>
					{#if training.top_tasks}<dt>What to show</dt>
						<dd>{training.top_tasks}</dd>{/if}
					{#if training.needs}<dt>Needs</dt>
						<dd>{training.needs}</dd>{/if}
				</dl>
				<p class="training__muted">
					Uplift will pick a time from these and email everyone the link. You can change the details
					until then.
				</p>
				<div class="training__actions">
					<Button variant="secondary" onclick={startEditing}>Change the details</Button>
					{#if query.data?.is_owner}
						<Button variant="tertiary" onclick={() => (confirmSkip = true)}
							>We don’t need training</Button
						>
					{/if}
				</div>
			{:else}
				<p>
					Tell Uplift who should come and when suits you. We’ll book a video call and walk your team
					through the jobs they do every day.
				</p>
				<div class="training__actions">
					<Button onclick={startEditing}>Arrange training</Button>
					{#if query.data?.is_owner}
						<Button variant="tertiary" onclick={() => (confirmSkip = true)}
							>We don’t need training</Button
						>
					{/if}
				</div>
			{/if}

			{#if training && !editing}
				<div class="training__consent">
					<Toggle
						id="training-consent-standing"
						label="Uplift may record the training"
						description={training.consent_changed_at
							? `${training.recording_consent ? 'Agreed' : 'Not agreed'} by ${training.consent_changed_by_name} on ${day(training.consent_changed_at)}. You can change this any time.`
							: 'So your team can watch it again from your handover pack.'}
						labelSide="start"
						checked={training.recording_consent === true}
						disabled={changeConsent.isPending}
						onchange={(checked) => changeConsent.mutate(checked)}
					/>
				</div>
			{/if}
		</div>
	</SectionBlock>

	<ConfirmDialog
		open={confirmSkip}
		title="Skip training?"
		confirmLabel="We don’t need it"
		cancelLabel="Keep it"
		loading={skip.isPending}
		onConfirm={() => skip.mutate()}
		onClose={() => (confirmSkip = false)}
	>
		<p>
			Uplift won’t book a training call. If you change your mind later, ask in Chat with Uplift and
			we’ll book one.
		</p>
	</ConfirmDialog>
{/if}

<style lang="scss">
	:global(.training-card-block) {
		scroll-margin-top: var(--space-largest);
	}

	.training {
		display: grid;
		gap: var(--space-base);

		p {
			margin: 0;
		}

		&__lead {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}

		&__muted {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__form {
			display: grid;
			gap: var(--space-base);
		}

		&__people {
			display: grid;
			gap: var(--space-small);
			margin: 0;
			padding: 0;
			border: 0;

			legend {
				margin-bottom: var(--space-smaller);
				padding: 0;
				color: var(--color-heading);
				font-weight: 600;
			}
		}

		&__person {
			display: grid;
			grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1.3fr) 4.4rem;
			gap: var(--space-small);
			align-items: start;
			padding-bottom: var(--space-small);
			border-bottom: 1px solid var(--color-border);

			@media (max-width: 720px) {
				grid-template-columns: minmax(0, 1fr) 4.4rem;

				:global(> :not(.training__remove)) {
					grid-column: 1;
				}

				.training__remove {
					grid-column: 2;
					grid-row: 1;
				}
			}
		}

		&__field {
			display: grid;
			gap: var(--space-smaller);
		}

		&__label {
			color: var(--color-heading);
			font-weight: 600;
		}

		&__remove,
		&__add {
			display: inline-flex;
			align-items: center;
			justify-content: center;
			gap: var(--space-smaller);
			min-height: 4.4rem;
			padding: 0 var(--space-small);
			border: 0;
			border-radius: var(--radius-base);
			background: none;
			color: var(--color-text--secondary);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			:global(svg) {
				width: 1.6rem;
				height: 1.6rem;
			}

			&:hover {
				background: var(--color-surface--hover);
				color: var(--color-heading);
			}
		}

		&__add {
			justify-self: start;
			color: var(--color-interactive);
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__booked {
			display: grid;
			grid-template-columns: auto minmax(0, 1fr) auto;
			gap: var(--space-base);
			align-items: center;
			padding: var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-surface--background);

			@media (max-width: 560px) {
				grid-template-columns: auto minmax(0, 1fr);

				:global(> :last-child) {
					grid-column: 1 / -1;
				}
			}
		}

		&__booked-icon {
			display: grid;
			place-items: center;
			width: 4rem;
			height: 4rem;
			border-radius: 50%;
			background: var(--color-interactive--subtle);
			color: var(--color-interactive);

			:global(svg) {
				width: 2rem;
				height: 2rem;
			}
		}

		&__link {
			padding: 0;
			border: 0;
			background: none;
			color: var(--color-interactive);
			font: inherit;
			text-decoration: underline;
			cursor: pointer;
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

			@media (max-width: 560px) {
				grid-template-columns: minmax(0, 1fr);

				dd {
					margin-bottom: var(--space-small);
				}
			}
		}

		&__consent {
			padding-top: var(--space-base);
			border-top: 1px solid var(--color-border);
		}
	}
</style>
