<script lang="ts">
	import RailCard from '$lib/components/layout/RailCard.svelte';
	import notesIcon from '@tabler/icons/outline/notes.svg?raw';
	import lockIcon from '@tabler/icons/outline/lock.svg?raw';
	import alertIcon from '@tabler/icons/outline/alert-circle.svg?raw';

	// One internal note written while a record is being created or edited. It saves with the record, so it
	// holds plain text rather than talking to the notes API the way NotesPanel does for a saved record. Its
	// field is the Notes panel's, grown taller, so a note looks the same before and after Save.
	let {
		value = $bindable(''),
		id = 'record-initial-note',
		title = 'Notes',
		icon = notesIcon,
		label = 'Leave an internal note for yourself or a team member',
		/** What the note saves with, for the hint line: "client", "request", "quote". */
		recordNoun = 'record',
		maxlength = 500,
		error = ''
	}: {
		value?: string;
		id?: string;
		title?: string;
		icon?: string;
		label?: string;
		recordNoun?: string;
		maxlength?: number;
		error?: string;
	} = $props();

	const remaining = $derived(maxlength - value.length);
</script>

<!-- eslint-disable svelte/no-at-html-tags -->
<RailCard
	tone="conversation"
	{title}
	{icon}
	description="Only your team sees this · saves with the {recordNoun}"
>
	<div class="form-notes" class:form-notes--invalid={Boolean(error)}>
		<textarea
			{id}
			class="form-notes__input"
			rows={3}
			{maxlength}
			placeholder={label}
			aria-label={label}
			aria-invalid={Boolean(error)}
			aria-describedby={error ? `${id}-error` : `${id}-count`}
			bind:value></textarea>
		<div class="form-notes__foot">
			<span class="form-notes__private">
				<span class="form-notes__icon" aria-hidden="true">{@html lockIcon}</span>Team only
			</span>
			<span class="form-notes__count" id={`${id}-count`}>{remaining} left</span>
		</div>
	</div>
	{#if error}
		<p class="form-notes__error" id={`${id}-error`} role="alert">
			<span class="form-notes__icon" aria-hidden="true">{@html alertIcon}</span>{error}
		</p>
	{/if}
</RailCard>

<style lang="scss">
	.form-notes {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: var(--space-slim) var(--space-slim) 10px;
		border: var(--border-base) solid var(--color-border);
		border-radius: var(--radius-base);
		background: var(--color-surface--background);
		cursor: text;
		transition:
			background var(--timing-quick),
			border-color var(--timing-quick);

		&:hover {
			border-color: var(--color-border--interactive--hover);
		}

		&:focus-within {
			border-color: var(--color-interactive);
			background: var(--color-surface);
			box-shadow: inset 0 0 0 0.5px var(--color-interactive);
		}

		&--invalid,
		&--invalid:hover,
		&--invalid:focus-within {
			border-color: var(--color-critical);
			box-shadow: inset 0 0 0 0.5px var(--color-critical);
		}

		&__input {
			width: 100%;
			min-height: calc(3 * 1.45em);
			padding: 0;
			border: 0;
			outline: none;
			resize: none;
			color: var(--color-heading);
			background: transparent;
			font: inherit;
			font-size: var(--typography--fontSize-base);
			line-height: 1.45;

			&::placeholder {
				padding-top: 0;
				color: var(--color-text--secondary);
			}
		}

		&__foot {
			display: flex;
			align-items: center;
			justify-content: space-between;
			gap: var(--space-small);
		}

		&__private {
			display: inline-flex;
			align-items: center;
			gap: 6px;
			color: var(--color-conversation--onSurface);
			font-size: var(--typography--fontSize-small);
			font-weight: 600;

			.form-notes__icon {
				color: var(--color-conversation);
			}
		}

		&__icon {
			display: inline-flex;

			:global(svg) {
				display: block;
				width: 14px;
				height: 14px;
			}
		}

		&__count {
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			font-weight: 500;
		}

		&__error {
			display: flex;
			align-items: center;
			gap: 6px;
			margin: var(--space-small) 0 0;
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
	}
</style>
