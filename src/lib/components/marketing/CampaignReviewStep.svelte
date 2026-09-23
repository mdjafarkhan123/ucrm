<script lang="ts">
	import { page } from '$app/state';
	import Button from '$lib/components/ui/Button.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import DateTimePicker from '$lib/components/ui/DateTimePicker.svelte';
	import {
		calendarDateToString,
		emptyDateTimePickerValue,
		timeToString,
		type DateTimePickerValue
	} from '$lib/components/ui/date-time';
	import LoadingSkeleton from '$lib/components/data-display/LoadingSkeleton.svelte';
	import ErrorState from '$lib/components/data-display/ErrorState.svelte';
	import CustomerGroupPreview from './CustomerGroupPreview.svelte';
	import MarketingSenderSummary from './MarketingSenderSummary.svelte';
	import MarketingAllowanceNotice from './MarketingAllowanceNotice.svelte';
	import MarketingTemplatePreview from './MarketingTemplatePreview.svelte';
	import {
		MARKETING_CTA_TYPE_LABELS,
		marketingGoalLabels,
		type MarketingCampaignContent,
		type MarketingCtaType,
		type MarketingGoal
	} from '$lib/marketing/campaign-content';
	import {
		MARKETING_GROUP_RULE_CONDITIONS,
		type MarketingCustomerGroup
	} from '$lib/marketing/customer-groups';
	import { sendTestEmailRequest, type MarketingDeliveryOptions } from '$lib/marketing/api';
	import { zonedTimeToUtc } from '$lib/time/calendar-day';
	import formsIcon from '@tabler/icons/outline/forms.svg?raw';
	import worldIcon from '@tabler/icons/outline/world.svg?raw';
	import phoneIcon from '@tabler/icons/outline/phone.svg?raw';
	import externalLinkIcon from '@tabler/icons/outline/external-link.svg?raw';
	import rocketIcon from '@tabler/icons/outline/rocket.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import alertTriangleIcon from '@tabler/icons/outline/alert-triangle.svg?raw';
	import arrowLeftIcon from '@tabler/icons/outline/arrow-left.svg?raw';
	import sendIcon from '@tabler/icons/outline/send.svg?raw';

	// Step 5 (blueprint §8 step 5): a final, read-only summary before send. Nothing here is editable -- every
	// field was chosen on an earlier step; "Back" is how a contractor changes any of it. Only the owner or an
	// administrator ever sees a working Send/Schedule control (blueprint §14); everyone else is shown why not.
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

	const ctaIcons: Record<MarketingCtaType, string> = {
		internal_form: formsIcon,
		website: worldIcon,
		phone: phoneIcon
	};

	const selectedGroup = $derived(groups.find((group) => group.id === customerGroupId) ?? null);
	const activeConditionLabels = $derived(
		selectedGroup
			? MARKETING_GROUP_RULE_CONDITIONS.filter(
					(condition) => selectedGroup.rules[condition.key] !== undefined
				).map((condition) => condition.label)
			: []
	);

	const chosenFormId = $derived(content.cta?.type === 'internal_form' ? content.cta.form_id : '');
	const chosenForm = $derived(
		chosenFormId ? (options.forms.find((form) => form.id === chosenFormId) ?? null) : null
	);
	const formNoLongerAvailable = $derived(content.cta?.type === 'internal_form' && !chosenForm);

	function websiteHref(website: string) {
		return /^https?:\/\//i.test(website) ? website : `https://${website}`;
	}

	// Only the owner or an administrator may launch a campaign (blueprint §14) -- a Marketing-enabled staff
	// member can build and review a draft but the app never offers them a button that would send it.
	const canSend = $derived(
		page.data.organization?.role === 'owner' || page.data.organization?.role === 'admin'
	);

	let sendMode = $state<'now' | 'schedule'>('now');
	let when = $state<DateTimePickerValue>(emptyDateTimePickerValue());
	let sending = $state(false);
	let sendError = $state('');

	const sendModeOptions = [
		{ value: 'now', label: 'Send now' },
		{ value: 'schedule', label: 'Schedule for later' }
	];

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
</script>

