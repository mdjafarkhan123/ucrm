<script lang="ts">
	import { untrack } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { CalendarDate, today, getLocalTimeZone } from '@internationalized/date';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import RadioGroup from '$lib/components/ui/RadioGroup.svelte';
	import CalendarPicker from '$lib/components/ui/CalendarPicker.svelte';
	import { getToastManager } from '$lib/components/ui/ToastManager.svelte';
	import { calendarDateFromString } from '$lib/components/ui/date-time';
	import { sendLeadWrite } from '$lib/jafar/lead-page-api';
	import {
		DEAL_STAGE_LABELS,
		DEAL_START_STAGES,
		STAGES_NEEDING_DATE,
		refreshDeals,
		suggestedNextStep,
		type DealStartStage,
		type OpenDealStage
	} from '$lib/jafar/deals';

	// Jafar business management B4: every Deal change that only needs a next step -- starting a Deal, moving it to
	// another stage, and reopening a Lost one. An open Deal always has a dated next step (B4 Q10): a stage that
	// comes with its own date (a call, a revisit, a follow-up) prefills one; the others keep the current step.
	type Action =
		| { kind: 'start'; relationshipId: string }
		| { kind: 'move'; dealId: string; relationshipId: string; stage: OpenDealStage }
		| { kind: 'reopen'; dealId: string; relationshipId: string; stage: OpenDealStage };

	let {
		action,
		businessName,
		current,
		onDone,
		onClose
	}: {
		action: Action;
		businessName: string;
		/** The business's next step now, if it has one. */
		current: { text: string; due_on: string } | null;
		/** After the save is confirmed and the caches refreshed. */
		onDone?: () => void;
		onClose: () => void;
	} = $props();

	const queryClient = useQueryClient();
	const toast = getToastManager();

	let startStage = $state<DealStartStage>('interested');
	const stage = $derived<OpenDealStage>(action.kind === 'start' ? startStage : action.stage);
	// Moving into a stage with its own date asks for a fresh step; otherwise the current step is kept unless
	// Jafar changes it. Starting and reopening always give one.
	const needsNewStep = $derived(
		action.kind !== 'move' || STAGES_NEEDING_DATE.includes(stage) || current === null
	);

	function prefill(forStage: OpenDealStage) {
		if (!needsNewStep && current) return { text: current.text, due_on: current.due_on };
		return suggestedNextStep(forStage, businessName);
	}

	const first = untrack(() => prefill(stage));
	let text = $state(first.text);
	let dueOn = $state<CalendarDate | undefined>(calendarDateFromString(first.due_on));
	let fieldErrors = $state<Record<string, string>>({});
	let formError = $state('');
	let saving = $state(false);

	function chooseStartStage(next: DealStartStage) {
		startStage = next;
		const suggestion = suggestedNextStep(next, businessName);
		text = suggestion.text;
		dueOn = calendarDateFromString(suggestion.due_on);
	}

	const todayDate = today(getLocalTimeZone());
	const quickDates = [
		{ label: 'Today', days: 0 },
		{ label: 'Tomorrow', days: 1 },
		{ label: 'In 3 days', days: 3 },
		{ label: 'Next week', days: 7 }
	];

	const title = $derived(
		action.kind === 'start'
			? 'Start a Deal'
			: action.kind === 'reopen'
				? 'Reopen this Deal'
				: `Move to ${DEAL_STAGE_LABELS[stage]}`
	);
	const textLabel = $derived(
		stage === 'call_booked' ? 'The call' : stage === 'later' ? 'When you come back' : 'Next step'
	);
	const dateLabel = $derived(
		stage === 'call_booked' ? 'Call date' : stage === 'later' ? 'Revisit on' : 'Due'
	);

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (saving) return;
		formError = '';
		const errors: Record<string, string> = {};
		if (!text.trim()) errors['next_action.text'] = 'Say what the next step is.';
		if (!dueOn) errors['next_action.due_on'] = 'Choose the date.';
		fieldErrors = errors;
		if (Object.keys(errors).length) return;

		const step = { text: text.trim(), due_on: dueOn!.toString() };
		const unchanged = current && step.text === current.text && step.due_on === current.due_on;
		saving = true;
		const result =
			action.kind === 'start'
				? await sendLeadWrite('/api/jafar/deals', 'POST', {
						relationship_id: action.relationshipId,
						stage,
						next_action: step
					})
				: action.kind === 'reopen'
					? await sendLeadWrite(
							`/api/jafar/deals/${encodeURIComponent(action.dealId)}/reopen`,
							'POST',
							{ next_action: step }
						)
					: await sendLeadWrite(`/api/jafar/deals/${encodeURIComponent(action.dealId)}`, 'PATCH', {
							stage,
							...(needsNewStep || !unchanged ? { next_action: step } : {})
						});
		saving = false;
		if (!result.ok) {
			fieldErrors = result.fieldErrors;
			formError = result.error;
			return;
		}
		await refreshDeals(queryClient, action.relationshipId);
		toast.success(
			action.kind === 'start'
				? 'Deal started'
				: action.kind === 'reopen'
					? 'Deal reopened'
					: `Moved to ${DEAL_STAGE_LABELS[stage]}`
		);
		onDone?.();
		onClose();
	}
