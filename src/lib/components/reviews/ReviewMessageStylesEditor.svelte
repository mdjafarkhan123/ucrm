<script lang="ts">
	import SectionBlock from '$lib/components/layout/SectionBlock.svelte';
	import Select from '$lib/components/ui/Select.svelte';
	import ReviewMessageSetEditor from './ReviewMessageSetEditor.svelte';
	import {
		DEFAULT_REVIEW_MESSAGE_STYLES,
		REVIEW_STYLES,
		REVIEW_STYLE_LABELS,
		type ReviewMessageStyles,
		type ReviewStyle
	} from '$lib/reviews/settings';
	import mailIcon from '@tabler/icons/outline/mail-forward.svg?raw';

	// The three editable starting styles for a review request's first message, for each channel. A manual
	// request and the automation both start from these; `default_style` is the one picked first.
	let {
		styles = $bindable(),
		disabled = false,
		fieldErrors = {}
	}: {
		styles: ReviewMessageStyles;
		disabled?: boolean;
		fieldErrors?: Record<string, string>;
	} = $props();

	const styleOptions = REVIEW_STYLES.map((value) => ({ value, label: REVIEW_STYLE_LABELS[value] }));
</script>

<SectionBlock
	title="Request messages"
	hint="The wording your review requests start from. Every message must include the review link."
	icon={mailIcon}
	form
	level={3}
>
	<div class="message-styles">
		<ReviewMessageSetEditor
			bind:messages={styles}
			defaults={DEFAULT_REVIEW_MESSAGE_STYLES}
			idPrefix="review"
			errorPrefix="message_styles"
			{disabled}
			{fieldErrors}
		/>

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
				Reminders use the same style as the request they follow.
			</p>
		</div>
	</div>
</SectionBlock>

<style lang="scss">
	.message-styles {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

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
