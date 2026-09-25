<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import SegmentedControl from '$lib/components/ui/SegmentedControl.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import Button from '$lib/components/ui/Button.svelte';
	import SmsActionEditor from '$lib/components/settings/automation/SmsActionEditor.svelte';
	import EmailActionEditor from '$lib/components/settings/automation/EmailActionEditor.svelte';
	import {
		DEFAULT_REVIEW_MESSAGE_STYLES,
		REVIEW_MESSAGE_VARIABLES,
		REVIEW_STYLES,
		REVIEW_STYLE_LABELS,
		type ReviewChannel,
		type ReviewMessageStyles,
		type ReviewStyle
	} from '$lib/reviews/settings';
	import mailIcon from '@tabler/icons/outline/mail-forward.svg?raw';

	// The three editable starting styles for a review request, for each channel. A manual request and the
	// automation both start from these; `default_style` is the one picked first. Editing reuses the automation
	// message editors, so the variable picker and SMS length line behave exactly as they do there.
	let {
		styles = $bindable(),
		disabled = false,
		fieldErrors = {}
	}: {
		styles: ReviewMessageStyles;
		disabled?: boolean;
		fieldErrors?: Record<string, string>;
	} = $props();

	let channel = $state<ReviewChannel>('sms');
	let style = $state<ReviewStyle>('friendly');

	const channelOptions = [
		{ value: 'sms', label: 'Text message' },
		{ value: 'email', label: 'Email' }
	];
	const styleOptions = REVIEW_STYLES.map((value) => ({ value, label: REVIEW_STYLE_LABELS[value] }));

	function errorFor(key: ReviewChannel, value: ReviewStyle) {
		const prefix = `message_styles.${key}.${value}`;
		return Object.entries(fieldErrors).find(([path]) => path.startsWith(prefix))?.[1] ?? '';
	}

	// A style tab with a problem gets a marker, so an error on a tab you are not looking at is not missed.
	function styleHasError(key: ReviewChannel, value: ReviewStyle) {
		return errorFor(key, value) !== '';
	}

	const styleTabs = $derived(
		styleOptions.map((option) => ({
			...option,
			label: styleHasError(channel, option.value) ? `${option.label} •` : option.label
		}))
	);

	const isChanged = $derived(
		channel === 'sms'
			? styles.sms[style].body !== DEFAULT_REVIEW_MESSAGE_STYLES.sms[style].body
			: styles.email[style].subject !== DEFAULT_REVIEW_MESSAGE_STYLES.email[style].subject ||
					styles.email[style].body !== DEFAULT_REVIEW_MESSAGE_STYLES.email[style].body
	);

	function resetStyle() {
		if (channel === 'sms') styles.sms[style] = { ...DEFAULT_REVIEW_MESSAGE_STYLES.sms[style] };
		else styles.email[style] = { ...DEFAULT_REVIEW_MESSAGE_STYLES.email[style] };
	}
</script>

<SectionBlock
	title="Request messages"
	hint="The wording your review requests start from. Every message must include the review link."
	icon={mailIcon}
	form
	level={3}
>
	<div class="message-styles">
		<div class="message-styles__row">
			<SegmentedControl
				label="Channel"
				options={channelOptions}
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
				idPrefix={`review-sms-${style}`}
				body={styles.sms[style].body}
				variables={REVIEW_MESSAGE_VARIABLES}
				showSender={false}
				errorMessage={errorFor('sms', style)}
				onBodyChange={(value) => (styles.sms[style].body = value)}
			/>
		{:else}
			<EmailActionEditor
				idPrefix={`review-email-${style}`}
				subject={styles.email[style].subject}
				body={styles.email[style].body}
				variables={REVIEW_MESSAGE_VARIABLES}
				subjectPlaceholder="e.g. How did we do, {'{{customer_first_name}}'}?"
				errorMessage={errorFor('email', style)}
				onSubjectChange={(value) => (styles.email[style].subject = value)}
				onBodyChange={(value) => (styles.email[style].body = value)}
			/>
		{/if}

		<div class="message-styles__footer">
			<Button
				variant="tertiary"
				size="small"
				disabled={disabled || !isChanged}
				onclick={resetStyle}
			>
				Restore the original wording
			</Button>
		</div>

		<div class="message-styles__default">
			<Select
				id="review-default-style"
				label="Style picked first"
				options={styleOptions}
				value={styles.default_style}
				{disabled}
				onchange={(value) => (styles.default_style = value as ReviewStyle)}
			/>
			<p class="message-styles__hint">
				Text messages are sent first. You can choose email instead when you send a request.
			</p>
		</div>
	</div>
</SectionBlock>

<style lang="scss">
	.message-styles {
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

		&__default {
			display: flex;
			flex-direction: column;
			gap: var(--space-smaller);
			max-width: 320px;
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
