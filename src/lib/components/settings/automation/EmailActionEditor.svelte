<script lang="ts">
	import MessageSheet from '$lib/components/ui/MessageSheet.svelte';
	import { AUTOMATION_EMAIL_VARIABLES } from '$lib/automation/email-variables';

	// Contractor Settings Part 6D-3b: the authoring card for one "Send an email" step. The contractor writes
	// the subject and message as plain text; the only dynamic values they can drop in are the fixed,
	// allow-listed variables (email-variables.ts), inserted at the caret from the sheet's values bar. The send
	// path fills and HTML-escapes them, so authored text can never become markup. There is no template picker
	// and no raw HTML — what you type is what goes out, with the variables swapped for real values.
	let {
		idPrefix,
		subject,
		body,
		errorMessage = '',
		variables = AUTOMATION_EMAIL_VARIABLES,
		subjectPlaceholder = 'e.g. Following up on your quote {{quote_number}}',
		onSubjectChange,
		onBodyChange
	}: {
		idPrefix: string;
		subject: string;
		body: string;
		errorMessage?: string;
		// The insertable values; a website inquiry passes its smaller, quote-free list.
		variables?: ReadonlyArray<{ token: string; label: string }>;
		subjectPlaceholder?: string;
		onSubjectChange: (value: string) => void;
		onBodyChange: (value: string) => void;
	} = $props();
</script>

<MessageSheet
	{idPrefix}
	{subject}
	{body}
	bodyMaxlength={5000}
	bodyRows={7}
	{variables}
	{subjectPlaceholder}
	{errorMessage}
	hint={'Values in {{ }} are swapped for the real details when it sends.'}
	{onSubjectChange}
	{onBodyChange}
/>
