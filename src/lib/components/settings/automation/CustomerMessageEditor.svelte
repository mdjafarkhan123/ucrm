<script lang="ts">
	import SmsActionEditor from './SmsActionEditor.svelte';
	import EmailActionEditor from './EmailActionEditor.svelte';
	import { AUTOMATION_INQUIRY_VARIABLES } from '$lib/automation/email-variables';

	// CRM launch readiness Part 4 Stage 6: the authoring card for one "Reply by text or email" step on a website
	// inquiry. It composes the two existing editors: the text is used when the customer agreed to texts and a
	// number is ready, and the email is used otherwise or when the text is reported failed — so the email is
	// always required and the text is optional (left empty, the step only emails).
	let {
		idPrefix,
		smsBody,
		emailSubject,
		emailBody,
		errorMessage = '',
		onSmsBodyChange,
		onEmailSubjectChange,
		onEmailBodyChange
	}: {
		idPrefix: string;
		smsBody: string;
		emailSubject: string;
		emailBody: string;
		errorMessage?: string;
		onSmsBodyChange: (value: string) => void;
		onEmailSubjectChange: (value: string) => void;
		onEmailBodyChange: (value: string) => void;
	} = $props();
</script>

<div class="customer-message">
	<section class="customer-message__channel" aria-labelledby={`${idPrefix}-sms-title`}>
		<h4 id={`${idPrefix}-sms-title`} class="customer-message__title">Text message</h4>
		<p class="customer-message__hint">
			Sent when the customer ticked the box agreeing to texts and your texting number is ready.
			Leave it empty to always email.
		</p>
		<SmsActionEditor
			idPrefix={`${idPrefix}-sms`}
			body={smsBody}
			required={false}
			showSender={false}
			variables={AUTOMATION_INQUIRY_VARIABLES}
			onBodyChange={onSmsBodyChange}
		/>
	</section>

	<section class="customer-message__channel" aria-labelledby={`${idPrefix}-email-title`}>
		<h4 id={`${idPrefix}-email-title`} class="customer-message__title">Email</h4>
		<p class="customer-message__hint">
			Sent when a text is not possible, or instead of a text that could not be delivered.
		</p>
		<EmailActionEditor
			{idPrefix}
			subject={emailSubject}
			body={emailBody}
			variables={AUTOMATION_INQUIRY_VARIABLES}
			subjectPlaceholder={'e.g. Thanks for contacting {{business_name}}'}
			onSubjectChange={onEmailSubjectChange}
			onBodyChange={onEmailBodyChange}
		/>
	</section>

	{#if errorMessage}
		<p class="customer-message__error" role="alert">{errorMessage}</p>
	{/if}
</div>

<style lang="scss">
	.customer-message {
		display: flex;
		flex-direction: column;
		gap: var(--space-large);

		&__channel {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);

			& + & {
				padding-top: var(--space-large);
				border-top: var(--border-base) solid var(--color-border);
			}
		}

		&__title {
			color: var(--color-heading);
			font-size: var(--typography--fontSize-base);
			font-weight: 700;
		}

		&__hint {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			line-height: var(--typography--lineHeight-base);
		}

		&__error {
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
