<script lang="ts">
	import { tick } from 'svelte';
	import Input from '$lib/components/ui/Input.svelte';
	import Textarea from '$lib/components/ui/Textarea.svelte';
	import { AUTOMATION_EMAIL_VARIABLES } from '$lib/automation/email-variables';

	// Contractor Settings Part 6D-3b: the authoring card for one "Send an email" step. The contractor writes
	// the subject and message as plain text; the only dynamic values they can drop in are the fixed,
	// allow-listed variables (email-variables.ts), inserted at the caret through the picker below. The send
	// path fills and HTML-escapes them, so authored text can never become markup. There is no template picker
	// and no raw HTML — what you type is what goes out, with the variables swapped for real values.
	let {
		idPrefix,
		subject,
		body,
		errorMessage = '',
		onSubjectChange,
		onBodyChange
	}: {
		idPrefix: string;
		subject: string;
		body: string;
		errorMessage?: string;
		onSubjectChange: (value: string) => void;
		onBodyChange: (value: string) => void;
	} = $props();

	const subjectId = $derived(`${idPrefix}-subject`);
	const bodyId = $derived(`${idPrefix}-body`);

	// The field a picked variable lands in. Follows focus; defaults to the body since that is where most copy
	// goes. A picker click keeps the field focused (mousedown preventDefault), so the caret is still live.
	let lastField = $state<'subject' | 'body'>('body');

	function activeField(): 'subject' | 'body' {
		const active = document.activeElement;
		if (active?.id === subjectId) return 'subject';
		if (active?.id === bodyId) return 'body';
		return lastField;
	}

	async function insertVariable(token: string) {
		const field = activeField();
		const id = field === 'subject' ? subjectId : bodyId;
		const el = document.getElementById(id) as HTMLInputElement | HTMLTextAreaElement | null;
		const current = field === 'subject' ? subject : body;
		const placeholder = `{{${token}}}`;

		const start = el?.selectionStart ?? current.length;
		const end = el?.selectionEnd ?? current.length;
		const next = current.slice(0, start) + placeholder + current.slice(end);

		if (field === 'subject') onSubjectChange(next);
		else onBodyChange(next);

		// Put the caret just after the inserted token once the new value has rendered.
		await tick();
		const refreshed = document.getElementById(id) as HTMLInputElement | HTMLTextAreaElement | null;
		if (refreshed) {
			const caret = start + placeholder.length;
			refreshed.focus();
			refreshed.setSelectionRange(caret, caret);
		}
	}
</script>

<div class="email-editor">
	<Input
		id={subjectId}
		label="Subject line"
		required
		value={subject}
		maxlength="300"
		onfocus={() => (lastField = 'subject')}
		oninput={(event: Event) => onSubjectChange((event.currentTarget as HTMLInputElement).value)}
		placeholder={'e.g. Following up on your quote {{quote_number}}'}
	/>

	<Textarea
		id={bodyId}
		label="Message"
		required
		rows={7}
		maxlength={5000}
		value={body}
		onfocus={() => (lastField = 'body')}
		oninput={(event: Event) => onBodyChange((event.currentTarget as HTMLTextAreaElement).value)}
	/>

	<div class="email-editor__variables">
		<span class="email-editor__variables-label">Insert a value</span>
		<div class="email-editor__variable-list">
			{#each AUTOMATION_EMAIL_VARIABLES as variable (variable.token)}
				<button
					type="button"
					class="email-editor__variable"
					onmousedown={(event) => event.preventDefault()}
					onclick={() => insertVariable(variable.token)}
				>
					{variable.label}
				</button>
			{/each}
		</div>
		<p class="email-editor__hint">
			These get replaced with the real details when the email is sent.
		</p>
	</div>

	{#if errorMessage}
		<p class="email-editor__error" role="alert">{errorMessage}</p>
	{/if}
</div>

<style lang="scss">
	.email-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-base);

		&__variables {
			display: flex;
			flex-direction: column;
			gap: var(--space-small);
		}

		&__variables-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__variable-list {
			display: flex;
			flex-wrap: wrap;
			gap: var(--space-small);
		}

		&__variable {
			display: inline-flex;
			align-items: center;
			min-height: 32px;
			padding: var(--space-smaller) var(--space-slim);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			color: var(--color-interactive);
			background: var(--color-surface);
			font: inherit;
			font-weight: 600;
			cursor: pointer;
			transition: all var(--timing-base) ease-out;

			&:hover,
			&:focus-visible {
				border-color: var(--color-interactive--hover);
				color: var(--color-interactive--hover);
				background: var(--color-surface--hover);
			}
			&:focus-visible {
				outline: transparent;
				box-shadow: var(--shadow-focus);
			}
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}

		&__error {
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
