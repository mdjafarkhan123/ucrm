<script lang="ts">
	import type { Snippet } from 'svelte';
	import exclamationCircleIcon from '@tabler/icons/outline/exclamation-circle.svg?raw';

	let {
		value = $bindable(''),
		id,
		label,
		type = 'text',
		size = 'base',
		required = false,
		invalid = false,
		errorMessage = '',
		disabled = false,
		class: className = '',
		children,
		...rest
	}: {
		// A number field binds back a number, and an empty one binds back null, so the type covers what
		// the DOM actually hands over rather than only the text case.
		value?: string | number | null;
		id: string;
		label?: string;
		type?: string;
		size?: 'small' | 'base' | 'large';
		required?: boolean;
		invalid?: boolean;
		errorMessage?: string;
		disabled?: boolean;
		class?: string;
		children?: Snippet;
		[key: string]: unknown;
	} = $props();

	const ALWAYS_FLOATED_LABEL_TYPES = new Set(['date', 'time', 'datetime-local', 'month', 'week']);

	let describedBy = $derived(errorMessage ? `${id}-error` : undefined);
	// The label rests over the field until there is something to lift it clear. A placeholder counts: it
	// shows while the field is still empty, so without this the two sit on top of each other.
	let hasValue = $derived(
		Boolean(value) || ALWAYS_FLOATED_LABEL_TYPES.has(type) || Boolean(rest.placeholder)
	);
</script>

<div
	class={`input input--${size} ${className}`}
	class:input--has-value={hasValue}
	class:input--invalid={invalid}
	class:input--disabled={disabled}
>
	{#if label}<label class="input__label" for={id}
			>{label}{#if required}<span class="field-required" aria-hidden="true">*</span>{/if}</label
		>{/if}
	<div class="input__control">
		{#if children}{@render children()}{/if}
		<input
			{...rest}
			{id}
			{type}
			bind:value
			{disabled}
			aria-invalid={invalid}
			aria-required={required || undefined}
			aria-describedby={describedBy}
		/>
	</div>
	{#if errorMessage}<p class="input__error" id={`${id}-error`} role="alert">
			<!-- eslint-disable-next-line svelte/no-at-html-tags -->
			<span aria-hidden="true">{@html exclamationCircleIcon}</span>{errorMessage}
		</p>{/if}
</div>

<style lang="scss">
	.input {
		position: relative;
		width: 100%;
		font-size: var(--typography--fontSize-base);

		&__control {
			display: flex;
			align-items: center;
			min-height: var(--space-largest);
			border: var(--border-base) solid var(--color-border--interactive);
			border-radius: var(--radius-base);
			background: var(--color-surface);
			overflow: hidden;
		}
		&__label {
			position: absolute;
			z-index: var(--elevation-base);
			top: 50%;
			left: var(--space-base);
			max-width: calc(100% - var(--space-largest));
			overflow: hidden;
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-base);
			text-overflow: ellipsis;
			white-space: nowrap;
			transform: translateY(-50%);
			transition: all var(--timing-quick);
			pointer-events: none;
		}
		input {
			width: 100%;
			min-width: 0;
			padding: calc(var(--space-base) - var(--space-smallest)) var(--space-base);
			border: 0;
			outline: 0;
			color: var(--color-heading);
			background: transparent;
			line-height: 20px;
		}
		input:focus {
			outline: none;
		}
		&:focus-within .input__label,
		&--has-value .input__label {
			top: var(--space-smallest);
			color: var(--color-text--secondary);
			font-size: var(--typography--fontSize-small);
			transform: none;
		}
		&:focus-within input,
		&--has-value input {
			padding-top: calc(var(--space-base) + var(--space-smaller));
			padding-bottom: var(--space-small);
		}
		&:focus-within .input__control {
			box-shadow: var(--shadow-focus);
			z-index: var(--elevation-base);
		}
		&--small .input__control {
			min-height: 36px;
		}
		&--small input {
			padding: var(--space-small);
		}
		&--small .input__label {
			display: none;
		}
		&--large .input__control {
			min-height: var(--space-extravagant);
		}
		&--large input {
			padding: 14px 20px;
			font-size: var(--typography--fontSize-large);
		}
		&--invalid .input__control {
			border-color: var(--color-critical);
		}
		&--disabled .input__control {
			border-color: var(--color-border);
			background: var(--color-disabled--secondary);
		}
		&--disabled input {
			color: var(--color-disabled);
			-webkit-text-fill-color: var(--color-disabled);
		}
		&__error {
			display: flex;
			align-items: center;
			gap: var(--space-smaller);
			padding-top: var(--space-smaller);
			color: var(--color-critical);
			font-size: var(--typography--fontSize-small);
		}
		&__error span :global(svg) {
			width: 16px;
			height: 16px;
		}
	}
</style>