<section class="panel">
	<header class="panel__head">
		<h2>Review before you send</h2>
		<p>One last check. Use Back to change anything below.</p>
	</header>

	<div class="panel__body">
		{#if isPending}
			<LoadingSkeleton variant="text" rows={4} label="Loading your campaign for review" />
		{:else if isError}
			<ErrorState description="This campaign could not be loaded for review." retry={onRetry} />
		{:else}
			<div class="block">
				<h3>Message</h3>
				<p class="review-subject">{content.subject || 'No subject yet'}</p>
				<MarketingTemplatePreview title={name || 'Campaign'} {content} />
			</div>

			<div class="block">
				<h3>Goal &amp; recipients</h3>
				<p class="review-line"><b>Goal:</b> {goal ? marketingGoalLabels[goal] : 'Not set'}</p>
				<p class="review-line">
					<b>Customer group:</b>
					{selectedGroup?.name ?? 'Not set'}
				</p>
				<p class="hint">
					{#if activeConditionLabels.length > 0}
						Matches customers who: {activeConditionLabels.join(', ')}.
					{:else}
						No conditions set — matches every active customer.
					{/if}
				</p>
				{#if selectedGroup}
					<CustomerGroupPreview rules={selectedGroup.rules} />
				{/if}
				<MarketingAllowanceNotice allowance={options.allowance} />
			</div>

			<div class="block">
				<h3>Sender &amp; replies</h3>
				<MarketingSenderSummary sender={options.sender} />
			</div>

			<div class="block">
				<h3>What customers are asked to do</h3>
				{#if content.cta}
					{@const cta = content.cta}
					<div class="review-cta">
						<!-- eslint-disable-next-line svelte/no-at-html-tags -->
						<span class="review-cta__icon" aria-hidden="true">{@html ctaIcons[cta.type]}</span>
						<span class="review-cta__label">{MARKETING_CTA_TYPE_LABELS[cta.type]}</span>
						{#if cta.type === 'internal_form'}
							{#if formNoLongerAvailable}
								<span class="warning"
									>This form is no longer available. Go back and choose another.</span
								>
							{:else if chosenForm}
								<Button
									variant="secondary"
									variation="subtle"
									size="small"
									href={`/forms/${options.organization_slug}/${chosenForm.public_slug}`}
									target="_blank"
								>
									<!-- eslint-disable-next-line svelte/no-at-html-tags -->
									<span class="btn-icon" aria-hidden="true">{@html externalLinkIcon}</span> Open form
								</Button>
							{/if}
						{:else if cta.type === 'website'}
							<Button
								variant="secondary"
								variation="subtle"
								size="small"
								href={websiteHref(options.business_website ?? '')}
								target="_blank"
							>
								<!-- eslint-disable-next-line svelte/no-at-html-tags -->
								<span class="btn-icon" aria-hidden="true">{@html externalLinkIcon}</span>
								{options.business_website}
							</Button>
						{:else if cta.type === 'phone'}
							<span class="hint"
								>Customers will be shown a Call button for {options.business_phone}.</span
							>
						{/if}
					</div>
				{:else}
					<p class="warning">No call to action chosen. Go back to Delivery to choose one.</p>
				{/if}
			</div>

			<div class="notice">
				<!-- eslint-disable-next-line svelte/no-at-html-tags -->
				<span class="notice__icon" aria-hidden="true">{@html alertTriangleIcon}</span>
				<span>
					Sent email cannot be recalled. Cancelling a campaign in progress only stops recipients who
					haven't been sent to yet.
				</span>
			</div>

			{#if canSend}
				<div class="block">
					<h3>Send</h3>
					<SegmentedControl bind:value={sendMode} options={sendModeOptions} />
					{#if sendMode === 'schedule'}
						<DateTimePicker
							id="campaign-review-send-at"
							range={false}
							dateLabel="Day to send"
							timeLabel="Time"
							bind:value={when}
						/>
					{/if}
					{#if sendError}
						<p class="warning" role="alert">{sendError}</p>
					{/if}

					<div class="test-send">
						<Button
							variant="secondary"
							variation="subtle"
							size="small"
							loading={testSending}
							onclick={() => void sendTest()}
						>
							<!-- eslint-disable-next-line svelte/no-at-html-tags -->
							<span class="btn-icon" aria-hidden="true">{@html sendIcon}</span> Send a test email
						</Button>
						{#if testMessage}
							<p class="test-send__success">{testMessage}</p>
						{:else if testError}
							<p class="test-send__error" role="alert">{testError}</p>
						{/if}
					</div>
				</div>
			{/if}
		{/if}
	</div>

	<footer class="panel__foot">
		<Button variant="secondary" variation="subtle" onclick={onBack}>
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span class="btn-icon" aria-hidden="true">{@html arrowLeftIcon}</span> Back
		</Button>
		<div class="panel__foot-right">
			{#if canSend}
				<Button
					variant="primary"
					loading={sending}
					disabled={isPending || isError}
					onclick={() => void handleSend()}
				>
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span class="btn-icon" aria-hidden="true">{@html rocketIcon}</span>
					{sendMode === 'schedule' ? 'Schedule campaign' : 'Send now'}
				</Button>
			{:else}
				<span class="panel__foot-note">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -->
					<span class="btn-icon" aria-hidden="true">{@html lockIcon}</span>
					Only the business owner or an administrator can send or schedule this campaign.
				</span>
			{/if}
		</div>
	</footer>
</section>

<style lang="scss">
	.panel {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-large);
		box-shadow: var(--shadow-base);
		overflow: hidden;

		&__head {
			padding: var(--space-large) var(--space-large) var(--space-base);
			border-bottom: 1px solid var(--color-border);

			h2 {
				font-family: var(--typography--fontFamily-display);
				font-size: var(--typography--fontSize-larger);
				font-weight: 600;
				color: var(--color-heading);
				margin: 0;
			}
			p {
				margin: var(--space-smaller) 0 0;
				color: var(--color-text--secondary);
			}
		}

		&__body {
			display: flex;
			flex-direction: column;
			gap: var(--space-large);
			padding: var(--space-large);
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			flex-wrap: wrap;
			gap: var(--space-base);
			padding: var(--space-base) var(--space-large);
			border-top: 1px solid var(--color-border);
			background: var(--color-surface--background--subtle);

			&-right {
				display: flex;
				align-items: center;
				gap: var(--space-base);
				flex-wrap: wrap;
			}

			&-note {
				display: flex;
				align-items: center;
				gap: var(--space-smaller);
				font-size: var(--typography--fontSize-small);
				color: var(--color-text--secondary);
			}
		}
	}

	.block {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		h3 {
			font-family: var(--typography--fontFamily-display);
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
			color: var(--color-heading);
			margin: 0;
		}
	}

	.review-subject {
		margin: 0;
		color: var(--color-heading);
		font-weight: 600;
	}

	.review-line {
		margin: 0;
		color: var(--color-text--secondary);

		b {
			color: var(--color-heading);
			font-weight: 600;
		}
	}

	.hint {
		margin: 0;
		font-size: var(--typography--fontSize-small);
		color: var(--color-text--secondary);
	}

	.warning {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		margin: 0;
		color: var(--color-warning--onSurface);
		font-size: var(--typography--fontSize-small);
	}

	.review-cta {
		display: flex;
		align-items: center;
		gap: var(--space-small);
		flex-wrap: wrap;

		&__icon {
			display: grid;
			place-items: center;
			color: var(--color-interactive);

			:global(svg) {
				width: 18px;
				height: 18px;
			}
		}

		&__label {
			font-weight: 600;
			color: var(--color-heading);
		}
	}

	.notice {
		display: flex;
		align-items: flex-start;
		gap: var(--space-small);
		padding: var(--space-slim) var(--space-base);
		border-radius: var(--radius-base);
		background: var(--color-informative--surface);
		color: var(--color-informative--onSurface);
		font-size: var(--typography--fontSize-small);

		&__icon {
			flex: none;
			display: grid;
			place-items: center;
			margin-top: 2px;

			:global(svg) {
				width: 16px;
				height: 16px;
			}
		}
	}

	.btn-icon :global(svg) {
		width: 16px;
		height: 16px;
		display: block;
	}

	.test-send {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-smaller);

		&__success {
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-success--surface);
			color: var(--color-success--onSurface);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			padding: var(--space-slim) var(--space-base);
			border-radius: var(--radius-base);
			background: var(--color-critical--surface);
			color: var(--color-critical--onSurface);
			font-size: var(--typography--fontSize-small);
		}
	}

	@media (max-width: 560px) {
		.panel__foot {
			flex-direction: column-reverse;
			align-items: stretch;
		}
		.panel__foot-right {
			flex-direction: column-reverse;
			align-items: stretch;
		}
	}
</style>
