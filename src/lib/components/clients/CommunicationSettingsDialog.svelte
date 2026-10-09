<script lang="ts">
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import { createQuery } from '@tanstack/svelte-query';
	import { resolve } from '$app/paths';
	import {
		fetchMessageAutomationStatus,
		messageAutomationStatusKey,
		MESSAGE_SWITCH_TRIGGERS,
		type ClientPreferences,
		type MessageSwitch
	} from '$lib/clients/api';

	type PreferenceFlag = Exclude<keyof ClientPreferences, 'contact_policy'>;

	let {
		open,
		preferences = $bindable(),
		onClose
	}: {
		open: boolean;
		preferences: ClientPreferences;
		onClose: () => void;
	} = $props();

	// "Do not disturb" pauses everything and "No marketing" pauses the marketing message, but neither one
	// wipes the choices underneath — switch back to Allow and the client's settings are exactly as saved.
	const allPaused = $derived(preferences.contact_policy === 'do_not_disturb');
	const marketingPaused = $derived(allPaused || preferences.contact_policy === 'no_marketing');

	// Client reminders Part 3: a switch only sends while its business-wide automation is on, so say so plainly
	// when it is off rather than let the tick promise a message that never goes out.
	const statusQuery = createQuery(() => ({
		queryKey: messageAutomationStatusKey,
		queryFn: fetchMessageAutomationStatus,
		enabled: open,
		staleTime: 30_000
	}));
	const automationsHref = resolve('/(app)/settings/automation');

	function notSending(key: PreferenceFlag): boolean {
		const status = statusQuery.data;
		if (!status || !(key in MESSAGE_SWITCH_TRIGGERS)) return false;
		return !status.sending[key as MessageSwitch];
	}

	const groups: {
		title: string;
		items: { key: PreferenceFlag; label: string; description: string }[];
	}[] = [
		{
			title: 'Quotes & invoices',
			items: [
				{
					key: 'quote_follow_ups',
					label: 'Outstanding quote follow-ups',
					description: 'A nudge when a quote has been sitting unanswered.'
				},
				{
					key: 'invoice_reminders',
					label: 'Overdue invoice reminders',
					description: 'A reminder once an invoice passes its due date.'
				}
			]
		},
		{
			title: 'Jobs & visits',
			items: [
				{
					key: 'appointment_reminders',
					label: 'Upcoming assessment and visit reminders',
					description: 'A heads-up before someone is due on site.'
				},
				{
					key: 'job_follow_ups',
					label: 'Job completion follow-ups',
					description: 'A check-in after the work is finished.'
				}
			]
		},
		{
			title: 'Growth',
			items: [
				{
					key: 'review_requests',
					label: 'Review requests',
					description: 'An ask for a review after a job goes well.'
				}
			]
		}
	];
</script>

<Dialog {open} title="Communication settings" size="large" {onClose}>
	{#if allPaused}
		<p class="communication-settings__notice">
			This client is set to <strong>Do not disturb</strong>, so none of these are sent. Your choices
			are still saved and come back the moment you switch to Allow.
		</p>
	{:else if marketingPaused}
		<p class="communication-settings__notice">
			This client is set to <strong>No marketing</strong>, so marketing messages are held back. The
			rest still go out as normal.
		</p>
	{/if}

	{#each groups as group (group.title)}
		<section class="communication-settings__group">
			<h3 class="communication-settings__group-title">{group.title}</h3>
			{#each group.items as item (item.key)}
				<div
					class="communication-settings__item"
					class:communication-settings__item--paused={allPaused}
				>
					<Checkbox
						id={`client-pref-${item.key}`}
						label={item.label}
						description={item.description}
						bind:checked={preferences[item.key]}
					/>
					{#if notSending(item.key)}
						<p class="communication-settings__not-sending">
							Not sending — {#if statusQuery.data?.can_manage}<a
									class="communication-settings__link"
									href={automationsHref}>turn it on in Automations</a
								>{:else}your business has this automation turned off{/if}.
						</p>
					{/if}
				</div>
			{/each}
		</section>
	{/each}

	<p class="communication-settings__hint">
		Marketing email consent is kept as a dated record on the <strong>Marketing email</strong> card, not
		as a tick here — so you always know who agreed, when, and how.
	</p>

	<footer class="communication-settings__footer">
		<Button variant="primary" onclick={onClose}>Done</Button>
	</footer>
</Dialog>

<style lang="scss">
	.communication-settings {
		&__notice {
			margin-bottom: var(--space-base);
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			color: var(--color-text);
			background: var(--color-surface--active);
			font-size: var(--typography--fontSize-small);
		}

		&__group {
			display: flex;
			flex-direction: column;
			gap: var(--space-slim);

			& + & {
				margin-top: var(--space-large);
			}
		}

		&__group-title {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 700;
			letter-spacing: 0.04em;
			text-transform: uppercase;
		}

		&__not-sending {
			margin: var(--space-smallest) 0 0 calc(var(--space-large) + var(--space-small));
			color: var(--color-warning--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__link {
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: underline;
		}

		&__item--paused {
			opacity: 0.55;
		}

		&__hint {
			margin-top: var(--space-large);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__footer {
			display: flex;
			justify-content: flex-end;
			margin-top: var(--space-large);
		}
	}
</style>
