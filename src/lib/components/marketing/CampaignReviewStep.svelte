<script lang="ts">
	import { page } from '$app/state';
	import { createQuery } from '@tanstack/svelte-query';
	import Button from '$lib/components/ui/Button.svelte';
	import Banner from '$lib/components/ui/Banner.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import IconTile from '$lib/components/ui/IconTile.svelte';
	import {
		calendarDateToString,
		emptyDateTimePickerValue,
		timeToString,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import SetupStepCard from '$lib/components/layout/SetupStepCard.svelte';
	import CampaignAudience from './CampaignAudience.svelte';
	import CampaignEmailPreview from './CampaignEmailPreview.svelte';
	import {
		MARKETING_FORM_CTA_LABELS,
		MARKETING_PHONE_CTA_LABEL,
		MARKETING_WEBSITE_CTA_LABEL,
		marketingGoalLabels,
		type MarketingCampaignContent,
		type MarketingGoal
	} from '$lib/marketing/campaign-content';
	import {
		marketingGroupPreviewKey,
		type MarketingCustomerGroup
	} from '$lib/marketing/customer-groups';
	import { groupRuleChips } from '$lib/marketing/group-rule-chips';
	import {
		fetchGroupPreviewCounts,
		fetchRuleLabels,
		sendTestEmailRequest,
		type MarketingDeliveryOptions
	} from '$lib/marketing/api';
	import type { FormOutcome } from '$lib/forms/types';
	import { zonedTimeToUtc } from '$lib/time/calendar-day';
	import listCheckIcon from '@tabler/icons/outline/list-check.svg?raw';
	import targetIcon from '@tabler/icons/outline/target.svg?raw';
	import usersIcon from '@tabler/icons/outline/users.svg?raw';
	import mailIcon from '@tabler/icons/outline/mail.svg?raw';
	import mailXIcon from '@tabler/icons/outline/mail-x.svg?raw';
	import clickIcon from '@tabler/icons/outline/click.svg?raw';
	import gaugeIcon from '@tabler/icons/outline/gauge.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';
	import calendarClockIcon from '@tabler/icons/outline/calendar-clock.svg?raw';
	import calendarCheckIcon from '@tabler/icons/outline/calendar-check.svg?raw';
	import globeIcon from '@tabler/icons/outline/globe.svg?raw';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import mailSearchIcon from '@tabler/icons/outline/mail-search.svg?raw';
	import mailCheckIcon from '@tabler/icons/outline/mail-check.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';

	// Step 5 (blueprint §8 step 5), design skill `layout.md` → New campaign · Review step: a final, read-only
	// summary before send. Nothing here is editable -- every field was chosen on an earlier step; "Back" is how a
	// contractor changes any of it. The email sits on the left, the launch panel on the right. Only the owner or
	// an administrator ever sees a working Send/Schedule control (blueprint §14); everyone else is shown why not.
	let {
		content,
		campaignId,
		name,
		goal,
		customerGroupId,
		groups,
		options,
		isPending,
		isError,
		onRetry,
		onBack,
		onSend
	}: {
		content: MarketingCampaignContent;
		campaignId: string | null;
		name: string;
		goal: MarketingGoal | null;
		customerGroupId: string | null;
		groups: MarketingCustomerGroup[];
		options: MarketingDeliveryOptions;
		isPending: boolean;
		isError: boolean;
		onRetry: () => void;
		onBack: () => void;
		onSend: (sendAt: string | null) => Promise<void>;
	} = $props();

	const selectedGroup = $derived(groups.find((group) => group.id === customerGroupId) ?? null);

	// The Customers step's count query; its cache is warm by now. It gives the meter and the button's number.
	const countsQuery = createQuery(() => ({
		queryKey: marketingGroupPreviewKey(selectedGroup?.rules ?? { version: '1' }),
		queryFn: () => fetchGroupPreviewCounts(selectedGroup!.rules),
		enabled: selectedGroup !== null,
		staleTime: 10_000
	}));
	const counts = $derived(countsQuery.data);

	// The group's rules in words, named the way the Customers step names them.
	const serviceIds = $derived(selectedGroup?.rules.services ?? []);
	const labelsQuery = createQuery(() => ({
		queryKey: ['marketing', 'rule-labels', serviceIds],
		queryFn: () => fetchRuleLabels(serviceIds, []),
		enabled: serviceIds.length > 0,
		staleTime: 60_000
	}));
	const rulesLine = $derived(
		selectedGroup
			? groupRuleChips(
					selectedGroup.rules,
					Object.fromEntries(
						(labelsQuery.data?.catalog_items ?? []).map((item) => [item.id, item.label])
					)
				)
					.map((chip) => chip.text)
					.join(' · ') || 'Every active customer'
			: ''
	);

	const chosenFormId = $derived(content.cta?.type === 'internal_form' ? content.cta.form_id : '');
	const chosenForm = $derived(
		chosenFormId ? (options.forms.find((form) => form.id === chosenFormId) ?? null) : null
	);
	const formNoLongerAvailable = $derived(content.cta?.type === 'internal_form' && !chosenForm);

	function websiteHref(website: string) {
		return /^https?:\/\//i.test(website) ? website : `https://${website}`;
	}
	function websiteHost(website: string) {
		return website.replace(/^https?:\/\//i, '').replace(/\/$/, '');
	}

	// The button row: the words on the email's button and where it opens, as the Delivery step shows them.
	const button = $derived.by(() => {
		const cta = content.cta;
		if (!cta) return null;
		if (cta.type === 'internal_form') {
			if (!chosenForm) return null;
			const outcome = (
				chosenForm.outcome in MARKETING_FORM_CTA_LABELS ? chosenForm.outcome : 'request'
			) as FormOutcome;
			return {
				words: MARKETING_FORM_CTA_LABELS[outcome],
				opens: chosenForm.name,
				href: `/forms/${options.organization_slug}/${chosenForm.public_slug}`
			};
		}
		if (cta.type === 'website' && options.business_website)
			return {
				words: MARKETING_WEBSITE_CTA_LABEL,
				opens: websiteHost(options.business_website),
				href: websiteHref(options.business_website)
			};
		if (cta.type === 'phone' && options.business_phone)
			return { words: MARKETING_PHONE_CTA_LABEL, opens: options.business_phone, href: null };
		return null;
	});

	const buttonProblem = $derived(
		!content.cta
			? 'No button chosen. Go back to Delivery to choose one.'
			: formNoLongerAvailable
				? 'This form is no longer available. Go back and choose another.'
				: !button
					? 'The button has nowhere to lead. Go back to Delivery to fix it.'
					: ''
	);

	const plan = $derived.by(() => {
		const { allowance } = options;
		if (allowance.is_unlimited)
			return { value: 'Unlimited marketing email', line: 'from your package' };
		if (allowance.state === 'numeric' && allowance.value !== null)
			return {
				value: `${allowance.value.toLocaleString()} marketing ${allowance.value === 1 ? 'email' : 'emails'}`,
				line: 'per period, from your package'
			};
		return { value: 'Not in your plan yet', line: 'your package has no marketing email' };
	});

	// Only the owner or an administrator may launch a campaign (blueprint §14) -- a Marketing-enabled staff
	// member can build and review a draft but the app never offers them a button that would send it.
	const canSend = $derived(
		page.data.organization?.role === 'owner' || page.data.organization?.role === 'admin'
	);

	let sendMode = $state<'now' | 'schedule'>('now');
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let sending = $state(false);
	let sendError = $state('');

	let testSending = $state(false);
	let testMessage = $state('');
	let testError = $state('');

	async function sendTest() {
		if (testSending) return;
		testSending = true;
		testMessage = '';
		testError = '';
		try {
			await sendTestEmailRequest(content, campaignId);
			testMessage = 'A test email is on its way to your own inbox.';
		} catch (cause) {
			testError = cause instanceof Error ? cause.message : 'That test email could not be sent.';
		} finally {
			testSending = false;
		}
	}

	// "Tue, Oct 28 at 9:00 AM", in the business's own time zone, once a day and time are picked.
	const scheduledText = $derived.by(() => {
		const day = calendarDateToString(when.date);
		const time = timeToString(when.startTime);
		if (!day || !time) return null;
		const at = zonedTimeToUtc(day, time, options.timezone);
		if (!at) return null;
		const zone = { timeZone: options.timezone };
		const dayText = new Intl.DateTimeFormat('en-US', {
			...zone,
			weekday: 'short',
			month: 'short',
			day: 'numeric'
		}).format(at);
		const timeText = new Intl.DateTimeFormat('en-US', {
			...zone,
			hour: 'numeric',
			minute: '2-digit'
		}).format(at);
		return `${dayText} at ${timeText}`;
	});

	const sendLabel = $derived(
		sendMode === 'schedule'
			? scheduledText
				? `Schedule for ${scheduledText}`
				: 'Schedule campaign'
			: counts
				? `Send to ${counts.eligible.toLocaleString()} ${counts.eligible === 1 ? 'customer' : 'customers'}`
				: 'Send now'
	);

	async function handleSend() {
		if (sending) return;
		sendError = '';

		let sendAt: string | null = null;
		if (sendMode === 'schedule') {
			const day = calendarDateToString(when.date);
			const time = timeToString(when.startTime);
			if (!day || !time) {
				sendError = 'Pick a day and time to schedule this campaign for.';
				return;
			}
			const parsed = zonedTimeToUtc(day, time, options.timezone);
			if (!parsed) {
				sendError = 'That date and time could not be read. Try picking them again.';
				return;
			}
			if (parsed.getTime() <= Date.now()) {
				sendError = 'Pick a time in the future.';
				return;
			}
			sendAt = parsed.toISOString();
		}

		sending = true;
		try {
			await onSend(sendAt);
		} catch (cause) {
			sendError = cause instanceof Error ? cause.message : 'That campaign could not be sent.';
		} finally {
			sending = false;
		}
	}

	const needsFix = $derived(!options.sender || Boolean(buttonProblem));
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<SetupStepCard
	title="Review before you send"
	hint="One last check. Use Back to change anything here."
	icon={listCheckIcon}
	tone="growth"
	flush
>
	{#if isError}
		<div class="review__problem">
			<ErrorState description="This campaign could not be loaded for review." retry={onRetry} />
		</div>
	{:else}
		<div class="review">
			<CampaignEmailPreview
				{content}
				title={name || 'Campaign'}
				shownWith="Shown with Alex's details"
			/>

			<aside class="review__panel" aria-label="Launch">
				{#if isPending}
					<div
						class="review-bones"
						role="status"
						aria-label="Loading your campaign for review"
						aria-busy="true"
					>
						<span class="skeleton review-bones__meter"></span>
						<span class="skeleton review-bones__title"></span>
						<div class="review-bones__list">
							{#each [0, 1, 2, 3, 4] as row (row)}
								<div class="review-bones__row">
									<span class="skeleton review-bones__tile"></span>
									<span class="review-bones__lines">
										<span class="skeleton review-bones__line review-bones__line--short"></span>
										<span class="skeleton review-bones__line"></span>
									</span>
								</div>
							{/each}
						</div>
					</div>
				{:else}
					{#if selectedGroup}
						<CampaignAudience
							rules={selectedGroup.rules}
							{counts}
							isPending={countsQuery.isPending}
							isError={countsQuery.isError}
							onRetry={() => countsQuery.refetch()}
							meterOnly
						/>
					{/if}

					<section class="review__section" aria-labelledby="review-facts-title">
						<h3 class="review__title" id="review-facts-title">
							Who, from whom, and where it leads
						</h3>
						<ul class="facts">
							<li class="fact">
								<IconTile icon={targetIcon} tone="growth" size={32} />
								<span class="fact__copy">
									<span class="fact__label">Goal</span>
									<span class="fact__value">{goal ? marketingGoalLabels[goal] : 'Not set'}</span>
								</span>
							</li>
							<li class="fact">
								<IconTile icon={usersIcon} tone="growth" size={32} />
								<span class="fact__copy">
									<span class="fact__label">Customer group</span>
									<span class="fact__value">{selectedGroup?.name ?? 'Not set'}</span>
									{#if selectedGroup}<span class="fact__line">{rulesLine}</span>{/if}
								</span>
							</li>
							{#if options.sender}
								<li class="fact">
									<IconTile icon={mailIcon} tone="conversation" size={32} />
									<span class="fact__copy">
										<span class="fact__label">From</span>
										<span class="fact__value"
											>{options.sender.display_name} &lt;{options.sender.email_address}&gt;</span
										>
										<span class="fact__line">Replies land in your Inbox.</span>
									</span>
								</li>
							{:else}
								<li class="fact fact--fix">
									<IconTile icon={mailXIcon} tone="warning" size={32} white />
									<span class="fact__copy">
										<span class="fact__label">From</span>
										<span class="fact__value">No verified sender yet</span>
									</span>
									<Button
										variant="secondary"
										size="small"
										href="/settings/communications"
										target="_blank"
									>
										Set up a sender
									</Button>
								</li>
							{/if}
							{#if button}
								<li class="fact">
									<IconTile icon={clickIcon} tone="informative" size={32} />
									<span class="fact__copy">
										<span class="fact__label">The button</span>
										<span class="fact__value">{button.words}</span>
										<span class="fact__line">Opens {button.opens}</span>
									</span>
									{#if button.href}
										<Button
											variant="secondary"
											iconOnly
											label="Open {button.opens}"
											href={button.href}
											target="_blank"
										>
											{@html externalLinkIcon}
										</Button>
									{/if}
								</li>
							{:else}
								<li class="fact fact--fix">
									<IconTile icon={clickIcon} tone="warning" size={32} white />
									<span class="fact__copy">
										<span class="fact__label">The button</span>
										<span class="fact__value">{buttonProblem}</span>
									</span>
									<span class="fact__alert" aria-hidden="true">{@html alertTriangleIcon}</span>
								</li>
							{/if}
							<li class="fact">
								<IconTile icon={gaugeIcon} tone="growth" size={32} />
								<span class="fact__copy">
									<span class="fact__label">Your plan</span>
									<span class="fact__value">{plan.value}</span>
									<span class="fact__line">{plan.line}</span>
								</span>
							</li>
						</ul>
					</section>

					{#if canSend}
						<section class="review__section" aria-labelledby="review-when-title">
							<h3 class="review__title" id="review-when-title">When should it send?</h3>
							<div class="when" role="radiogroup" aria-labelledby="review-when-title">
								<label class={['when__tile', sendMode === 'now' && 'when__tile--chosen']}>
									<input type="radio" name="campaign-send-mode" value="now" bind:group={sendMode} />
									<span class="when__radio" aria-hidden="true"></span>
									<IconTile
										icon={sendIcon}
										tone={sendMode === 'now' ? 'growth' : 'inactive'}
										size={32}
									/>
									<span class="when__copy">
										<span class="when__name">Send now</span>
										<span class="when__hint">Goes out as soon as you press send.</span>
									</span>
								</label>
								<div class={['when__tile', sendMode === 'schedule' && 'when__tile--chosen']}>
									<label class="when__top">
										<input
											type="radio"
											name="campaign-send-mode"
											value="schedule"
											bind:group={sendMode}
										/>
										<span class="when__radio" aria-hidden="true"></span>
										<IconTile
											icon={calendarClockIcon}
											tone={sendMode === 'schedule' ? 'growth' : 'inactive'}
											size={32}
										/>
										<span class="when__copy">
											<span class="when__name">Schedule for later</span>
											<span class="when__hint">Pick a day and time.</span>
										</span>
									</label>
									{#if sendMode === 'schedule'}
										<div class="when__pick">
											<DateTimePicker
												id="campaign-review-send-at"
												range={false}
												dateLabel="Day to send"
												timeLabel="Time"
												bind:value={when}
											/>
											<p class="when__zone">
												<span aria-hidden="true">{@html globeIcon}</span>
												{options.timezone}, your business time zone
											</p>
										</div>
									{/if}
								</div>
							</div>
						</section>
					{/if}

					<Banner type="notice" icon={alertTriangleIcon}>
						Sent email can't be recalled. Cancelling a campaign in progress only stops recipients
						who haven't been sent to yet.
					</Banner>

					{#if needsFix}
						<Banner type="warning">
							A part of this campaign needs a fix before it can send. Use Back to change it.
						</Banner>
					{/if}

					{#if canSend}
						{#if sendError}<Banner type="error">{sendError}</Banner>{/if}
						<div class="actions">
							<Button
								variant="primary"
								size="large"
								fullWidth
								loading={sending}
								disabled={isPending || isError}
								onclick={() => void handleSend()}
							>
								{@html sendMode === 'schedule' ? calendarCheckIcon : rocketIcon}
								{sendLabel}
							</Button>
							<Button
								variant="secondary"
								fullWidth
								loading={testSending}
								onclick={() => void sendTest()}
							>
								{@html mailSearchIcon}
								Send a test email to yourself
							</Button>
							{#if testMessage}
								<p class="test test--success" role="status">
									<span aria-hidden="true">{@html mailCheckIcon}</span>{testMessage}
								</p>
							{:else if testError}
								<p class="test test--error" role="alert">
									<span aria-hidden="true">{@html mailXIcon}</span>{testError}
								</p>
							{/if}
						</div>
					{:else}
						<div class="staff">
							<IconTile icon={lockIcon} tone="inactive" size={32} />
							<span class="staff__copy">
								<b>Ready for the owner to send</b>
								<span>
									Only the business owner or an administrator can send or schedule this campaign.
								</span>
							</span>
						</div>
					{/if}
				{/if}
			</aside>
		</div>
	{/if}

	{#snippet footer()}
		<Button variant="secondary" onclick={onBack}>
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<span class="foot-hint">Nothing sends until you press Send.</span>
	{/snippet}
</SetupStepCard>

<!-- eslint-enable svelte/no-at-html-tags -->

<style lang="scss">
	// The step's body: the email on the left, the launch panel (440) on the right.
	.review {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 440px;

		&__problem {
			padding: var(--space-medium);
		}

		&__panel {
			display: flex;
			flex-direction: column;
			gap: 20px;
			min-width: 0;
			padding: 20px;
			border-left: var(--border-base) solid var(--color-border);
			background: var(--color-surface);
		}

		&__section {
			display: flex;
			flex-direction: column;
			gap: 12px;
		}

		&__title {
			margin: 0;
			color: var(--color-heading);
			font-size: var(--typography--fontSize-large);
			font-weight: 600;
		}
	}

	// One box, a row per fact with a hairline between.
	.facts {
		margin: 0;
		padding: 0;
		overflow: hidden;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-large);
		list-style: none;
	}

	.fact {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 14px;

		& + & {
			border-top: var(--border-base) solid var(--color-border);
		}

		&--fix {
			background: var(--color-warning--surface);
			color: var(--color-warning--onSurface);

			.fact__label,
			.fact__value {
				color: var(--color-warning--onSurface);
			}
		}

		&__copy {
			display: flex;
			flex: 1 1 auto;
			flex-direction: column;
			min-width: 0;
			gap: 1px;
		}
		&__label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}
		&__value {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			overflow-wrap: anywhere;
		}
		&__line {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			overflow-wrap: anywhere;
		}
		&__alert {
			display: flex;
			flex: none;
			color: var(--color-warning--onSurface);

			:global(svg) {
				width: 20px;
				height: 20px;
			}
		}
	}

	// Send now / Schedule for later: two radio tiles.
	.when {
		display: flex;
		flex-direction: column;
		gap: 10px;

		&__tile {
			display: flex;
			flex-direction: column;
			gap: 12px;
			padding: 12px 14px;
			border: var(--border-base) solid var(--color-border);
			border-radius: var(--radius-large);
			background: var(--color-surface);
			cursor: pointer;

			// The tile that holds its own radio row (Schedule) is not itself the label.
			&:not(label) {
				cursor: default;
			}

			&--chosen {
				border-color: var(--color-interactive);
				box-shadow: inset 0 0 0 0.5px var(--color-interactive);
			}

			&:has(input:focus-visible) {
				outline: 2px solid var(--color-interactive);
				outline-offset: 2px;
			}
		}

		&__top {
			display: flex;
			align-items: center;
			gap: 12px;
			cursor: pointer;
		}

		// A label tile lays its radio, tile and words in one row.
		label#{&}__tile {
			flex-direction: row;
			align-items: center;
		}

		input {
			position: absolute;
			width: 1px;
			height: 1px;
			overflow: hidden;
			clip-path: inset(50%);
			opacity: 0;
		}

		&__radio {
			display: grid;
			flex: none;
			place-items: center;
			width: 18px;
			height: 18px;
			border: 1.5px solid var(--color-border--strong, var(--color-border));
			border-radius: var(--radius-circle);
			background: var(--color-surface);
		}
		&__tile--chosen &__radio {
			border-color: var(--color-interactive);

			&::after {
				content: '';
				width: 8px;
				height: 8px;
				border-radius: var(--radius-circle);
				background: var(--color-interactive);
			}
		}

		&__copy {
			display: flex;
			flex-direction: column;
			min-width: 0;
			gap: 1px;
		}
		&__name {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}
		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__pick {
			display: flex;
			flex-direction: column;
			gap: 10px;
		}
		&__zone {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}
	}

	.actions {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.test {
		display: flex;
		align-items: center;
		gap: 8px;
		margin: 0;
		padding: 8px 12px;
		border-radius: var(--radius-base);
		font-size: var(--typography--fontSize-small);
		font-weight: 500;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}

		&--success {
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
		}
		&--error {
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
		}
	}

	// A staff member sees why there is no send button, in a quiet box.
	.staff {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 14px;
		border-radius: var(--radius-large);
		background: var(--color-surface--background--subtle);

		&__copy {
			display: flex;
			flex-direction: column;
			gap: 1px;

			b {
				color: var(--color-heading);
				font-size: var(--typography--fontSize-base);
				font-weight: 600;
			}
			span {
				color: var(--color-text--secondary);
				font-size: var(--typography--fontSize-small);
			}
		}
	}

	// Loading: bones in the shape of the meter and the list.
	.review-bones {
		display: flex;
		flex-direction: column;
		gap: 20px;

		&__meter {
			height: 132px;
			border: var(--border-base) solid var(--color-growth--surface-edge);
			border-radius: var(--radius-large);
		}
		&__title {
			width: 60%;
			height: 20px;
		}
		&__list {
			display: flex;
			flex-direction: column;
			gap: 14px;
		}
		&__row {
			display: flex;
			align-items: center;
			gap: 12px;
		}
		&__tile {
			flex: none;
			width: 32px;
			height: 32px;
			border-radius: var(--radius-base);
		}
		&__lines {
			display: flex;
			flex: 1;
			flex-direction: column;
			gap: 6px;
		}
		&__line {
			height: 12px;

			&--short {
				width: 30%;
			}
		}
	}

	.foot-hint {
		flex: 1;
		color: var(--color-text--secondary);
		font-size: var(--typography--fontSize-small);
		text-align: right;
	}

	.btn-icon {
		display: inline-flex;

		:global(svg) {
			display: block;
			width: 16px;
			height: 16px;
		}
	}

	// A narrow window puts the launch panel under the email.
	@media (max-width: 960px) {
		.review {
			grid-template-columns: minmax(0, 1fr);

			&__panel {
				border-left: 0;
				border-top: var(--border-base) solid var(--color-border);
			}
		}
	}
</style>
