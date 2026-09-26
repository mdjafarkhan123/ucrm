<script lang="ts">
	import { untrack } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Badge from '$lib/components/ui/Badge.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import SmsActionEditor from '$lib/components/settings/automation/SmsActionEditor.svelte';
	import EmailActionEditor from '$lib/components/settings/automation/EmailActionEditor.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { clientCommunicationHistoryKey } from '$lib/communications/inbox';
	import {
		REVIEW_MESSAGE_VARIABLES,
		REVIEW_STYLES,
		REVIEW_STYLE_LABELS,
		type ReviewChannel,
		type ReviewStyle
	} from '$lib/reviews/settings';
	import {
		REVIEW_REQUEST_STATUS_LABELS,
		REVIEW_REQUEST_STATUS_TONES,
		REVIEW_REQUEST_STOP_LABELS,
		cancelReviewRequest,
		createReviewRequest,
		type ReviewRequestContext
	} from '$lib/reviews/requests';
	import infoIcon from '@tabler/icons/outline/info-circle.svg?raw';

	// Google review campaign Part 3: the manual request panel's body, once its details have loaded. Follows
	// the brief's order: who to send to, how, which style, the message itself, then now or later. The style's
	// text keeps its {{variables}}; the server fills them and makes the customer's own link when it sends.
	let { context, onDone }: { context: ReviewRequestContext; onDone: () => void } = $props();

	const toast = getToastManager();
	const queryClient = useQueryClient();
	const NO_JOB = 'none';

	const dateFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
	const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
		day: 'numeric',
		month: 'short',
		hour: 'numeric',
		minute: '2-digit'
	});

	// Chosen once from the details as they first arrive; a background refetch never resets what the
	// contractor has picked or typed.
	const initial = untrack(() => {
		const channel: ReviewChannel = !context.sms_ready && context.email_ready ? 'email' : 'sms';
		return {
			channel,
			style: context.message_styles.default_style,
			jobId: context.job?.id ?? context.jobs[0]?.id ?? NO_JOB
		};
	});

	let channel = $state<ReviewChannel>(initial.channel);
	let style = $state<ReviewStyle>(initial.style);
	let jobId = $state(initial.jobId);
	let smsBody = $state(untrack(() => context.message_styles.sms[initial.style].body));
	let emailSubject = $state(untrack(() => context.message_styles.email[initial.style].subject));
	let emailBody = $state(untrack(() => context.message_styles.email[initial.style].body));
	let contactMethodId = $state(untrack(() => firstUsableContact(initial.channel)));
	let when = $state<'now' | 'later'>('now');
	let sendAt = $state(tomorrowMorning());
	let sending = $state(false);
	let cancellingId = $state<string | null>(null);
	let formError = $state('');
	// One key per attempt, so a double click or a retried request after a dropped connection sends once.
	let idempotencyKey = crypto.randomUUID();

	function firstUsableContact(value: ReviewChannel) {
		const usable =
			value === 'sms'
				? context.phones.filter((phone) => phone.sms_consent === 'opted_in')
				: context.emails.filter((email) => !email.suppressed);
		return usable[0]?.id ?? '';
	}

	// A datetime-local input wants the member's own wall-clock time, minute precision, no zone.
	function localInputValue(at: Date) {
		return new Date(at.getTime() - at.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
	}

	function tomorrowMorning() {
		const today = new Date();
		return localInputValue(
			new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1, 10, 0)
		);
	}

	function earliestScheduleValue() {
		return localInputValue(new Date(Math.ceil((Date.now() + 5 * 60_000) / 60_000) * 60_000));
	}

	const channelOptions = [
		{ value: 'sms', label: 'Text message' },
		{ value: 'email', label: 'Email' }
	];
	const styleOptions = REVIEW_STYLES.map((value) => ({ value, label: REVIEW_STYLE_LABELS[value] }));
	const whenOptions = [
		{ value: 'now', label: 'Send now' },
		{ value: 'later', label: 'Schedule' }
	];

	const jobOptions = $derived([
		...context.jobs.map((job) => ({
			value: job.id,
			label: `#${job.job_number}${job.title ? ` · ${job.title}` : ''} — completed ${dateFormat.format(new Date(job.last_completed_at))}`
		})),
		{ value: NO_JOB, label: 'No particular job' }
	]);

	const contactOptions = $derived(
		channel === 'sms'
			? context.phones.map((phone) => ({
					value: phone.id,
					label: contactLabel(phone.value, phone.contact_name, phone.label),
					...(phone.sms_consent === 'opted_in'
						? {}
						: {
								disabled: true,
								label: `${contactLabel(phone.value, phone.contact_name, phone.label)} — ${
									phone.sms_consent === 'opted_out'
										? 'opted out of texts'
										: 'no permission to text on file'
								}`
							})
				}))
			: context.emails.map((email) => ({
					value: email.id,
					label: email.suppressed
						? `${contactLabel(email.value, email.contact_name, email.label)} — unsubscribed or bounced`
						: contactLabel(email.value, email.contact_name, email.label),
					disabled: Boolean(email.suppressed)
				}))
	);

	function contactLabel(value: string, name: string | null, label: string | null) {
		const who = [name, label].filter(Boolean).join(', ');
		return who ? `${value} (${who})` : value;
	}

	// Why the chosen channel cannot send, in the contractor's words, or '' when it can.
	const channelProblem = $derived.by(() => {
		if (channel === 'sms') {
			if (context.sms_reason === 'no_number')
				return 'Your business does not have a texting number yet. Send this by email instead.';
			if (context.sms_reason === 'paused') return 'Texting is paused for your business right now.';
			if (context.sms_reason === 'not_ready')
				return 'Your texting number is not ready to send yet.';
			if (context.phones.length === 0) return 'This customer has no mobile number saved.';
			if (!context.phones.some((phone) => phone.sms_consent === 'opted_in'))
				return 'None of this customer’s numbers have permission to receive texts on file.';
			return '';
		}
		if (!context.email_ready) return 'Your business email is not set up to send yet.';
		if (context.emails.length === 0) return 'This customer has no email address saved.';
		if (!context.emails.some((email) => !email.suppressed))
			return 'This customer’s email addresses unsubscribed or could not receive email.';
		return '';
	});

	const jobProblem = $derived(
		context.job && !context.job.eligible
			? 'Ask for a review once work on this job has been completed.'
			: ''
	);

	const canSend = $derived(
		context.has_google_link && !channelProblem && !jobProblem && Boolean(contactMethodId)
	);

	function selectChannel(value: string) {
		channel = value as ReviewChannel;
		contactMethodId = firstUsableContact(channel);
		formError = '';
	}

	// Picking a style replaces the message with that style's saved text, the way a template picker does.
	function selectStyle(value: string) {
		style = value as ReviewStyle;
		smsBody = context.message_styles.sms[style].body;
		emailSubject = context.message_styles.email[style].subject;
		emailBody = context.message_styles.email[style].body;
	}

	async function refresh() {
		await Promise.all([
			queryClient.invalidateQueries({ queryKey: ['reviews', 'request-context'] }),
			queryClient.invalidateQueries({ queryKey: ['communications', 'inbox'] }),
			queryClient.invalidateQueries({ queryKey: clientCommunicationHistoryKey(context.client.id) })
		]);
	}

	async function send() {
		if (!canSend || sending) return;
		let sendAtIso: string | null = null;
		if (when === 'later') {
			const at = new Date(sendAt);
			if (!sendAt || Number.isNaN(at.getTime()) || at.getTime() <= Date.now()) {
				formError = 'Choose a send time in the future.';
				return;
			}
			sendAtIso = at.toISOString();
		}
		sending = true;
		formError = '';
		try {
			await createReviewRequest({
				client_id: context.client.id,
				job_id: context.job?.id ?? (jobId === NO_JOB ? null : jobId),
				channel,
				style,
				contact_method_id: contactMethodId,
				subject: channel === 'email' ? emailSubject : '',
				body: channel === 'sms' ? smsBody : emailBody,
				send_at: sendAtIso,
				idempotency_key: idempotencyKey
			});
			idempotencyKey = crypto.randomUUID();
			await refresh();
			toast.success(
				sendAtIso
					? `Review request scheduled for ${dateTimeFormat.format(new Date(sendAtIso))}`
					: 'Review request sent'
			);
			onDone();
		} catch (error) {
			formError = (error as Error).message;
		} finally {
			sending = false;
		}
	}

	async function cancel(id: string) {
		cancellingId = id;
		formError = '';
		try {
			await cancelReviewRequest(id);
			await refresh();
			toast.success('Review request cancelled');
		} catch (error) {
			formError = (error as Error).message;
		} finally {
			cancellingId = null;
		}
	}

	// "2 reminders will follow, 3 and 5 days after the first message": the plan this request will follow.
	const planNote = $derived.by(() => {
		const waits = context.reminder_wait_days;
		if (waits.length === 0) return 'No reminders will follow. You can add them in Review settings.';
		const days = waits.map((_, index) =>
			waits.slice(0, index + 1).reduce((total, wait) => total + wait, 0)
		);
		const list =
			days.length === 1 ? `${days[0]}` : `${days.slice(0, -1).join(', ')} and ${days.at(-1)}`;
		const count = waits.length === 1 ? '1 reminder follows' : `${waits.length} reminders follow`;
		return `${count}, ${list} days after the first message goes out. They stop as soon as the customer responds.`;
	});

	// Where the request's reminders stand, when that adds to the status badge.
	function reminderLine(request: ReviewRequestContext['requests'][number]) {
		const sent = request.messages.filter(
			(message) => message.slot > 0 && message.state !== 'cancelled'
		).length;
		const parts: string[] = [];
		if (sent > 0) parts.push(sent === 1 ? '1 reminder sent' : `${sent} reminders sent`);
		if (request.next_reminder_at && request.status !== 'cancelled') {
			parts.push(`next reminder ${dateFormat.format(new Date(request.next_reminder_at))}`);
		} else if (
			request.stop_reason &&
			!['cancelled', 'continued_to_google', 'feedback_submitted'].includes(request.stop_reason)
		) {
			parts.push(
				`reminders stopped: ${REVIEW_REQUEST_STOP_LABELS[request.stop_reason].toLowerCase()}`
			);
		}
		const line = parts.join(' · ');
		return line ? line.charAt(0).toUpperCase() + line.slice(1) : '';
	}

	function requestLine(request: ReviewRequestContext['requests'][number]) {
		const how = request.channel === 'sms' ? 'Text' : 'Email';
		const to = request.recipient ? ` to ${request.recipient}` : '';
		const at =
			request.status === 'scheduled' && request.send_at
				? `for ${dateTimeFormat.format(new Date(request.send_at))}`
				: dateFormat.format(new Date(request.created_at));
		const job = !context.job && request.job_number ? ` · Job #${request.job_number}` : '';
		return `${how}${to} · ${at}${job}`;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<form
	class="review-request"
	onsubmit={(event) => {
		event.preventDefault();
		void send();
	}}
>
	{#if !context.has_google_link}
		<p class="review-request__notice review-request__notice--warning">
			<span aria-hidden="true">{@html infoIcon}</span>
			Add your Google review link in Review settings before asking customers for reviews.
		</p>
	{/if}

	{#if context.last_asked_at}
		<p class="review-request__notice">
			<span aria-hidden="true">{@html infoIcon}</span>
			{context.client.name} was already asked for a review on {dateFormat.format(
				new Date(context.last_asked_at)
			)}. You can still send another.
		</p>
	{/if}

	{#if jobProblem}
		<p class="review-request__notice review-request__notice--warning">
			<span aria-hidden="true">{@html infoIcon}</span>{jobProblem}
		</p>
	{/if}

	{#if !context.job}
		<Select
			id="review-request-job"
			label="About"
			options={jobOptions}
			bind:value={jobId}
			disabled={sending}
		/>
	{/if}

	<div class="review-request__row">
		<SegmentedControl
			label="Send by"
			options={channelOptions}
			value={channel}
			disabled={sending}
			onchange={selectChannel}
		/>
		<SegmentedControl
			label="Style"
			options={styleOptions}
			value={style}
			disabled={sending}
			onchange={selectStyle}
		/>
	</div>

	{#if channelProblem}
		<p class="review-request__notice review-request__notice--warning">
			<span aria-hidden="true">{@html infoIcon}</span>{channelProblem}
		</p>
	{:else}
		<Select
			id="review-request-contact"
			label="Send to"
			placeholder="Choose who to send it to"
			options={contactOptions}
			bind:value={contactMethodId}
			disabled={sending}
		/>
	{/if}

	{#if channel === 'sms'}
		<SmsActionEditor
			idPrefix="review-request-sms"
			body={smsBody}
			variables={REVIEW_MESSAGE_VARIABLES}
			showSender={false}
			onBodyChange={(value) => (smsBody = value)}
		/>
	{:else}
		<EmailActionEditor
			idPrefix="review-request-email"
			subject={emailSubject}
			body={emailBody}
			variables={REVIEW_MESSAGE_VARIABLES}
			onSubjectChange={(value) => (emailSubject = value)}
			onBodyChange={(value) => (emailBody = value)}
		/>
	{/if}

	<div class="review-request__when">
		<SegmentedControl label="When" options={whenOptions} bind:value={when} disabled={sending} />
		{#if when === 'later'}
			<Input
				id="review-request-send-at"
				label="Send at"
				type="datetime-local"
				bind:value={sendAt}
				min={earliestScheduleValue()}
				disabled={sending}
			/>
		{/if}
	</div>
	<p class="review-request__plan">{planNote}</p>

	{#if context.requests.length > 0}
		<section class="review-request__history" aria-labelledby="review-request-history-title">
			<h3 id="review-request-history-title">Recent requests</h3>
			<ul>
				{#each context.requests as request (request.id)}
					<li class="review-request__item">
						<div class="review-request__item-text">
							<Badge status={REVIEW_REQUEST_STATUS_TONES[request.status]} size="small">
								{REVIEW_REQUEST_STATUS_LABELS[request.status]}
							</Badge>
							<span>{requestLine(request)}</span>
							{#if reminderLine(request)}
								<span class="review-request__item-reminders">{reminderLine(request)}</span>
							{/if}
							{#if request.stop_detail && request.stop_reason && ['not_sent', 'not_delivered'].includes(request.stop_reason)}
								<span class="review-request__item-failure">{request.stop_detail}</span>
							{/if}
							{#if request.status === 'failed' && request.failure_message}
								<span class="review-request__item-failure">{request.failure_message}</span>
							{/if}
						</div>
						{#if request.cancellable}
							<Button
								size="small"
								variant="tertiary"
								variation="destructive"
								loading={cancellingId === request.id}
								disabled={cancellingId !== null && cancellingId !== request.id}
								onclick={() => void cancel(request.id)}
							>
								Cancel
							</Button>
						{/if}
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	{#if formError}<p class="review-request__error" role="alert">{formError}</p>{/if}

	<footer class="review-request__footer">
		<Button variant="secondary" onclick={onDone} disabled={sending}>Close</Button>
		<Button variant="primary" type="submit" loading={sending} disabled={!canSend}>
			{when === 'later' ? 'Schedule request' : 'Send request'}
		</Button>
	</footer>
</form>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.review-request {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__row {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-base);
		}

		&__when {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-end;
			gap: var(--space-base);
		}

		&__notice {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--active);
			font-size: var(--typography--fontSize-small);

			span {
				display: inline-flex;
				flex-shrink: 0;
				width: 18px;
				height: 18px;

				:global(svg) {
					width: 100%;
					height: 100%;
				}
			}

			&--warning {
				color: var(--color-warning--onSurface);
				background: var(--color-warning--surface);
			}
		}

		&__history {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
			padding-top: var(--space-base);
			border-top: var(--border-base) solid var(--color-border);

			h3 {
				margin: 0;
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}

			ul {
				display: flex;
				flex-direction: column;
				gap: var(--space-small);
				margin: 0;
				padding: 0;
				list-style: none;
			}
		}

		&__item {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__item-text {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
			min-width: 0;
			color: var(--color-text);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}

		&__plan {
			margin: calc(var(--space-small) * -1) 0 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__item-reminders {
			flex-basis: 100%;
			color: var(--color-text--secondary);
		}

		&__item-failure {
			flex-basis: 100%;
			color: var(--color-critical);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__footer {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
			margin-top: var(--space-small);
		}
	}
</style>
