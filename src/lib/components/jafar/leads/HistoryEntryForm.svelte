<script lang="ts">
	import { untrack } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import {
		dateTimePickerValueFromDate,
		dateTimePickerValueFromLocalString,
		dateTimePickerValueToLocalString,
		localDateTimeToIso,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import {
		CALL_OUTCOMES,
		CALL_OUTCOME_LABELS,
		CHANNEL_METHOD_KINDS,
		CONTACT_CHANNELS,
		CONTACT_CHANNEL_LABELS,
		CONTACT_DIRECTION_LABELS,
		CONTACT_FUTURE_SKEW_MS,
		HISTORY_BODY_MAX,
		takesCallOutcome,
		type CallOutcome,
		type ContactChannel,
		type ContactDirection,
		type HistoryEntry,
		type LeadContactMethodDetail
	} from '$lib/jafar/lead-history';
	import { CONTACT_METHOD_LABELS } from '$lib/jafar/leads';
	import { refreshLead, sendLeadWrite } from '$lib/jafar/lead-page-api';

	// Jafar business management B2: adding to a Lead's history -- a note, or contact that happened outside UCRM
	// (an email sent from Gmail, a call, a reply) -- and correcting one already there. Logged contact names who
	// reached out, how, which saved detail was used, when, and what was said; a call we made also says how it went.
	let {
		leadId,
		contactMethods,
		entry,
		idPrefix,
		onSaved,
		onCancel
	}: {
		leadId: string;
		contactMethods: LeadContactMethodDetail[];
		/** The note or logged contact being corrected; adding a new one when absent. */
		entry?: HistoryEntry;
		idPrefix: string;
		onSaved?: () => void;
		onCancel?: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	type Kind = 'note' | 'contact';

	function nowLocal() {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(new Date()));
	}

	function localFromIso(iso: string) {
		return dateTimePickerValueToLocalString(dateTimePickerValueFromDate(new Date(iso)));
	}

	// The form starts from the entry being corrected, or blank with "now" as when it happened.
	const start = untrack(() => entry);
	let kind = $state<Kind>(start?.kind === 'contact' ? 'contact' : 'note');
	let direction = $state<ContactDirection>(start?.contact_direction ?? 'outbound');
	let channel = $state<ContactChannel | ''>(start?.contact_channel ?? '');
	let methodId = $state(start?.contact_method?.id ?? '');
	let callOutcome = $state<CallOutcome | ''>(start?.call_outcome ?? '');
	let occurredLocal = $state(start ? localFromIso(start.occurred_at) : nowLocal());
	// The picker shows minutes only. Left at "now", the exact moment is sent, so contact logged right after
	// adding a Lead is not listed before "Lead added".
	let occurredUntouched = $state(!start);
	let body = $state(start?.body ?? '');

	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);

	const editing = $derived(Boolean(entry));
	const needsOutcome = $derived(channel !== '' && takesCallOutcome(channel, direction));

	// Only the details this channel could have used: a call or a text goes to a phone number.
	function methodsFor(value: ContactChannel | '') {
		if (value === '') return [];
		const kinds = CHANNEL_METHOD_KINDS[value];
		return contactMethods.filter((method) => kinds.includes(method.kind));
	}
	const methodChoices = $derived(methodsFor(channel));
	const methodOptions = $derived([
		{ value: '', label: 'Not one saved on this Lead' },
		...methodChoices.map((method) => ({
			value: method.id,
			label: `${CONTACT_METHOD_LABELS[method.kind]}: ${method.value}`
		}))
	]);
	// A detail chosen for another channel is not sent for this one.
	const chosenMethod = $derived(
		methodChoices.some((method) => method.id === methodId) ? methodId : ''
	);

	const channelOptions = CONTACT_CHANNELS.map((value) => ({
		value,
		label: CONTACT_CHANNEL_LABELS[value]
	}));
	const outcomeOptions = CALL_OUTCOMES.map((value) => ({
		value,
		label: CALL_OUTCOME_LABELS[value]
	}));
	const directionOptions = (['outbound', 'inbound'] as const).map((value) => ({
		value,
		label: CONTACT_DIRECTION_LABELS[value]
	}));

	const pickerValue = $derived(dateTimePickerValueFromLocalString(occurredLocal));

	function selectChannel(value: string) {
		channel = value as ContactChannel;
		// One saved detail for this channel is almost always the one used.
		const choices = methodsFor(channel);
		if (!choices.some((method) => method.id === methodId))
			methodId = choices.length === 1 ? choices[0].id : '';
	}

	function payload() {
		if (kind === 'note') return { kind, body };
		return {
			kind,
			contact_direction: direction,
			contact_channel: channel || undefined,
			contact_method_id: chosenMethod || null,
			call_outcome: needsOutcome ? callOutcome || null : null,
			occurred_at:
				occurredUntouched && occurredLocal === nowLocal()
					? new Date().toISOString()
					: localDateTimeToIso(occurredLocal) || undefined,
			body
		};
	}

	// The same checks the server makes, so the common slips are caught before a round trip.
	function localErrors() {
		const errors: Record<string, string> = {};
		if (kind === 'note') {
			if (!body.trim()) errors.body = 'Write the note.';
			return errors;
		}
		if (!channel) errors.contact_channel = 'Choose how.';
		if (needsOutcome && !callOutcome) errors.call_outcome = 'Choose how the call went.';
		const when = localDateTimeToIso(occurredLocal);
		if (!when) errors.occurred_at = 'Choose when it happened.';
		else if (Date.parse(when) > Date.now() + CONTACT_FUTURE_SKEW_MS)
			errors.occurred_at =
				'Contact you log has already happened — choose a time that is not in the future.';
		return errors;
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (saving) return;
		formError = '';
		fieldErrors = localErrors();
		if (Object.keys(fieldErrors).length) return;

		saving = true;
		const base = `/api/jafar/leads/${encodeURIComponent(leadId)}/history`;
		const result = entry
			? await sendLeadWrite(`${base}/${encodeURIComponent(entry.id)}`, 'PATCH', payload())
			: await sendLeadWrite(base, 'POST', payload());
		saving = false;
		if (!result.ok) {
			fieldErrors = result.fieldErrors;
			formError = result.error;
			return;
		}
		await refreshLead(queryClient, leadId);
		toast.success(editing ? 'Change saved' : kind === 'note' ? 'Note added' : 'Contact logged');
		if (!entry) {
			// Ready for the next one, keeping the kind the person is working with.
			body = '';
			callOutcome = '';
			occurredLocal = nowLocal();
			occurredUntouched = true;
		}
		onSaved?.();
	}
