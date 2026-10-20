<script lang="ts">
	import { tick } from 'svelte';
	import bracesIcon from '@tabler/icons/outline/braces.svg?raw';
	import userIcon from '@tabler/icons/outline/user.svg?raw';
	import storeIcon from '@tabler/icons/outline/building-store.svg?raw';
	import hashIcon from '@tabler/icons/outline/hash.svg?raw';
	import linkIcon from '@tabler/icons/outline/link.svg?raw';
	import calendarIcon from '@tabler/icons/outline/calendar.svg?raw';
	import mapPinIcon from '@tabler/icons/outline/map-pin.svg?raw';
	import moneyIcon from '@tabler/icons/outline/currency-dollar.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// The message sheet (`inputs.md`, board `qf1uu`): an automation's email or text written in one sheet,
	// like a mail app. The subject row shows only for an email. The value chips at the sheet's foot drop a
	// `{{token}}` in at the caret of whichever field was last in use.
	let {
		idPrefix,
		subject,
		body,
		subjectMaxlength = 300,
		bodyMaxlength,
		bodyRows = 6,
		required = true,
		variables,
		subjectPlaceholder,
		bodyPlaceholder,
		hint,
		errorMessage = '',
		onSubjectChange,
		onBodyChange
	}: {
		idPrefix: string;
		/** Undefined for a text message: no subject row. */
		subject?: string;
		body: string;
		subjectMaxlength?: number;
		bodyMaxlength: number;
		bodyRows?: number;
		required?: boolean;
		variables: ReadonlyArray<{ token: string; label: string }>;
		subjectPlaceholder?: string;
		bodyPlaceholder?: string;
		hint: string;
		errorMessage?: string;
		onSubjectChange?: (value: string) => void;
		onBodyChange: (value: string) => void;
	} = $props();

	const subjectId = $derived(`${idPrefix}-subject`);
	const bodyId = $derived(`${idPrefix}-body`);
	const errorId = $derived(`${idPrefix}-error`);
	const remaining = $derived(bodyMaxlength - body.length);
	const hasSubject = $derived(subject !== undefined);

	// The field a picked value lands in. Follows focus; defaults to the message since that is where most
	// copy goes. A chip press keeps the field focused (mousedown preventDefault), so the caret is still live.
	let lastField = $state<'subject' | 'body'>('body');

	function activeField(): 'subject' | 'body' {
		const active = document.activeElement;
		if (hasSubject && active?.id === subjectId) return 'subject';
		if (active?.id === bodyId) return 'body';
		return hasSubject ? lastField : 'body';
	}

	async function insertVariable(token: string) {
		const field = activeField();
		const id = field === 'subject' ? subjectId : bodyId;
		const el = document.getElementById(id) as HTMLInputElement | HTMLTextAreaElement | null;
		const current = field === 'subject' ? (subject ?? '') : body;
		const placeholder = `{{${token}}}`;

		const start = el?.selectionStart ?? current.length;
		const end = el?.selectionEnd ?? current.length;
		const next = current.slice(0, start) + placeholder + current.slice(end);

		if (field === 'subject') onSubjectChange?.(next);
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

	// A small picture of what each value is, so the chips read at a glance.
	function variableIcon(token: string) {
		if (token.includes('link')) return linkIcon;
		if (token.startsWith('business')) return storeIcon;
		if (token.startsWith('customer')) return userIcon;
		if (token.includes('number')) return hashIcon;
		if (token.includes('when') || token.includes('date')) return calendarIcon;
		if (token.includes('address')) return mapPinIcon;
		if (token.includes('balance') || token.includes('amount') || token.includes('total'))
			return moneyIcon;
		return bracesIcon;
	}
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<div class="message-sheet" class:message-sheet--invalid={Boolean(errorMessage)}>
	<div class="message-sheet__sheet">
		{#if hasSubject}
			<div class="message-sheet__subject">
				<label class="message-sheet__label" for={subjectId}
					>Subject{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</label
				>
				<input
					id={subjectId}
					class="message-sheet__subject-input"
					value={subject}
					maxlength={subjectMaxlength}
					placeholder={subjectPlaceholder}
					aria-required={required || undefined}
					aria-invalid={Boolean(errorMessage)}
					aria-describedby={errorMessage ? errorId : undefined}
					onfocus={() => (lastField = 'subject')}
					oninput={(event) => onSubjectChange?.(event.currentTarget.value)}
				/>
			</div>
		{/if}
		<div class="message-sheet__message">
			<label class="message-sheet__label" for={bodyId}
				>Message{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</label
			>
			<textarea
				id={bodyId}
				class="message-sheet__body"
				rows={bodyRows}
				maxlength={bodyMaxlength}
				value={body}
				placeholder={bodyPlaceholder}
				aria-required={required || undefined}
				aria-invalid={Boolean(errorMessage)}
				aria-describedby={errorMessage ? errorId : undefined}
				onfocus={() => (lastField = 'body')}
				oninput={(event) => onBodyChange(event.currentTarget.value)}></textarea>
		</div>
		<div class="message-sheet__values">
			<span class="message-sheet__values-icon" aria-hidden="true">{@html bracesIcon}</span>
			<span class="message-sheet__values-label">Insert</span>
			<span class="message-sheet__chips">
				{#each variables as variable (variable.token)}
					<button
						type="button"
						class="message-sheet__chip"
						onmousedown={(event) => event.preventDefault()}
						onclick={() => insertVariable(variable.token)}
					>
						<span class="message-sheet__chip-icon" aria-hidden="true"
							>{@html variableIcon(variable.token)}</span
						>{variable.label}
					</button>
				{/each}
			</span>
			<span class="message-sheet__count">{remaining.toLocaleString()} left</span>
		</div>
	</div>
	{#if errorMessage}
		<p class="message-sheet__error" id={errorId} role="alert">
			<span aria-hidden="true">{@html alertIcon}</span>{errorMessage}
		</p>
	{/if}
	<p class="message-sheet__hint">{hint}</p>
</div>

<style lang="scss">
	.message-sheet {
		display: flex;
		flex-direction: column;
		gap: var(--space-small);

		&__sheet {
			display: flex;
			flex-direction: column;
			overflow: hidden;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			transition: box-shadow var(--timing-quick);

			&:focus-within {
				box-shadow:
					0 0 0 4px var(--color-surface),
					0 0 0 6px var(--color-focus);
			}
		}

		&--invalid &__sheet {
			border-color: var(--color-critical);
			box-shadow: inset 0 0 0 0.5px var(--color-critical);
		}

		&__subject {
			display: flex;
			align-items: center;
			gap: 10px;
			height: 44px;
			padding: 0 var(--space-slim);
			border-bottom: var(--border-base) solid var(--color-border);
		}

		&__label {
			flex: 0 0 auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-label);
			font-weight: 600;
		}

		&__subject-input {
			min-width: 0;
			flex: 1 1 auto;
			padding: 0;
			border: 0;
			outline: none;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			font-weight: 600;
		}

		&__message {
			display: flex;
			flex-direction: column;
			gap: 6px;
			padding: var(--space-slim);
		}

		&__body {
			width: 100%;
			padding: 0;
			border: 0;
			outline: none;
			resize: none;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			line-height: 1.5;
		}

		&__subject-input::placeholder,
		&__body::placeholder {
			padding-top: 0;
			color: var(--color-text--secondary);
			font-weight: 400;
		}

		&__values {
			display: flex;
			align-items: center;
			gap: var(--space-small);
			padding: var(--space-small) var(--space-slim);
			border-top: var(--border-base) solid var(--color-border);
			background: var(--color-surface--background--subtle);
		}

		&__values-icon {
			display: inline-flex;
			color: var(--color-conversation);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__values-label {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
		}

		&__chips {
			display: flex;
			min-width: 0;
			flex: 1 1 auto;
			flex-wrap: wrap;
			gap: 6px;
		}

		&__chip {
			display: inline-flex;
			height: 28px;
			align-items: center;
			gap: 6px;
			padding: 0 var(--space-slim) 0 9px;
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-circle);
			color: var(--color-heading);
			background: var(--color-surface);
			box-shadow: var(--shadow-button);
			font: inherit;
			font-size: var(--typography--fontSize-small);
			font-weight: 600;
			cursor: pointer;

			&:hover {
				background: var(--color-surface--hover);
			}

			&:active {
				background: var(--color-surface--active);
			}

			&:focus-visible {
				outline: none;
				box-shadow: var(--shadow-focus);
			}
		}

		&__chip-icon {
			display: inline-flex;
			color: var(--color-conversation);

			:global(svg) {
				width: 14px;
				height: 14px;
			}
		}

		&__count {
			flex: 0 0 auto;
			margin-left: auto;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
			font-variant-numeric: tabular-nums;
		}

		&__error {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__hint {
			margin: 0;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
