<script lang="ts">
	import bellRingingIcon from '@tabler/icons/outline/bell-ringing.svg?raw';
	import fileTextIcon from '@tabler/icons/outline/file-text.svg?raw';
	import hammerIcon from '@tabler/icons/outline/hammer.svg?raw';
	import starIcon from '@tabler/icons/outline/star.svg?raw';
	import pauseIcon from '@tabler/icons/outline/player-pause.svg?raw';
	import moonIcon from '@tabler/icons/outline/moon.svg?raw';
	import noMarketingIcon from '@tabler/icons/outline/ad-off.svg?raw';
	import shieldCheckIcon from '@tabler/icons/outline/shield-check.svg?raw';
	import Dialog from '$lib/components/ui/Dialog.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import Checkbox from '$lib/components/ui/Checkbox.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
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

	// Each group wears the colour of the record its messages are about (design `modals.md`).
	const groups: {
		title: string;
		icon: string;
		tone: string;
		items: { key: PreferenceFlag; label: string; description: string }[];
	}[] = [
		{
			title: 'Quotes & invoices',
			icon: fileTextIcon,
			tone: 'quote',
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
			icon: hammerIcon,
			tone: 'job',
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
			icon: starIcon,
			tone: 'review',
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

<!-- eslint-disable svelte/no-at-html-tags -->
<Dialog
	{open}
	title="Communication settings"
	subtitle="Automatic messages this client gets"
	icon={bellRingingIcon}
	iconTone="conversation"
	size="large"
	{onClose}
>
	<div class="communication-settings">
		{#if allPaused}
			<Banner type="warning" icon={moonIcon}>
				This client is set to <strong>Do not disturb</strong>, so none of these are sent. Your choices
				are still saved and come back the moment you switch to Allow.
			</Banner>
		{:else if marketingPaused}
			<Banner type="notice" icon={noMarketingIcon}>
				This client is set to <strong>No marketing</strong>, so marketing messages are held back. The
				rest still go out as normal.
			</Banner>
		{/if}

		<div class="communication-settings__groups">
			{#each groups as group (group.title)}
				<section
					class="communication-settings__group"
					class:communication-settings__group--paused={allPaused}
				>
					<div class="communication-settings__group-head">
						<IconTile icon={group.icon} tone={group.tone} size={32} />
						<h3 class="communication-settings__group-title">{group.title}</h3>
					</div>
					<div class="communication-settings__items">
						{#each group.items as item (item.key)}
							<div class="communication-settings__item">
								<Checkbox
									id={`client-pref-${item.key}`}
									label={item.label}
									description={item.description}
									bind:checked={preferences[item.key]}
								/>
								{#if notSending(item.key)}
									<p class="communication-settings__not-sending">
										<span class="communication-settings__not-sending-icon" aria-hidden="true"
											>{@html pauseIcon}</span
										>
										<span
											>Not sending · {#if statusQuery.data?.can_manage}<a
													class="communication-settings__link"
													href={automationsHref}>turn it on in Automations</a
												>{:else}your business has this automation turned off{/if}</span
										>
									</p>
								{/if}
							</div>
						{/each}
					</div>
				</section>
			{/each}
		</div>

		<p class="communication-settings__hint">
			<span class="communication-settings__hint-icon" aria-hidden="true">{@html shieldCheckIcon}</span>
			<span>
				Marketing email consent is kept as a dated record on the <strong>Marketing email</strong> card,
				not as a tick here, so you always know who agreed, when, and how.
			</span>
		</p>
	</div>

	{#snippet footer()}
		<Button variant="primary" onclick={onClose}>Done</Button>
	{/snippet}
</Dialog>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	.communication-settings {
		// The pop-up body's own padding is 20 all round; this list starts closer to the header (4 20 20).
		margin-top: calc(var(--space-smaller) - var(--space-medium));

		> :global(.banner) {
			margin-top: var(--space-base);
		}

		&__group {
			display: grid;
			grid-template-columns: 240px minmax(0, 1fr);
			gap: var(--space-base);
			padding: 18px 0;

			& + & {
				border-top: var(--border-base) solid var(--color-border);
			}

			&--paused {
				opacity: 0.5;
			}
		}

		&__group-head {
			display: flex;
			align-items: center;
			align-self: start;
			gap: var(--space-slim);
		}

		&__group-title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 700;
		}

		&__items {
			display: grid;
			gap: var(--space-base);
		}

		&__item {
			display: grid;
			justify-items: start;
		}

		// Lines up under the tick's label: the 18 box and its 10 gap.
		&__not-sending {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			margin: var(--space-small) 0 0 28px;
			padding: 6px 10px;
			border-radius: var(--radius-base);
			color: var(--color-warning--onSurface);
			background: var(--color-warning--surface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__not-sending-icon {
			display: inline-grid;
			color: var(--color-warning);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__link {
			color: var(--color-interactive);
			font-weight: 600;
			text-decoration: underline;
		}

		&__hint {
			display: flex;
			align-items: flex-start;
			gap: var(--space-small);
			padding: var(--space-slim) 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-tile-large);
			color: var(--color-text--secondary);
			background: var(--color-surface--background--subtle);
			font-size: var(--typography--fontSize-small);
		}

		&__hint-icon {
			display: inline-grid;
			flex: 0 0 auto;
			color: var(--color-growth);

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}
</style>