</script>

<form class="history-form" onsubmit={submit} novalidate>
	{#if !editing}
		<SegmentedControl
			ariaLabel="What to add"
			name={`${idPrefix}-kind`}
			size="small"
			bind:value={kind}
			options={[
				{ value: 'note', label: 'Note' },
				{ value: 'contact', label: 'Log contact' }
			]}
			onchange={() => (fieldErrors = {})}
		/>
	{/if}

	{#if kind === 'contact'}
		<div class="history-form__direction">
			<SegmentedControl
				label="Who reached out"
				name={`${idPrefix}-direction`}
				size="small"
				fullWidth
				bind:value={direction}
				options={directionOptions}
			/>
		</div>

		<div class="history-form__grid">
			<div class="history-form__field">
				<Select
					id={`${idPrefix}-channel`}
					label="How"
					placeholder="Choose a channel"
					required
					value={channel}
					options={channelOptions}
					onchange={selectChannel}
				/>
				{#if fieldErrors.contact_channel}<p class="history-form__error">
						{fieldErrors.contact_channel}
					</p>{/if}
			</div>

			{#if channel && channel !== 'in_person'}
				<div class="history-form__field">
					<Select
						id={`${idPrefix}-method`}
						label={direction === 'outbound' ? 'Sent to' : 'Came from'}
						value={chosenMethod}
						options={methodOptions}
						onchange={(value) => (methodId = value)}
					/>
					{#if fieldErrors.contact_method_id}<p class="history-form__error">
							{fieldErrors.contact_method_id}
						</p>{/if}
				</div>
			{/if}

			{#if needsOutcome}
				<div class="history-form__field">
					<Select
						id={`${idPrefix}-outcome`}
						label="How the call went"
						placeholder="Choose an outcome"
						required
						value={callOutcome}
						options={outcomeOptions}
						onchange={(value) => (callOutcome = value as CallOutcome)}
					/>
					{#if fieldErrors.call_outcome}<p class="history-form__error">
							{fieldErrors.call_outcome}
						</p>{/if}
				</div>
			{/if}

			<div class="history-form__field history-form__field--when">
				<DateTimePicker
					id={`${idPrefix}-when`}
					dateLabel="Date"
					timeLabel="Time"
					required
					invalid={Boolean(fieldErrors.occurred_at)}
					value={pickerValue}
					onchange={(value: DateTimePickerValue) => {
						occurredLocal = dateTimePickerValueToLocalString(value);
						occurredUntouched = false;
					}}
				/>
				{#if fieldErrors.occurred_at}<p class="history-form__error">
						{fieldErrors.occurred_at}
					</p>{/if}
			</div>
		</div>
	{/if}

	<Textarea
		id={`${idPrefix}-body`}
		label={kind === 'note' ? 'Note' : 'What was said (optional)'}
		rows={kind === 'note' ? 3 : 2}
		maxlength={HISTORY_BODY_MAX}
		placeholder={kind === 'note'
			? 'Something worth remembering about this business'
			: 'e.g. Sent the intro email; asked for a 15-minute call'}
		required={kind === 'note'}
		invalid={Boolean(fieldErrors.body)}
		errorMessage={fieldErrors.body ?? ''}
		bind:value={body}
	/>

	{#if formError && !Object.keys(fieldErrors).some((key) => key !== 'form')}
		<p class="history-form__error" role="alert">{formError}</p>
	{/if}

	<div class="history-form__actions">
		{#if onCancel}
			<Button variant="tertiary" type="button" onclick={onCancel} disabled={saving}>Cancel</Button>
		{/if}
		<Button variant="primary" type="submit" loading={saving}>
			{editing ? 'Save change' : kind === 'note' ? 'Add note' : 'Log contact'}
		</Button>
	</div>
</form>

<style lang="scss">
	.history-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);
		min-width: 0;

		&__grid {
			display: grid;
			grid-template-columns: repeat(2, minmax(0, 1fr));
			gap: var(--space-base);
		}

		&__field {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			min-width: 0;
		}

		&__field--when {
			grid-column: 1 / -1;
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}

		&__actions {
			display: flex;
			justify-content: flex-end;
			gap: var(--space-small);
		}
	}

	@media (max-width: 639px) {
		.history-form__grid {
			grid-template-columns: minmax(0, 1fr);
		}

		.history-form__actions {
			flex-direction: column-reverse;

			:global(.button) {
				width: 100%;
			}
		}
	}
</style>
