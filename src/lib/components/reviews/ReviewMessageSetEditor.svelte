<script lang="ts">
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SmsActionEditor from '$lib/components/settings/automation/SmsActionEditor.svelte';
	import EmailActionEditor from '$lib/components/settings/automation/EmailActionEditor.svelte';
	import {
		REVIEW_MESSAGE_VARIABLES,
		REVIEW_STYLES,
		REVIEW_STYLE_LABELS,
		type ReviewChannel,
		type ReviewMessageSet,
		type ReviewStyle
	} from '$lib/reviews/settings';

	// One review message's wording in each channel and style: the first message (ReviewMessageStylesEditor)
	// and every reminder (ReviewRequestPlanEditor). Editing reuses the automation message editors, so the
	// variable picker and SMS length line behave exactly as they do there.
	let {
		messages = $bindable(),
		defaults,
		idPrefix,
		errorPrefix,
		disabled = false,
		fieldErrors = {},
		subjectPlaceholder = 'e.g. How did we do, {{customer_first_name}}?'
	}: {
		messages: ReviewMessageSet;
		// The original wording "Restore" puts back.
		defaults: ReviewMessageSet;
		idPrefix: string;
		// Where this set's field errors live, e.g. "message_styles" or "request_plan.reminders.0.messages".
		errorPrefix: string;
		disabled?: boolean;
		fieldErrors?: Record<string, string>;
		subjectPlaceholder?: string;
	} = $props();

	let channel = $state<ReviewChannel>('sms');
	let style = $state<ReviewStyle>('friendly');

	const channelOptions = [
		{ value: 'sms', label: 'Text message' },
		{ value: 'email', label: 'Email' }
	];

	function errorFor(key: ReviewChannel, value: ReviewStyle) {
		const prefix = `${errorPrefix}.${key}.${value}`;
		return Object.entries(fieldErrors).find(([path]) => path.startsWith(prefix))?.[1] ?? '';
	}

	// A tab with a problem gets a marker, so an error on a tab you are not looking at is not missed.
	const channelTabs = $derived(
		channelOptions.map((option) => ({
			...option,
			label: REVIEW_STYLES.some((value) => errorFor(option.value as ReviewChannel, value) !== '')
				? `${option.label} •`
				: option.label
		}))
	);
	const styleTabs = $derived(
		REVIEW_STYLES.map((value) => ({
			value,
			label:
				errorFor(channel, value) !== ''
					? `${REVIEW_STYLE_LABELS[value]} •`
					: REVIEW_STYLE_LABELS[value]
		}))
	);

	const isChanged = $derived(
		channel === 'sms'
			? messages.sms[style].body !== defaults.sms[style].body
			: messages.email[style].subject !== defaults.email[style].subject ||
					messages.email[style].body !== defaults.email[style].body
	);

	function restore() {
		if (channel === 'sms') messages.sms[style] = { ...defaults.sms[style] };
		else messages.email[style] = { ...defaults.email[style] };
	}
</script>

<div class="message-set">
	<div class="message-set__row">
		<SegmentedControl
			label="Channel"
			options={channelTabs}
			value={channel}
			onchange={(value) => (channel = value as ReviewChannel)}
		/>
		<SegmentedControl
			label="Style"
			options={styleTabs}
			value={style}
			onchange={(value) => (style = value as ReviewStyle)}
		/>
	</div>

	{#if channel === 'sms'}
		<SmsActionEditor
			idPrefix={`${idPrefix}-sms-${style}`}
			body={messages.sms[style].body}
			variables={REVIEW_MESSAGE_VARIABLES}
			showSender={false}
			errorMessage={errorFor('sms', style)}
			onBodyChange={(value) => (messages.sms[style].body = value)}
		/>
	{:else}
		<EmailActionEditor
			idPrefix={`${idPrefix}-email-${style}`}
			subject={messages.email[style].subject}
			body={messages.email[style].body}
			variables={REVIEW_MESSAGE_VARIABLES}
			{subjectPlaceholder}
			errorMessage={errorFor('email', style)}
			onSubjectChange={(value) => (messages.email[style].subject = value)}
			onBodyChange={(value) => (messages.email[style].body = value)}
		/>
	{/if}

	<div class="message-set__footer">
		<Button variant="tertiary" size="small" disabled={disabled || !isChanged} onclick={restore}>
			Restore the original wording
		</Button>
	</div>
</div>

<style lang="scss">
	.message-set {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__row {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-base);
		}

		&__footer {
			display: flex;
			justify-content: flex-end;
		}
	}
</style>
