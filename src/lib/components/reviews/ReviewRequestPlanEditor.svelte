<script lang="ts">
	import { slide } from 'svelte/transition';
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import ReviewMessageSetEditor from './ReviewMessageSetEditor.svelte';
	import {
		DEFAULT_REVIEW_REMINDER_MESSAGES,
		REVIEW_FIRST_SEND_DELAY_MAX,
		REVIEW_REMINDERS_MAX,
		REVIEW_REMINDER_WAIT_MAX_DAYS,
		REVIEW_REMINDER_WAIT_MIN_DAYS,
		newReviewReminder,
		reviewPlanWarnings,
		type ReviewFirstSendUnit,
		type ReviewRequestPlan
	} from '$lib/reviews/settings';
	import timelineIcon from '@tabler/icons/outline/calendar-repeat.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import bellIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
	import plusIcon from '@tabler/icons/outline/plus.svg?raw';
	import trashIcon from '@tabler/icons/outline/trash.svg?raw';
	import pencilIcon from '@tabler/icons/outline/pencil.svg?raw';
	import warningIcon from '@tabler/icons/outline/alert-triangle.svg?raw';

	// Google review campaign Part 4A: "Request behavior", following HighLevel's Reputation settings. When the
	// first message goes, and the reminders that follow it, shown as a readable timeline. Every request
	// follows it; a customer who continues to Google or leaves private feedback gets no more reminders.
	let {
		plan = $bindable(),
		disabled = false,
		fieldErrors = {}
	}: {
		plan: ReviewRequestPlan;
		disabled?: boolean;
		fieldErrors?: Record<string, string>;
	} = $props();

	// One reminder's wording is open at a time.
	let openReminderId = $state<string | null>(null);

	const timingOptions = [
		{ value: 'now', label: 'Right away' },
		{ value: 'delay', label: 'After a delay' }
	];
	const unitOptions = [
		{ value: 'hours', label: 'Hours' },
		{ value: 'days', label: 'Days' }
	];

	const warnings = $derived(reviewPlanWarnings(plan));

	// "Day 3", "Day 5": each reminder's day counted from the first message.
	const reminderDays = $derived(
		plan.reminders.reduce<number[]>((days, reminder, index) => {
			days.push((index === 0 ? 0 : days[index - 1]) + (Number(reminder.wait_days) || 0));
			return days;
		}, [])
	);

	const firstSendLabel = $derived.by(() => {
		const { amount, unit } = plan.first_send_delay;
		if (amount === 0) return 'Right away';
		if (!amount) return 'Choose a delay';
		return `${amount} ${amount === 1 ? unit.slice(0, -1) : unit} later`;
	});

	function setTiming(value: string) {
		plan.first_send_delay =
			value === 'now' ? { amount: 0, unit: 'hours' } : { amount: 2, unit: 'hours' };
	}

	function addReminder() {
		const reminder = newReviewReminder(crypto.randomUUID(), 3);
		plan.reminders.push(reminder);
		openReminderId = reminder.id;
	}

	function removeReminder(index: number) {
		const [removed] = plan.reminders.splice(index, 1);
		if (removed?.id === openReminderId) openReminderId = null;
	}

	function reminderError(index: number) {
		const prefix = `request_plan.reminders.${index}`;
		return Object.entries(fieldErrors).find(([path]) => path.startsWith(prefix))?.[1] ?? '';
	}

	function waitError(index: number) {
		return fieldErrors[`request_plan.reminders.${index}.wait_days`] ?? '';
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SectionBlock
	title="Request behavior"
	hint="When the first message goes and the reminders that follow. Every review request uses this plan."
	icon={timelineIcon}
	form
	level={3}
>
	<div class="request-plan">
		<ol class="request-plan__timeline">
			<li class="request-plan__step">
				<span class="request-plan__marker request-plan__marker--first" aria-hidden="true"
					>{@html sendIcon}</span
				>
				<div class="request-plan__body">
					<div class="request-plan__head">
						<p class="request-plan__title">First message</p>
						<span class="request-plan__when">{firstSendLabel}</span>
					</div>
					<div class="request-plan__controls">
						<Select
							id="review-first-send-timing"
							label="Send the first message"
							options={timingOptions}
							value={plan.first_send_delay.amount === 0 ? 'now' : 'delay'}
							{disabled}
							onchange={setTiming}
						/>
						<!-- Only an exact 0 means "right away", so emptying the field keeps it on screen. -->
						{#if plan.first_send_delay.amount !== 0}
							<div class="request-plan__delay">
								<Input
									id="review-first-send-amount"
									label="Wait"
									type="number"
									min={1}
									max={REVIEW_FIRST_SEND_DELAY_MAX[plan.first_send_delay.unit]}
									bind:value={plan.first_send_delay.amount}
									invalid={Boolean(fieldErrors['request_plan.first_send_delay.amount'])}
									errorMessage={fieldErrors['request_plan.first_send_delay.amount']}
									{disabled}
								/>
								<Select
									id="review-first-send-unit"
									label="Unit"
									options={unitOptions}
									value={plan.first_send_delay.unit}
									{disabled}
									onchange={(value) => (plan.first_send_delay.unit = value as ReviewFirstSendUnit)}
								/>
							</div>
						{/if}
					</div>
					<p class="request-plan__note">
						Uses the wording in Request messages below. This timing applies to automatic requests.
						When you send one yourself, you choose Send now or Schedule.
					</p>
				</div>
			</li>

			{#each plan.reminders as reminder, index (reminder.id)}
				{@const open = openReminderId === reminder.id}
				{@const error = reminderError(index)}
				<li class="request-plan__step" transition:slide={{ duration: 150 }}>
					<span class="request-plan__marker" aria-hidden="true">{@html bellIcon}</span>
					<div class="request-plan__body">
						<div class="request-plan__head">
							<p class="request-plan__title">Reminder {index + 1}</p>
							<span class="request-plan__when">Day {reminderDays[index]}</span>
							{#if error && !open}
								<span class="request-plan__flag">Needs attention</span>
							{/if}
						</div>
						<div class="request-plan__controls">
							<div class="request-plan__wait">
								<Input
									id={`review-reminder-wait-${reminder.id}`}
									label="Days after the previous message"
									type="number"
									min={REVIEW_REMINDER_WAIT_MIN_DAYS}
									max={REVIEW_REMINDER_WAIT_MAX_DAYS}
									bind:value={reminder.wait_days}
									invalid={waitError(index) !== ''}
									errorMessage={waitError(index)}
									{disabled}
								/>
							</div>
							<div class="request-plan__actions">
								<Button
									variant="tertiary"
									size="small"
									onclick={() => (openReminderId = open ? null : reminder.id)}
								>
									<span class="request-plan__button-icon" aria-hidden="true"
										>{@html pencilIcon}</span
									>
									{open ? 'Close wording' : 'Edit wording'}
								</Button>
								<Button
									variant="tertiary"
									size="small"
									{disabled}
									onclick={() => removeReminder(index)}
								>
									<span class="request-plan__button-icon" aria-hidden="true">{@html trashIcon}</span
									>
									Remove
								</Button>
							</div>
						</div>
						{#if open}
							<div
								class="request-plan__copy"
								id={`review-reminder-copy-${reminder.id}`}
								transition:slide={{ duration: 150 }}
							>
								<ReviewMessageSetEditor
									bind:messages={reminder.messages}
									defaults={DEFAULT_REVIEW_REMINDER_MESSAGES}
									idPrefix={`review-reminder-${reminder.id}`}
									errorPrefix={`request_plan.reminders.${index}.messages`}
									subjectPlaceholder="e.g. A quick reminder from {'{{business_name}}'}"
									{disabled}
									{fieldErrors}
								/>
							</div>
						{/if}
					</div>
				</li>
			{/each}
		</ol>

		{#if plan.reminders.length === 0}
			<p class="request-plan__note">No reminders. Customers get the first message only.</p>
		{/if}

		<div class="request-plan__add">
			<Button
				variant="secondary"
				size="small"
				disabled={disabled || plan.reminders.length >= REVIEW_REMINDERS_MAX}
				onclick={addReminder}
			>
				<span class="request-plan__button-icon" aria-hidden="true">{@html plusIcon}</span>
				Add a reminder
			</Button>
			<p class="request-plan__note">
				Reminders stop as soon as the customer goes to Google or leaves private feedback, or if a
				message cannot be delivered.
				{#if plan.reminders.length >= REVIEW_REMINDERS_MAX}
					You have reached the limit of {REVIEW_REMINDERS_MAX} reminders.
				{/if}
			</p>
		</div>

		{#each warnings as warning (warning)}
			<div class="request-plan__banner" role="status">
				<span class="request-plan__banner-icon" aria-hidden="true">{@html warningIcon}</span>
				<p>{warning}</p>
			</div>
		{/each}
	</div>
</SectionBlock>

<style lang="scss">
	.request-plan {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__timeline {
			display: flex;
			flex-direction: column;
			margin: 0;
			padding: 0;
			list-style: none;
		}

		&__step {
			position: relative;
			display: flex;
			gap: var(--space-base);
			padding-bottom: var(--space-large);

			// The line joining one step's marker to the next.
			&:not(:last-child)::before {
				content: '';
				position: absolute;
				top: 36px;
				bottom: 4px;
				left: 15px;
				width: 2px;
				border-radius: var(--radius-base);
				background: var(--color-border);
			}

			&:last-child {
				padding-bottom: 0;
			}
		}

		&__marker {
			display: inline-grid;
			flex: 0 0 auto;
			place-items: center;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-circle);
			color: var(--color-informative--onSurface);
			background: var(--color-informative--surface);

			&--first {
				color: var(--color-surface);
				background: var(--color-interactive);
			}

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__body {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: var(--space-small);
			min-width: 0;
			padding-top: var(--space-smaller);
		}

		&__head {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-small);
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-weight: 600;
		}

		&__when {
			padding: var(--space-smallest) var(--space-small);
			border-radius: var(--radius-base);
			color: var(--color-text--secondary);
			background: var(--color-surface--background);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__flag {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__controls {
			display: flex;
			flex-wrap: wrap;
			align-items: flex-start;
			gap: var(--space-base);

			> :global(:first-child) {
				min-width: 200px;
			}
		}

		&__delay {
			display: flex;
			gap: var(--space-small);

			> :global(*) {
				width: 120px;
			}
		}

		&__wait {
			width: 240px;
			max-width: 100%;
		}

		&__actions {
			display: flex;
			flex-wrap: wrap;
			align-items: center;
			gap: var(--space-smaller);
			min-height: 40px;
		}

		&__copy {
			padding: var(--space-base);
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-base);
		}

		&__add {
			display: flex;
			flex-direction: column;
			align-items: flex-start;
			gap: var(--space-small);
		}

		&__note {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__button-icon {
			display: inline-grid;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}

		&__banner {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);

			p {
				margin: 0;
			}
		}

		&__banner-icon {
			display: inline-grid;
			flex: 0 0 auto;
			padding: var(--space-smaller);
			border-radius: var(--radius-circle);
			color: var(--color-surface);
			background: var(--color-warning);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