</script>

<Dialog open={true} {title} size="small" initialFocusId="deal-step-text" {onClose}>
	<form class="deal-step" onsubmit={submit} novalidate>
		{#if action.kind === 'start'}
			<RadioGroup
				label="Where does it start?"
				variant="cards"
				options={DEAL_START_STAGES.map((option) => ({
					value: option,
					label:
						option === 'interested'
							? 'Interested — they want to know more'
							: 'Call booked — they agreed to a call'
				}))}
				value={startStage}
				onchange={(value) => chooseStartStage(value as DealStartStage)}
			/>
		{:else if action.kind === 'reopen'}
			<p class="deal-step__lead">
				It goes back to <strong>{DEAL_STAGE_LABELS[stage]}</strong>, where it was lost from.
			</p>
		{:else if !needsNewStep}
			<p class="deal-step__lead">The next step stays the same unless you change it.</p>
		{/if}

		<Input
			id="deal-step-text"
			label={textLabel}
			maxlength={200}
			required
			autocomplete="off"
			invalid={Boolean(fieldErrors['next_action.text'])}
			errorMessage={fieldErrors['next_action.text'] ?? ''}
			bind:value={text}
		/>

		<div class="deal-step__due">
			<CalendarPicker
				id="deal-step-due"
				label={dateLabel}
				required
				minValue={todayDate}
				invalid={Boolean(fieldErrors['next_action.due_on'])}
				errorMessage={fieldErrors['next_action.due_on'] ?? ''}
				bind:value={dueOn}
			/>
			<div class="deal-step__quick" role="group" aria-label="Quick dates">
				{#each quickDates as quick (quick.days)}
					<button
						type="button"
						class="deal-step__chip"
						onclick={() => (dueOn = todayDate.add({ days: quick.days }))}>{quick.label}</button
					>
				{/each}
			</div>
		</div>

		{#if formError && !fieldErrors['next_action.text'] && !fieldErrors['next_action.due_on']}
			<p class="deal-step__error" role="alert">{formError}</p>
		{/if}

		<div class="deal-step__actions">
			<Button variant="tertiary" onclick={onClose} disabled={saving}>Cancel</Button>
			<Button type="submit" variant="primary" loading={saving}>
				{action.kind === 'start' ? 'Start Deal' : action.kind === 'reopen' ? 'Reopen' : 'Move'}
			</Button>
		</div>
	</form>
</Dialog>

<style lang="scss">
	.deal-step {
		display: grid;
		gap: var(--space-base);
	}

	.deal-step__lead {
		margin: 0;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
	}

	.deal-step__lead strong {
		color: var(--color-text);
	}

	.deal-step__due {
		display: grid;
		gap: var(--space-small);
	}

	.deal-step__quick {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-small);
	}

	.deal-step__chip {
		padding: var(--space-smallest) var(--space-slim);
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-circle);
		color: var(--color-text);
		background: var(--color-surface);
		font: inherit;
		font-size: var(--typography--fontSize-small);
		cursor: pointer;

		&:hover {
			border-color: var(--color-border--interactive);
			background: var(--color-surface--hover);
		}

		&:focus-visible {
			outline: none;
			box-shadow: var(--shadow-focus);
		}
	}

	.deal-step__error {
		margin: 0;
		color: var(--color-critical--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.deal-step__actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-small);
	}
</style>
